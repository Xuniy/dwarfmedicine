class_name ItemDepositZone
extends Area3D

@onready var deposit_point: Marker3D = $DepositPoint

# Évite deux placements au même endroit avant la prochaine étape physique.
var _last_deposit_frame: int = -1

# Appelée quand le joueur appuie sur G en visant cette zone.
func request_deposit() -> void:
	if multiplayer.is_server():
		_try_deposit(multiplayer.get_unique_id())
	else:
		_request_deposit.rpc_id(1)


# Le client demande ; l'hôte décide.
@rpc("any_peer", "call_remote", "reliable")
func _request_deposit() -> void:
	if multiplayer.is_server():
		_try_deposit(multiplayer.get_remote_sender_id())


func _try_deposit(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _last_deposit_frame == Engine.get_physics_frames():
		return

	# 1. Retrouver le joueur qui a envoyé la demande.
	var player := _find_player(peer_id)
	if player == null:
		return

	# 2. Retrouver l'objet qu'il porte.
	var interactor := player.get_node("ItemInteractor")
	var held: WorldItem = interactor.get_held_item()

	if held == null or held.collision.shape == null:
		return

	# 3. Vérifier que ce joueur vise effectivement cette zone.
	var ray := player.get_node(
		"PivotCamera/Camera3D/InteractionRay"
	) as RayCast3D

	# Le raycast d'un joueur distant n'est pas piloté par les entrées de l'hôte.
	# Refaire la visée avec les couches monde, items et zones de dépôt.
	var sight := PhysicsRayQueryParameters3D.create(
		ray.global_position,
		ray.to_global(Vector3(0, 0, -interactor.reach)),
		WorldItem.WORLD_AND_ITEMS_MASK | 4,
		[player.get_rid()]
	)
	sight.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(sight)
	if hit.is_empty() or hit.collider != self:
		return

	# Vérifier aussi la distance jusqu'au point de dépôt.
	if ray.global_position.distance_to(
		deposit_point.global_position
	) > interactor.reach:
		return

	# 4. Vérifier la place disponible avant de déplacer l'objet.
	var destination := deposit_point.global_transform
	destination.basis = destination.basis.orthonormalized() * Basis.from_scale(held.global_basis.get_scale())
	var query := PhysicsShapeQueryParameters3D.new()

	query.shape = held.collision.shape
	query.transform = destination * held.collision.transform
	query.collision_mask = WorldItem.WORLD_AND_ITEMS_MASK
	query.exclude = [held.get_rid()]

	var obstacles := get_world_3d().direct_space_state.intersect_shape(
		query, 1
	)

	if not obstacles.is_empty():
		return


	# 5. Déposer l'objet et lui rendre sa physique.
	# La demande reçue suffit : ne pas relire le clavier sur le serveur.
	_last_deposit_frame = Engine.get_physics_frames()
	held.global_transform = destination
	held.holder_peer_id = 0
	held.linear_velocity = Vector3.ZERO
	held.angular_velocity = Vector3.ZERO
	held.sleeping = false
	held.reset_physics_interpolation()


func _find_player(peer_id: int) -> CharacterBody3D:
	for candidate in get_tree().get_nodes_in_group("players"):
		if (
			candidate.multiplayer == multiplayer
			and candidate.get_multiplayer_authority() == peer_id
		):
			return candidate as CharacterBody3D

	return null
