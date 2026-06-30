extends CanvasLayer
## Player statistics and achievements screen (toggle with G).
##
## A read-only summary of the player's lifetime stats plus the achievement list
## with locked/unlocked state. Like the other panels it is a pure view that
## reads the authoritative model and rebuilds on `evaluated` / relevant events.

@onready var _root: Control = $Root
@onready var _stats_label: Label = $Root/Panel/Margin/VBox/StatsLabel
@onready var _progress_label: Label = $Root/Panel/Margin/VBox/ProgressLabel
@onready var _ach_list: VBoxContainer = $Root/Panel/Margin/VBox/Scroll/AchList


func _ready() -> void:
	_root.hide()
	AchievementSystem.evaluated.connect(_refresh_if_visible)
	EventBus.achievement_unlocked.connect(_refresh2)
	$Root/Panel/Margin/VBox/CloseButton.pressed.connect(_close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_stats"):
		toggle()


func toggle() -> void:
	if _root.visible:
		_close()
	else:
		_open()


func _open() -> void:
	_root.show()
	GameClock.set_paused(true)
	EventBus.ui_modal_changed.emit(true)
	_refresh()


func _close() -> void:
	_root.hide()
	GameClock.set_paused(false)
	EventBus.ui_modal_changed.emit(false)


func _refresh2(_a, _b) -> void:
	_refresh_if_visible()


func _refresh_if_visible() -> void:
	if _root.visible:
		_refresh()


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	var player := GameState.player()
	if player == null:
		return
	var stats: Dictionary = player.stats
	var memory: Dictionary = player.memory
	_stats_label.text = "\n".join([
		"Cash: $%s" % Money.of(Economy.balance(player.id)).format_full(),
		"Net worth: $%s" % Money.of(_net_worth(player)).format_full(),
		"Total earned: $%s" % Money.of(int(stats.get("total_earned", 0))).format_full(),
		"Total spent: $%s" % Money.of(int(stats.get("total_spent", 0))).format_full(),
		"Slot wins / losses: %d / %d" % [int(memory.get("slot_wins", 0)), int(memory.get("slot_losses", 0))],
		"Net gambling: $%s" % Money.of(int(memory.get("net_gambling", 0))).format_short(),
		"Plots owned: %d   Buildings built: %d" % [player.plot_ids.size(), int(stats.get("buildings_built", 0))],
		"Pets owned: %d   Pets bred: %d" % [player.pet_ids.size(), int(stats.get("pets_bred", 0))],
		"Days lived: %d" % int(stats.get("days_lived", 0)),
	])
	_progress_label.text = "Achievements: %d / %d" % [AchievementSystem.unlocked_count(), AchievementSystem.total_count()]
	_render_achievements()


func _render_achievements() -> void:
	for child in _ach_list.get_children():
		child.queue_free()
	for id in DataRegistry.ids("achievements"):
		var def := DataRegistry.get_def("achievements", id)
		var done := AchievementSystem.is_unlocked(id)
		var mark := "✓" if done else "•"
		var lbl := Label.new()
		lbl.text = "%s  %s — %s" % [mark, def.get("title", id), def.get("description", "")]
		if not done:
			lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.62))
		_ach_list.add_child(lbl)


func _net_worth(player: Citizen) -> int:
	var worth := Economy.balance(player.id)
	for plot_id in player.plot_ids:
		var plot := GameState.get_plot(plot_id)
		if plot:
			worth += plot.appraised_value()
	for pet_id in player.pet_ids:
		var pet := GameState.get_pet(pet_id)
		if pet:
			worth += pet.market_value()
	return worth
