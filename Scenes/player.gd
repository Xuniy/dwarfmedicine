extends CharacterBody3D

@onready var animation_tree: AnimationTree = $DwarfM_Dummy/AnimationTree
@onready var animation_state: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
	
const SPEED = 5.0
const JUMP_VELOCITY = 4.5

func _ready() -> void:
	animation_tree.active = true
	animation_state.start("Idle")

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
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
