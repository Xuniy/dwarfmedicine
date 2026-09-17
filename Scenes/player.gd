extends CharacterBody3D

@onready var animation_tree: AnimationTree = $DwarfM_Dummy/AnimationTree
@onready var animation_state: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
	
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
@export var sensis_mouse: float = 0.002
@onready var camera_pivot: Node3D = $PivotCamera



func _ready() -> void:
	animation_tree.active = true
	animation_state.start("Idle")
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
		camera_pivot.rotate_x(-event.screen_relative.y * sensis_mouse)

		# Empêche de retourner la caméra.
		camera_pivot.rotation.x = clampf(camera_pivot.rotation.x,deg_to_rad(-85.0),deg_to_rad(85.0))

func _physics_process(delta: float) -> void:

	if not is_on_floor():
		velocity += get_gravity() * delta


	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var target_state = "Run" if horizontal_speed > 0.1 else "Idle"

	if animation_state.get_current_node() != target_state:
		animation_state.travel(target_state)
	move_and_slide()
