class_name WorldItem
extends RigidBody3D

const ITEM_LAYER := 2
const WORLD_AND_ITEMS_MASK := 3

@export var display_name: String = "Objet"
@export var held_position: Vector3 = Vector3.ZERO
@export var held_rotation_degrees: Vector3 = Vector3.ZERO

# Seul le serveur écrit cette valeur ; les clients la reçoivent par réplication.
var holder_peer_id: int = 0:
	set(value):
		holder_peer_id = value
		if is_node_ready():
			_update_physics_state()

@onready var visual: Node3D = $Visual
@onready var collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_update_physics_state()


func _physics_process(_delta: float) -> void:
	_update_physics_state()
	if holder_peer_id == 0:
		return
	var holder := _find_player(holder_peer_id)
	if holder != null:
		_follow_hand(holder)
	elif multiplayer.is_server():
		# Le joueur a quitté : l'objet reste dans le monde et retombe.
		holder_peer_id = 0
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		sleeping = false


func _process(_delta: float) -> void:
	# Suivre aussi la caméra entre deux ticks physiques pour une vue fluide.
	if holder_peer_id != 0:
		var holder := _find_player(holder_peer_id)
		if holder != null:
			_follow_hand(holder)


func get_held_transform() -> Transform3D:
	return Transform3D(Basis.from_euler(held_rotation_degrees * (PI / 180.0)), held_position)


func _update_physics_state() -> void:
	var held := holder_peer_id != 0
	var should_freeze := held or not multiplayer.is_server()
	if freeze != should_freeze:
		freeze = should_freeze
	collision_layer = 0 if held else ITEM_LAYER
	collision_mask = 0 if held else WORLD_AND_ITEMS_MASK


func _find_player(peer_id: int) -> CharacterBody3D:
	for player in get_tree().get_nodes_in_group("players"):
		if player.multiplayer == multiplayer and player.get_multiplayer_authority() == peer_id:
			return player as CharacterBody3D
	return null


func _follow_hand(player: CharacterBody3D) -> void:
	var anchor := player.get_node("PivotCamera/Camera3D/HandAnchor") as Node3D
	global_transform = anchor.global_transform * get_held_transform()


func request_pick_up() -> void:
	if multiplayer.is_server():
		_try_pick_up(multiplayer.get_unique_id())
	else:
		_request_pick_up.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_pick_up() -> void:
	if multiplayer.is_server():
		_try_pick_up(multiplayer.get_remote_sender_id())


func _try_pick_up(peer_id: int) -> bool:
	if not multiplayer.is_server() or holder_peer_id != 0 or collision.shape == null:
		return false
	var player := _find_player(peer_id)
	if player == null:
		return false
	for item in get_tree().get_nodes_in_group("world_items"):
		if item.multiplayer == multiplayer and item.holder_peer_id == peer_id:
			return false

	# Le serveur vérifie portée et visibilité, même pour une demande distante.
	var camera := player.get_node("PivotCamera/Camera3D") as Camera3D
	var interactor := player.get_node("ItemInteractor")
	if camera.global_position.distance_to(global_position) > interactor.reach:
		return false
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, global_position)
	ray.collision_mask = WORLD_AND_ITEMS_MASK
	ray.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.collider != self:
		return false

	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	holder_peer_id = peer_id
	_follow_hand(player)
	reset_physics_interpolation()
	return true


func request_drop() -> void:
	if multiplayer.is_server():
		_try_drop(multiplayer.get_unique_id())
	else:
		_request_drop.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_drop() -> void:
	if multiplayer.is_server():
		_try_drop(multiplayer.get_remote_sender_id())


func _try_drop(peer_id: int) -> bool:
	if not multiplayer.is_server() or holder_peer_id != peer_id or peer_id == 0:
		return false
	var player := _find_player(peer_id)
	if player == null:
		return false
	_follow_hand(player)

	# Ne pas réactiver la physique si la main se trouve dans un mur.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform
	query.collision_mask = WORLD_AND_ITEMS_MASK
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false

	holder_peer_id = 0
	linear_velocity = player.velocity
	angular_velocity = Vector3.ZERO
	sleeping = false
	reset_physics_interpolation()
	return true
