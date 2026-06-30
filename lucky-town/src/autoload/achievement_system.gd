extends Node
## Tracks the player's lifetime achievements.
##
## Achievements are data (`data/achievements/*.json`): a metric and a threshold.
## The system recomputes the player's metric values whenever a relevant fact
## fires on the `EventBus` and unlocks any newly-satisfied achievement once.
## Metrics are read straight from the authoritative player state (stats, memory,
## possessions) so there is no parallel bookkeeping to drift out of sync — the
## one exception is the jackpot tally, which is a transient event, counted here.

signal evaluated()

var unlocked: Dictionary = {}     # achievement_id -> true
var _jackpot_count: int = 0


func _ready() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.building_constructed.connect(_on_simple2)
	EventBus.property_purchased.connect(_on_simple3)
	EventBus.pet_acquired.connect(_on_simple2)
	EventBus.pet_bred.connect(_on_simple3)
	EventBus.slot_spun.connect(_on_simple3)
	EventBus.slot_jackpot_won.connect(_on_jackpot)
	EventBus.day_started.connect(_on_simple1)


func unlocked_count() -> int:
	return unlocked.size()


func total_count() -> int:
	return DataRegistry.ids("achievements").size()


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


# --- Event hooks (various arities, all just trigger a re-evaluation) ----------

func _on_money_changed(owner_id: String, _balance: int, _delta: int) -> void:
	if owner_id == GameState.player_id:
		evaluate()


func _on_jackpot(_machine: String, player_id: String, _amount: int) -> void:
	if player_id == GameState.player_id:
		_jackpot_count += 1
	evaluate()


func _on_simple1(_a) -> void:
	evaluate()


func _on_simple2(_a, _b) -> void:
	evaluate()


func _on_simple3(_a, _b, _c) -> void:
	evaluate()


# --- Evaluation --------------------------------------------------------------

func evaluate() -> void:
	if not GameState.initialised:
		return
	for id in DataRegistry.ids("achievements"):
		if unlocked.has(id):
			continue
		var def := DataRegistry.get_def("achievements", id)
		if _metric_value(def.get("metric", "")) >= int(def.get("threshold", 0)):
			_unlock(id, def.get("title", id))
	evaluated.emit()


func _unlock(id: String, title: String) -> void:
	unlocked[id] = true
	EventBus.achievement_unlocked.emit(id, title)
	EventBus.notification_posted.emit("Achievement: %s" % title, 2)


func _metric_value(metric: String) -> int:
	var player := GameState.player()
	if player == null:
		return 0
	match metric:
		"net_worth":
			return _net_worth(player)
		"total_earned":
			return int(player.stats.get("total_earned", 0))
		"slot_wins":
			return int(player.memory.get("slot_wins", 0))
		"jackpots":
			return _jackpot_count
		"plots_owned":
			return player.plot_ids.size()
		"buildings_built":
			return int(player.stats.get("buildings_built", 0))
		"pets_owned":
			return player.pet_ids.size()
		"pets_bred":
			return int(player.stats.get("pets_bred", 0))
	return 0


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


# --- Persistence -------------------------------------------------------------

func to_save() -> Dictionary:
	return {"unlocked": unlocked.duplicate(), "jackpot_count": _jackpot_count}


func from_save(data: Dictionary) -> void:
	unlocked = data.get("unlocked", {}).duplicate()
	_jackpot_count = int(data.get("jackpot_count", 0))
