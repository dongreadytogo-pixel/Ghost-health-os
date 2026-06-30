extends Node
## Central registry for all data-driven game content.
##
## The game is "data driven": slot themes, pet species, building types,
## personalities and market items are authored as JSON under `res://data/` and
## loaded here at boot. Gameplay code asks the registry for definitions by id;
## it never hard-codes content. Adding a new pet or slot theme is therefore a
## matter of dropping a JSON file in — no code change, no recompile.
##
## Each category is a folder of `*.json` files. A file may contain a single
## object (with an "id") or an array of objects.

signal data_loaded()

const _CATEGORIES := {
	"slot_machines": "res://data/slot_machines",
	"pet_species": "res://data/pet_species",
	"personalities": "res://data/personalities",
	"buildings": "res://data/buildings",
	"market_items": "res://data/market_items",
	"quests": "res://data/quests",
	"achievements": "res://data/achievements",
}

var _data: Dictionary = {}  # category -> { id -> Dictionary }
var _loaded := false


func _ready() -> void:
	load_all()


func load_all() -> void:
	_data.clear()
	for category in _CATEGORIES:
		_data[category] = _load_category(_CATEGORIES[category])
	_loaded = true
	Log.info("Data", "Loaded categories: %s" % str(_summary()))
	data_loaded.emit()


func is_loaded() -> bool:
	return _loaded


## All definitions in a category as `id -> Dictionary`.
func all(category: String) -> Dictionary:
	return _data.get(category, {})


## A single definition, or an empty dictionary if absent.
func get_def(category: String, id: String) -> Dictionary:
	return _data.get(category, {}).get(id, {})


func ids(category: String) -> Array:
	return _data.get(category, {}).keys()


func has(category: String, id: String) -> bool:
	return _data.get(category, {}).has(id)


## Convenience: build a typed SlotMachineConfig for a given machine id.
func slot_config(id: String) -> SlotMachineConfig:
	var def := get_def("slot_machines", id)
	if def.is_empty():
		Log.warn("Data", "Unknown slot machine '%s'" % id)
		return null
	return SlotMachineConfig.from_dict(def)


func _load_category(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		Log.warn("Data", "Missing data dir: %s" % dir_path)
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_ingest_file(dir_path.path_join(file_name), out)
		file_name = dir.get_next()
	dir.list_dir_end()
	return out


func _ingest_file(path: String, out: Dictionary) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		Log.warn("Data", "Empty or unreadable file: %s" % path)
		return
	var parsed = JSON.parse_string(text)
	if parsed == null:
		Log.error("Data", "Invalid JSON in %s" % path)
		return
	if parsed is Array:
		for entry in parsed:
			_register(entry, out, path)
	elif parsed is Dictionary:
		_register(parsed, out, path)


func _register(entry: Variant, out: Dictionary, path: String) -> void:
	if typeof(entry) != TYPE_DICTIONARY or not entry.has("id"):
		Log.warn("Data", "Skipping id-less entry in %s" % path)
		return
	var id := String(entry["id"])
	if out.has(id):
		Log.warn("Data", "Duplicate id '%s' (in %s) overwrites earlier definition" % [id, path])
	out[id] = entry


func _summary() -> Dictionary:
	var s := {}
	for category in _data:
		s[category] = _data[category].size()
	return s
