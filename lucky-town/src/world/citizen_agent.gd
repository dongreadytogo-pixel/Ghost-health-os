extends CharacterBody3D
## The visible avatar of an AI `Citizen`.
##
## A thin view bound to a `Citizen` model by id. The brain/actuator decide and
## apply *what* the citizen does (in `WorldDirector`); this node only makes the
## decision *visible* — wandering to a destination so the streets are never
## empty. Off-screen citizens have no agent at all, yet are still fully
## simulated, so the city scales without spawning thousands of nodes.

@export var move_speed: float = 3.0

var citizen_id: String = ""

var _target: Vector3
var _wander_bounds := Vector3(20, 0, 20)


func bind(id: String) -> void:
	citizen_id = id
	_pick_new_target()
	EventBus.citizen_action_started.connect(_on_action)


func _physics_process(delta: float) -> void:
	var to_target := _target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.5:
		_pick_new_target()
		return
	var dir := to_target.normalized()
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	velocity.y -= 9.8 * delta
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 8.0 * delta)
	move_and_slide()


func _pick_new_target() -> void:
	var rng := RngService.stream("wander:%s" % citizen_id)
	_target = Vector3(
		rng.randf_range(-_wander_bounds.x, _wander_bounds.x),
		0.0,
		rng.randf_range(-_wander_bounds.z, _wander_bounds.z)
	)


func _on_action(id: String, action: String) -> void:
	if id != citizen_id:
		return
	# A hook for future expression (emotes/speech bubbles per action).
	if action == "gamble" or action == "shop":
		_pick_new_target()
