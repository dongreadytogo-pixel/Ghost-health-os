extends Node
## Tracks the player's quests and turns gameplay into progress.
##
## The system subscribes to the `EventBus`, translates the player's actions into
## quest *metrics*, advances matching quests, and pays rewards on claim. It also
## issues fresh daily missions each morning and — most importantly — guarantees
## a **recovery mission** whenever the player goes broke, so there is always a
## way back through play (a hard requirement from the design brief).
##
## Only the player's quests are tracked here; AI citizens pursue goals implicitly
## through their personalities, so this stays focused and cheap.

## Below this balance (and with no active recovery quest) a recovery mission is
## offered automatically.
const RECOVERY_THRESHOLD := 50

var active: Array = []        # Array[Quest]
var _claimed_ids: Dictionary = {}  # id -> true (avoid re-issuing one-shots)


func _ready() -> void:
	EventBus.day_started.connect(_on_day_started)
	EventBus.transaction_recorded.connect(_on_transaction)
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.slot_spun.connect(_on_slot_spun)
	EventBus.pet_acquired.connect(_on_pet_acquired)
	EventBus.property_purchased.connect(_on_property_purchased)
	EventBus.building_constructed.connect(_on_building_constructed)
	EventBus.citizen_action_finished.connect(_on_action_finished)


# --- Public API --------------------------------------------------------------

func active_quests() -> Array:
	return active


func completed_unclaimed() -> Array:
	return active.filter(func(q): return q.state == Quest.State.COMPLETED)


## Claim a completed quest's reward. Returns the coins granted (0 if not ready).
func claim(quest_id: String) -> int:
	for q in active:
		if q.id == quest_id and q.state == Quest.State.COMPLETED:
			q.state = Quest.State.CLAIMED
			Economy.credit(GameState.player_id, q.reward_coins, "quest:%s" % q.id)
			_claimed_ids[q.id] = true
			EventBus.quest_claimed.emit(q.id, q.reward_coins)
			EventBus.notification_posted.emit("Quest reward: +%d" % q.reward_coins, 2)
			active.erase(q)
			return q.reward_coins
	return 0


## Seed the first batch of quests for a brand-new game.
func bootstrap() -> void:
	active.clear()
	_claimed_ids.clear()
	_issue_story()
	_issue_dailies(GameClock.day)
	_check_recovery()


# --- Metric advancement ------------------------------------------------------

func _advance(metric: String, amount: int = 1) -> void:
	for q in active:
		if q.advance(metric, amount):
			EventBus.quest_completed.emit(q.id)
			EventBus.notification_posted.emit("Quest complete: %s" % q.title, 2)
		elif q.metric == metric and q.state == Quest.State.ACTIVE:
			EventBus.quest_progressed.emit(q.id, q.progress, q.target)


# --- Event translation (player only) -----------------------------------------

func _on_transaction(record: Dictionary) -> void:
	if record.get("owner") != GameState.player_id:
		return
	var delta := int(record.get("delta", 0))
	if delta > 0 and not String(record.get("reason", "")).begins_with("quest:"):
		_advance("coins_earned", delta)


func _on_money_changed(owner_id: String, _balance: int, _delta: int) -> void:
	if owner_id == GameState.player_id:
		_check_recovery()


func _on_slot_spun(_machine: String, player_id: String, result: Dictionary) -> void:
	if player_id != GameState.player_id:
		return
	_advance("spin_slot", 1)
	if int(result.get("total_payout", 0)) + int(result.get("jackpot_amount", 0)) > 0:
		_advance("win_slot", 1)


func _on_pet_acquired(owner_id: String, _pet_id: String) -> void:
	if owner_id == GameState.player_id:
		_advance("buy_pet", 1)


func _on_property_purchased(_plot_id: String, owner_id: String, _price: int) -> void:
	if owner_id == GameState.player_id:
		_advance("buy_land", 1)


func _on_building_constructed(plot_id: String, _building_id: String) -> void:
	var plot := GameState.get_plot(plot_id)
	if plot and plot.owner_id == GameState.player_id:
		_advance("build", 1)


func _on_action_finished(citizen_id: String, action: String) -> void:
	if citizen_id == GameState.player_id and action == "work":
		_advance("work", 1)


# --- Daily issue & recovery --------------------------------------------------

func _on_day_started(day: int) -> void:
	_expire(day)
	_issue_dailies(day)
	_check_recovery()


func _expire(day: int) -> void:
	active = active.filter(func(q): return not q.is_expired(day))


func _issue_dailies(day: int) -> void:
	# Avoid stacking dailies if some are still active for the day.
	for q in active:
		if q.kind == Quest.Kind.DAILY and q.issued_day == day:
			return
	var pool := _daily_pool()
	if pool.is_empty():
		return
	var rng := RngService.stream("quests")
	for q in QuestGenerator.roll_dailies(pool, rng, day):
		_add(q)


func _check_recovery() -> void:
	if not GameState.initialised:
		return
	if Economy.balance(GameState.player_id) > RECOVERY_THRESHOLD:
		return
	for q in active:
		if q.kind == Quest.Kind.RECOVERY:
			return  # one safety net at a time
	_add(QuestGenerator.make_recovery(GameClock.day))


func _add(q: Quest) -> void:
	active.append(q)
	EventBus.quest_issued.emit(q.to_dict())


## Issue the one-time main-story chain (kind STORY). Called only at new-game
## bootstrap; on load these come back via `from_save`.
func _issue_story() -> void:
	for def in _pool_of_kind(Quest.Kind.STORY):
		_add(Quest.from_def(def, GameClock.day))


func _daily_pool() -> Array:
	return _pool_of_kind(Quest.Kind.DAILY)


## All quest defs of a given kind (the `quests` data folder mixes daily, weekly
## and story templates; callers select by kind).
func _pool_of_kind(kind: int) -> Array:
	var pool: Array = []
	for id in DataRegistry.ids("quests"):
		var def := DataRegistry.get_def("quests", id)
		if int(def.get("kind", Quest.Kind.DAILY)) == kind:
			pool.append(def)
	return pool


# --- Persistence -------------------------------------------------------------

func to_save() -> Dictionary:
	var quest_dicts: Array = []
	for q in active:
		quest_dicts.append(q.to_dict())
	return {"active": quest_dicts, "claimed_ids": _claimed_ids.duplicate()}


func from_save(data: Dictionary) -> void:
	active.clear()
	for d in data.get("active", []):
		active.append(Quest.from_dict(d))
	_claimed_ids = data.get("claimed_ids", {}).duplicate()
