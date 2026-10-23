# godot --headless --path . --script res://tests/test_items.gd
extends SceneTree

const ITEM_SCENE = preload("res://Scenes/items/world_item.tscn")
const PLAYER_SCENE = preload("res://Scenes/player.tscn")
const POTION = preload("res://resources/items/potion.tres")
const STONE = preload("res://resources/items/stone.tres")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)


func add_box(parent: Node, size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	body.position = at
	return body


func make_world(world_name: String) -> SubViewport:
	var world := SubViewport.new()
	world.name = world_name
	world.own_world_3d = true
	root.add_child(world)
	add_box(world, Vector3(30, 1, 30), Vector3(0, -0.5, 0))
	return world


func add_player(world: Node, player_name: String, peer_id: int, at := Vector3.ZERO):
	var player = PLAYER_SCENE.instantiate()
	player.name = player_name
	player.set_multiplayer_authority(peer_id)
	world.add_child(player)
	player.position = at
	player.set_physics_process(false)
	player.get_node("ItemInteractor").set_physics_process(false)
	return player


func add_item(world: Node, item_name: String, definition: Resource, at: Vector3):
	var item = ITEM_SCENE.instantiate()
	item.name = item_name
	item.data = definition
	world.add_child(item)
	item.position = at
	return item


func wait_ticks(count: int) -> void:
	for i in range(count):
		await physics_frame


func run() -> void:
	await test_local_items()
	if not OS.get_cmdline_user_args().has("--local"):
		await test_network_items()
	print("Item test failures: ", failures)
	quit(0 if failures == 0 else 1)


func test_local_items() -> void:
	var world := make_world("Offline")
	var player = add_player(world, "Player", 1)
	var other = add_player(world, "Other", 2, Vector3(0.5, 0, 0))
	var item = add_item(world, "Potion", POTION, Vector3(0, 1, -1.5))
	var stone = add_item(world, "Stone", STONE, Vector3(0.5, 1, -1.5))
	await wait_ticks(3)
	check(item.global_position.y < 1.0 and not item.freeze, "loose item falls with physics")
	check(is_equal_approx(item.mass, POTION.mass) and item.collision.shape == POTION.collision_shape, "resource supplies mass and collision")
	var camera: Camera3D = player.get_node("PivotCamera/Camera3D")
	var to_item: Vector3 = item.global_position - camera.global_position
	player.look_pitch = atan2(to_item.y, -to_item.z)
	var interactor := player.get_node("ItemInteractor")
	var ray: RayCast3D = player.get_node("PivotCamera/Camera3D/InteractionRay")
	ray.force_raycast_update()
	check(ray.get_collider() == item, "camera ray targets nearby item")
	check(InputMap.action_get_events("interact")[0].physical_keycode == KEY_E and InputMap.action_get_events("drop_item")[0].physical_keycode == KEY_G, "E and G actions configured")
	# Le backend headless ne capture pas la souris : appeler la demande directement.
	item.request_pick_up()
	check(item.holder_peer_id == 1 and interactor.get_held_item() == item, "pickup request equips targeted item")
	await wait_ticks(2)
	check(item.freeze and item.collision_layer == 0 and item.collision_mask == 0, "held item suspends physics and collisions")
	var anchor: Node3D = player.get_node("PivotCamera/Camera3D/HandAnchor")
	check(item.global_transform.is_equal_approx(anchor.global_transform * POTION.get_held_transform()), "item follows hand using resource offset")
	check(not stone._try_pick_up(1), "one item per player")
	check(not item._try_pick_up(2) and not item._try_drop(2), "other player cannot steal or drop held item")
	player.look_pitch = -0.25
	await wait_ticks(2)
	check(item.global_transform.is_equal_approx(anchor.global_transform * POTION.get_held_transform()), "held item follows camera pitch")
	var blocker := add_box(world, Vector3(0.6, 0.6, 0.6), item.global_position)
	await wait_ticks(2)
	check(not item._try_drop(1), "dropping inside an obstacle is refused")
	blocker.queue_free()
	await wait_ticks(2)
	item.request_drop()
	check(item.holder_peer_id == 0 and not item.freeze and item.collision_layer == 2, "drop request restores physics and collisions")
	var released_height: float = item.position.y
	await wait_ticks(8)
	check(item.position.y < released_height, "released item falls again")
	stone.position = Vector3(0.5, 1.0, -8)
	await wait_ticks(2)
	check(not stone._try_pick_up(1), "distant item cannot be picked up")
	stone.position = Vector3(0, 1.0, -1.5)
	stone.linear_velocity = Vector3.ZERO
	player.look_pitch = 0.0
	var wall := add_box(world, Vector3(3, 3, 0.1), Vector3(0, 1, -0.8))
	await wait_ticks(2)
	check(not stone._try_pick_up(1), "item behind wall cannot be picked up")
	wall.queue_free()
	await wait_ticks(2)
	item.data = STONE
	check(is_equal_approx(item.mass, STONE.mass) and item.collision.shape == STONE.collision_shape and item.visual.get_child_count() == 1 and item.visual.get_child(0).name == "StoneModel", "changing resource replaces model, mass and collision")
	check(is_equal_approx(POTION.mass, 0.3) and is_equal_approx(POTION.collision_shape.height, 0.36), "item state does not modify shared definition")
	check(stone._try_pick_up(2), "second player can pick up available item")
	other.queue_free()
	await wait_ticks(3)
	check(stone.holder_peer_id == 0 and not stone.freeze, "item falls when holder disappears")
	world.queue_free()
	await process_frame


func test_network_items() -> void:
	var host := make_world("Host")
	var guest := make_world("Guest")
	var host_api := SceneMultiplayer.new()
	var guest_api := SceneMultiplayer.new()
	set_multiplayer(host_api, host.get_path())
	set_multiplayer(guest_api, guest.get_path())
	var server_peer := ENetMultiplayerPeer.new()
	var error := server_peer.create_server(0, 1)
	check(error == OK, "ENet test server starts")
	if error != OK:
		host.queue_free()
		guest.queue_free()
		return
	host_api.multiplayer_peer = server_peer
	var client_peer := ENetMultiplayerPeer.new()
	error = client_peer.create_client("127.0.0.1", server_peer.get_host().get_local_port())
	check(error == OK, "ENet test client starts")
	if error != OK:
		server_peer.close()
		host.queue_free()
		guest.queue_free()
		return
	guest_api.multiplayer_peer = client_peer
	await wait_ticks(15)
	check(client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "ENet peers connect")
	var guest_id := guest_api.get_unique_id()
	add_player(host, "HostPlayer", 1, Vector3(4, 0, 0))
	add_player(guest, "HostPlayer", 1, Vector3(4, 0, 0))
	var host_guest_player = add_player(host, "GuestPlayer", guest_id)
	var guest_player = add_player(guest, "GuestPlayer", guest_id)
	var host_item = add_item(host, "Potion", POTION, Vector3(0, 1, -1.5))
	var guest_item = add_item(guest, "Potion", POTION, Vector3(0, 1, -1.5))
	await wait_ticks(8)
	check(not host_item.freeze and guest_item.freeze, "only server simulates loose items")
	guest_item.request_pick_up()
	await wait_ticks(10)
	check(host_item.holder_peer_id == guest_id and guest_item.holder_peer_id == guest_id, "client pickup RPC is accepted and replicated")
	guest_player.look_pitch = -0.2
	await wait_ticks(10)
	check(is_equal_approx(host_guest_player.look_pitch, -0.2), "holder camera pitch replicates to host")
	check(host_item.freeze and guest_item.freeze, "held item frozen on both peers")
	check(host_item.global_position.distance_to(guest_item.global_position) < 0.02, "both peers see same held position")
	host_item.request_drop()
	check(host_item.holder_peer_id == guest_id, "host cannot drop client's held item")
	guest_item.request_drop()
	await wait_ticks(10)
	check(host_item.holder_peer_id == 0 and guest_item.holder_peer_id == 0, "client drop RPC is accepted and replicated")
	check(not host_item.freeze and guest_item.freeze, "drop restores simulation only on server")
	check(host_item.global_position.distance_to(guest_item.global_position) < 0.2, "dropped item position replicates")
	host.queue_free()
	guest.queue_free()
	await process_frame
	server_peer.close()
	client_peer.close()
