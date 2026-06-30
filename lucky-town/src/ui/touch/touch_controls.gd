extends CanvasLayer
## Touch overlay for mobile / web: a movement stick plus action buttons.
##
## Each button injects the very same input *action* the keyboard would, via
## `Input.parse_input_event`, so nothing downstream knows or cares that the
## input came from a touchscreen — the player controller and every panel react
## exactly as on desktop. The overlay hides itself on desktop unless the build
## is running on the web (where a phone browser is the likely client).

@onready var _root: Control = $Root
@onready var _interact: Button = $Root/RightCluster/InteractButton
@onready var _board: Button = $Root/RightCluster/Grid/BoardButton
@onready var _auction: Button = $Root/RightCluster/Grid/AuctionButton
@onready var _stats: Button = $Root/RightCluster/Grid/StatsButton
@onready var _menu: Button = $Root/RightCluster/Grid/MenuButton

var _touch_wanted := false


func _ready() -> void:
	_interact.pressed.connect(_fire.bind("interact"))
	_board.pressed.connect(_fire.bind("toggle_board"))
	_auction.pressed.connect(_fire.bind("toggle_auction"))
	_stats.pressed.connect(_fire.bind("toggle_stats"))
	_menu.pressed.connect(_fire.bind("toggle_menu"))
	# Show on touchscreens and on the web; keep desktop clean.
	_touch_wanted = _wants_touch_ui()
	_root.visible = _touch_wanted
	# Hide the overlay while a full-screen panel is open so it can't overlap or
	# steal touches; panels carry their own on-screen Close button.
	EventBus.ui_modal_changed.connect(_on_modal_changed)


func _on_modal_changed(is_open: bool) -> void:
	_root.visible = _touch_wanted and not is_open


func _wants_touch_ui() -> bool:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return true
	return DisplayServer.is_touchscreen_available()


## Inject a one-shot action press+release so edge-triggered handlers
## (is_action_pressed in _unhandled_input) fire just as for a key tap.
func _fire(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
