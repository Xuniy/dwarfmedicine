extends Node3D

const PORT := 7777
const PLAYER_SCENE := preload("res://Scenes/player.tscn")

@onready var players: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner


func _ready() -> void:
	spawner.spawn_function = _create_player

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_return_to_menu)
	multiplayer.server_disconnected.connect(_return_to_menu)


func host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, 1) # Un invité + l'hôte.

	if error != OK:
		push_error("Impossible d'héberger : " + error_string(error))
		return

	multiplayer.multiplayer_peer = peer
	$Menu.hide()
	spawner.spawn(1) # L'identifiant du serveur est toujours 1.


func join_game(address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), PORT)

	if error != OK:
		push_error("Impossible de rejoindre : " + error_string(error))
		return

	multiplayer.multiplayer_peer = peer
	$Menu.hide()


func _create_player(peer_id: int) -> Node:
	var player := PLAYER_SCENE.instantiate()

	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.position = Vector3(-1.5 if peer_id == 1 else 1.5, 0.1, 0)

	# Le spawner ajoutera lui-même le joueur à Players.
	return player


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		spawner.spawn(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		var player := players.get_node_or_null(str(peer_id))
		if player:
			player.queue_free()


func _return_to_menu() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene.call_deferred()


func _on_heberger_pressed() -> void:
	host_game()


func _on_rejoindre_pressed() -> void:
	join_game($Menu/AdresseIP.text)
