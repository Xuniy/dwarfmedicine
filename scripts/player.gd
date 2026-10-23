extends CharacterBody3D

@onready var animation_tree: AnimationTree = $DwarfM_Dummy/AnimationTree
@onready var animation_state: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
@onready var camera: Camera3D = $PivotCamera/Camera3D
@onready var head_mesh: MeshInstance3D = \
	$DwarfM_Dummy/Rig/GeneralSkeleton/DwarfM_HeadMesh
@onready var barbe_mesh: MeshInstance3D = \
	$DwarfM_Dummy/Rig/GeneralSkeleton/DwarfM_BeardMesh01
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
@export var sensis_mouse: float = 0.002
@export var crouch_speed: float = 2.0
@export var crouch_height: float = 1.0
@export var crouch_camera_height: float = 0.75
@export var camera_height_transition_speed: float = 12.0
@onready var camera_pivot: Node3D = $PivotCamera
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Cette propriété est aussi reçue par le MultiplayerSynchronizer.
var is_crouching: bool = false:
	set(value):
		if is_crouching == value:
			return
		is_crouching = value
		if is_node_ready():
			_apply_crouch_collision()

var _capsule: CapsuleShape3D
var _standing_capsule: CapsuleShape3D
var _standing_collision_position: Vector3
var _standing_camera_height: float
var _crouching_height: float

var look_pitch: float = 0.0:
	set(value):
		look_pitch = clampf(value, deg_to_rad(-85.0), deg_to_rad(85.0))
		if is_node_ready():
			camera_pivot.rotation.x = look_pitch


func _ready() -> void:
	# Chaque joueur doit modifier sa propre capsule, sans affecter les autres.
	_standing_capsule = collision_shape.shape.duplicate() as CapsuleShape3D
	_capsule = _standing_capsule.duplicate() as CapsuleShape3D
	collision_shape.shape = _capsule
	_standing_collision_position = collision_shape.position
	_standing_camera_height = camera_pivot.position.y
	_crouching_height = clampf(crouch_height, _capsule.radius * 2.0, _capsule.height)
	_apply_crouch_collision()
	camera_pivot.rotation.x = look_pitch

	animation_tree.active = true
	animation_state.start("Idle")

	var local_player := is_multiplayer_authority()

	camera.current = local_player
	set_process_unhandled_input(local_player)
	set_physics_process(local_player)

	# Pour une première personne permanente :
	head_mesh.visible = not local_player
	barbe_mesh.visible = not local_player

	if local_player:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	# Échap libère le curseur.
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	# Un clic gauche capture à nouveau la souris.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion:
		# Gauche / droite : tourne tout le personnage.
		rotate_y(-event.screen_relative.x * sensis_mouse)

		# Haut / bas : incline uniquement la caméra.
		# L'inclinaison est synchronisée pour placer les objets tenus à distance.
		look_pitch -= event.screen_relative.y * sensis_mouse

func _physics_process(delta: float) -> void:
	if Input.is_action_pressed("crouch"):
		is_crouching = true
	elif is_crouching and _can_stand():
		is_crouching = false

	if not is_on_floor():
		velocity += get_gravity() * delta


	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY

	var movement_speed := crouch_speed if is_crouching else SPEED
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * movement_speed
		velocity.z = direction.z * movement_speed
	else:
		velocity.x = move_toward(velocity.x, 0, movement_speed)
		velocity.z = move_toward(velocity.z, 0, movement_speed)
		
	move_and_slide()

func _process(delta: float) -> void:
	var target_camera_height := crouch_camera_height if is_crouching else _standing_camera_height
	camera_pivot.position.y = lerpf(
		camera_pivot.position.y,
		target_camera_height,
		1.0 - exp(-camera_height_transition_speed * delta)
	)

	var speed := Vector2(velocity.x, velocity.z).length()
	var target_state: String
	if is_crouching:
		target_state = "Crouch_Forward" if speed > 0.1 else "Crouch_Idle"
	else:
		target_state = "Run" if speed > 0.1 else "Idle"

	if animation_state.get_current_node() != target_state:
		animation_state.travel(target_state)


func _apply_crouch_collision() -> void:
	_capsule.height = _crouching_height if is_crouching else _standing_capsule.height
	# Abaisser le centre garde les pieds au même endroit.
	collision_shape.position = _standing_collision_position
	collision_shape.position.y -= (_standing_capsule.height - _capsule.height) * 0.5


func _can_stand() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _standing_capsule
	query.transform = collision_shape.global_transform
	query.transform.origin = to_global(_standing_collision_position)
	# Une petite marge vers le haut évite de détecter le sol sous les pieds.
	query.transform.origin += up_direction * 0.01
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
