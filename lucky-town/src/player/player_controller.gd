extends CharacterBody3D
## Third-person walking controller for the player avatar.
##
## Phase 1 movement: the player physically walks the city in real time (WASD),
## and presses Interact (E) near a building to open its management screen. The
## controller is intentionally thin — it owns *input and motion only*; what an
## interactable does is the interactable's concern. This keeps the player
## decoupled from the city's content and ready for a future networked avatar.

@export var move_speed: float = 5.0
@export var acceleration: float = 12.0
@export var rotation_speed: float = 10.0
@export var interact_range: float = 2.5

## Set true while a full-screen UI (slot machine, shop) is open, to freeze input.
var input_locked: bool = false

@onready var _camera_pivot: Node3D = $CameraPivot if has_node("CameraPivot") else null

var _nearby_interactable: Node = null


func _physics_process(delta: float) -> void:
	if input_locked:
		velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)
		move_and_slide()
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y)
	if _camera_pivot:
		direction = direction.rotated(Vector3.UP, _camera_pivot.rotation.y)

	var target_velocity := direction * move_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	velocity.y -= 9.8 * delta  # gravity keeps us grounded on slopes

	if direction.length() > 0.1:
		var target_yaw := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, rotation_speed * delta)

	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return
	if event.is_action_pressed("interact") and _nearby_interactable:
		_nearby_interactable.interact(self)


## Called by an `Interactable` area when the player enters/leaves its range.
func set_nearby_interactable(node: Node) -> void:
	_nearby_interactable = node
	if node:
		EventBus.notification_posted.emit("Press E: %s" % node.prompt_text(), 0)


func clear_nearby_interactable(node: Node) -> void:
	if _nearby_interactable == node:
		_nearby_interactable = null
