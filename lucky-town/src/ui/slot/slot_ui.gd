extends Control
## Interactive slot-machine screen.
##
## A self-contained panel that lets the player choose a bet and spin. It calls
## `SlotService` (the same rules the AI uses) and renders the resulting grid and
## winnings. Reel animation is deliberately simple in Phase 1; the data model
## already carries everything a richer animation would need.

signal closed

@onready var _title: Label = $Panel/VBox/Title
@onready var _grid: GridContainer = $Panel/VBox/Grid
@onready var _bet_label: Label = $Panel/VBox/BetRow/BetLabel
@onready var _result_label: Label = $Panel/VBox/ResultLabel
@onready var _jackpot_label: Label = $Panel/VBox/JackpotLabel

var _machine_id: String = ""
var _config: SlotMachineConfig
var _bet: int = 10
var _actor: Node = null


func open(machine_id: String, actor: Node = null) -> void:
	_machine_id = machine_id
	_actor = actor
	_config = DataRegistry.slot_config(machine_id)
	if _config == null:
		close()
		return
	_bet = _config.min_bet
	_title.text = _config.display_name
	_setup_grid()
	_refresh()
	show()


func _setup_grid() -> void:
	_grid.columns = _config.reel_count()
	for child in _grid.get_children():
		child.queue_free()
	for _i in _config.reel_count() * _config.rows:
		var cell := Label.new()
		cell.text = "?"
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.custom_minimum_size = Vector2(64, 64)
		_grid.add_child(cell)


func _refresh() -> void:
	_bet_label.text = "Bet: %d" % _bet
	_jackpot_label.text = "Jackpot: %s" % Money.of(Economy.jackpot(_machine_id)).format_short()


func _on_bet_up_pressed() -> void:
	_bet = _config.clamp_bet(_bet + _config.bet_step)
	_refresh()


func _on_bet_down_pressed() -> void:
	_bet = _config.clamp_bet(_bet - _config.bet_step)
	_refresh()


func _on_spin_pressed() -> void:
	var outcome := SlotService.spin(_machine_id, GameState.player_id, _bet)
	if not outcome.ok:
		_result_label.text = "Cannot spin: %s" % outcome.reason
		return
	_render_result(outcome.result)
	_refresh()


func _render_result(result: SlotSpinResult) -> void:
	# grid is column-major (per reel); GridContainer fills row-major.
	for row in _config.rows:
		for reel in _config.reel_count():
			var index := row * _config.reel_count() + reel
			var cell := _grid.get_child(index) as Label
			cell.text = String(result.grid[reel][row])
	if result.jackpot_won:
		_result_label.text = "JACKPOT! +%s" % Money.of(result.jackpot_amount).format_full()
	elif result.is_win():
		_result_label.text = "WIN +%s" % Money.of(result.total_payout).format_full()
	else:
		_result_label.text = "No win. Try again!"


func _on_close_pressed() -> void:
	close()


func close() -> void:
	if _actor:
		_actor.input_locked = false
	hide()
	closed.emit()
