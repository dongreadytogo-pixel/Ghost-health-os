extends CanvasLayer
## Persistent heads-up display: money, date/time, and transient notifications.
##
## The HUD is a pure *subscriber*: it never reaches into game systems, it only
## listens to the `EventBus` and reflects state. That keeps presentation fully
## decoupled — the same signals that drive this HUD could drive a phone UI or a
## spectator view later.

@onready var _money_label: Label = $Root/TopBar/MoneyLabel
@onready var _time_label: Label = $Root/TopBar/TimeLabel
@onready var _prompt_label: Label = $Root/PromptLabel
@onready var _toast_label: Label = $Root/ToastLabel

var _toast_timer := 0.0


func _ready() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.hour_ticked.connect(_on_time_changed)
	EventBus.weather_changed.connect(_on_weather_changed)
	EventBus.notification_posted.connect(_on_notification)
	_refresh_money()
	_refresh_time()


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_label.text = ""


func _on_money_changed(owner_id: String, balance: int, _delta: int) -> void:
	if owner_id == GameState.player_id:
		_money_label.text = "$ %s" % Money.of(balance).format_full()


func _on_time_changed(_day: int, _hour: int) -> void:
	_refresh_time()


func _on_weather_changed(_weather: int) -> void:
	_refresh_time()


func _on_notification(text: String, severity: int) -> void:
	# Low-severity messages (prompts) sit in the prompt slot; others toast.
	if severity <= 0 and text.begins_with("Press"):
		_prompt_label.text = text
		return
	_toast_label.text = text
	_toast_timer = 3.0


func _refresh_money() -> void:
	_money_label.text = "$ %s" % Money.of(Economy.balance(GameState.player_id)).format_full()


func _refresh_time() -> void:
	_time_label.text = "Day %d  %s  %s  %s" % [
		GameClock.day, GameClock.time_string(), GameClock.season_name(), WorldDirector.weather_name(),
	]
