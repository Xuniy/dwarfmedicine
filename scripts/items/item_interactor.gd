extends Node

const Item = preload("res://scripts/items/world_item.gd")

@export var reach: float = 2.5
@onready var player: CharacterBody3D = get_parent()
@onready var ray: RayCast3D = $"../PivotCamera/Camera3D/InteractionRay"
@onready var hud: CanvasLayer = $"../InteractionUI"
@onready var prompt: Label = $"../InteractionUI/Prompt"


func _ready() -> void:
	var local_player := player.is_multiplayer_authority()
	hud.visible = local_player
	set_physics_process(local_player)
	ray.add_exception(player)
	ray.target_position = Vector3(0, 0, -reach)


func get_held_item() -> Item:
	for item in get_tree().get_nodes_in_group("world_items"):
		if item.multiplayer == multiplayer and item.holder_peer_id == player.get_multiplayer_authority():
			return item as Item
	return null


func _physics_process(_delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		prompt.text = ""
		return
	var held := get_held_item()
	# Les zones ne doivent pas cacher les objets quand la main est libre.
	ray.set_collision_mask_value(3, held != null)
	ray.force_raycast_update()
	if held != null:
		var zone := ray.get_collider() as ItemDepositZone
		prompt.text = ("G : déposer — " if zone != null else "G : lâcher — ") + held.display_name
		if Input.is_action_just_pressed("drop_item"):
			if zone != null:
				zone.request_deposit()
			else:
				held.request_drop()
		return

	var target := ray.get_collider() as Item
	if target == null or target.holder_peer_id != 0 or target.collision.shape == null:
		prompt.text = ""
		return
	prompt.text = "E : prendre — " + target.display_name
	if Input.is_action_just_pressed("interact"):
		target.request_pick_up()
