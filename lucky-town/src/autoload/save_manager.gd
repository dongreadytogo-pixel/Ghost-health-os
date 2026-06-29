extends Node
## Orchestrates saving and loading the entire game.
##
## A save is a single snapshot dictionary assembled from every stateful autoload
## (their `to_save()` / `from_save()` contracts). The manager owns slot policy —
## multiple manual slots, a dedicated auto-save slot, and an embedded schema
## `version` so old saves can be migrated forward. Storage is delegated to a
## `SaveBackend`, so swapping JSON for SQLite later is a one-line change here.

const SCHEMA_VERSION := 1
const AUTOSAVE_SLOT := 0
const MAX_MANUAL_SLOTS := 8
## Auto-save every N in-game hours.
const AUTOSAVE_INTERVAL_HOURS := 6

var _backend: SaveBackend
var _hours_since_autosave := 0


func _ready() -> void:
	_backend = JsonSaveBackend.new()
	EventBus.hour_ticked.connect(_on_hour_ticked)


func set_backend(backend: SaveBackend) -> void:
	_backend = backend


# --- Save --------------------------------------------------------------------

func save_to_slot(slot: int) -> bool:
	var snapshot := _collect_snapshot()
	var err := _backend.write_slot(slot, snapshot)
	if err != OK:
		Log.error("Save", "Failed to write slot %d (err %d)" % [slot, err])
		return false
	Log.info("Save", "Saved to slot %d" % slot)
	EventBus.game_saved.emit(slot)
	return true


func autosave() -> void:
	if not GameState.initialised:
		return
	if save_to_slot(AUTOSAVE_SLOT):
		EventBus.notification_posted.emit("Game auto-saved", 0)


# --- Load --------------------------------------------------------------------

func has_slot(slot: int) -> bool:
	return _backend.has_slot(slot)


func list_slots() -> Dictionary:
	return _backend.list_slots()


func load_from_slot(slot: int) -> bool:
	var snapshot := _backend.read_slot(slot)
	if snapshot.is_empty():
		Log.warn("Save", "Slot %d is empty" % slot)
		return false
	snapshot = _migrate(snapshot)
	_apply_snapshot(snapshot)
	Log.info("Save", "Loaded slot %d" % slot)
	EventBus.game_loaded.emit(slot)
	return true


func delete_slot(slot: int) -> void:
	_backend.delete_slot(slot)


# --- Snapshot assembly -------------------------------------------------------

func _collect_snapshot() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"meta": _build_meta(),
		"rng": RngService.to_save(),
		"clock": GameClock.to_save(),
		"economy": Economy.to_save(),
		"world": GameState.to_save(),
	}


func _apply_snapshot(snapshot: Dictionary) -> void:
	RngService.from_save(snapshot.get("rng", {}))
	GameClock.from_save(snapshot.get("clock", {}))
	Economy.from_save(snapshot.get("economy", {}))
	GameState.from_save(snapshot.get("world", {}))


## Headline info for the load-game menu — kept tiny and cheap to read.
func _build_meta() -> Dictionary:
	var player := GameState.player()
	return {
		"version": SCHEMA_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"day": GameClock.day,
		"player_name": player.citizen_name if player else "Unknown",
		"net_worth": _player_net_worth(),
		"citizen_count": GameState.citizens.size(),
	}


func _player_net_worth() -> int:
	var worth := Economy.balance(GameState.player_id)
	var player := GameState.player()
	if player == null:
		return worth
	for plot_id in player.plot_ids:
		var plot := GameState.get_plot(plot_id)
		if plot:
			worth += plot.appraised_value()
	for pet_id in player.pet_ids:
		var pet := GameState.get_pet(pet_id)
		if pet:
			worth += pet.market_value()
	return worth


# --- Migration ---------------------------------------------------------------

## Upgrade an older snapshot to the current schema. Each version bump appends a
## step here; today there is only version 1, so this is a pass-through.
func _migrate(snapshot: Dictionary) -> Dictionary:
	var version := int(snapshot.get("version", 1))
	while version < SCHEMA_VERSION:
		match version:
			# Example for the future:
			# 1: snapshot = _migrate_v1_to_v2(snapshot)
			_:
				break
		version += 1
	snapshot["version"] = SCHEMA_VERSION
	return snapshot


func _on_hour_ticked(_day: int, _hour: int) -> void:
	_hours_since_autosave += 1
	if _hours_since_autosave >= AUTOSAVE_INTERVAL_HOURS:
		_hours_since_autosave = 0
		autosave()
