class_name VirtualJoystick
extends Control
## On-screen analog stick that drives the movement actions.
##
## Mobile/web have no WASD, so this feeds the same `move_*` input actions the
## desktop keyboard does — the player controller is unchanged. It is a *dynamic*
## stick: the base appears wherever the thumb lands inside this control's rect,
## which is the most comfortable pattern for touchscreens. Works with both touch
## (real devices) and mouse (desktop browser testing).

@export var max_radius: float = 90.0
@export var deadzone: float = 0.18

var _active := false
var _finger := -1            # touch index, or -2 for mouse
var _base := Vector2.ZERO
var _knob := Vector2.ZERO
var _output := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not _active:
			_begin(event.position, event.index)
		elif not event.pressed and event.index == _finger:
			_end()
	elif event is InputEventScreenDrag and event.index == _finger:
		_move(event.position)
	elif event is InputEventMouseButton:
		if event.pressed and not _active:
			_begin(event.position, -2)
		elif not event.pressed and _finger == -2:
			_end()
	elif event is InputEventMouseMotion and _finger == -2 and _active:
		_move(event.position)


func _begin(pos: Vector2, finger: int) -> void:
	_active = true
	_finger = finger
	_base = pos
	_knob = pos
	_output = Vector2.ZERO
	queue_redraw()


func _move(pos: Vector2) -> void:
	var offset := pos - _base
	if offset.length() > max_radius:
		offset = offset.normalized() * max_radius
	_knob = _base + offset
	_output = offset / max_radius
	if _output.length() < deadzone:
		_output = Vector2.ZERO
	queue_redraw()


func _end() -> void:
	_active = false
	_finger = -1
	_output = Vector2.ZERO
	_release_all()
	queue_redraw()


func _process(_delta: float) -> void:
	if _active:
		_apply(_output)


func _apply(v: Vector2) -> void:
	_set_axis("move_right", "move_left", v.x)
	_set_axis("move_back", "move_forward", v.y)


func _set_axis(positive: String, negative: String, value: float) -> void:
	if value > 0.0:
		Input.action_release(negative)
		Input.action_press(positive, value)
	elif value < 0.0:
		Input.action_release(positive)
		Input.action_press(negative, -value)
	else:
		Input.action_release(positive)
		Input.action_release(negative)


func _release_all() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(action)


func _draw() -> void:
	if _active:
		draw_circle(_base, max_radius, Color(1, 1, 1, 0.12))
		draw_circle(_knob, max_radius * 0.4, Color(1, 1, 1, 0.35))
	else:
		# A faint hint ring at rest so the player knows where to thumb.
		var home := size * 0.5
		draw_circle(home, max_radius, Color(1, 1, 1, 0.06))
		draw_circle(home, max_radius * 0.4, Color(1, 1, 1, 0.12))
