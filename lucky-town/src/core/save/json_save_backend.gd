class_name JsonSaveBackend
extends SaveBackend
## File-per-slot JSON persistence under `user://saves/`.
##
## Offline-first and dependency-free: each slot is a single pretty-printed JSON
## file, plus a tiny `.meta.json` sidecar holding just the headline stats the
## load menu needs (so it never has to parse a multi-megabyte city to draw a
## list). Writes go to a temp file and are then renamed over the real file, so a
## crash mid-write can never corrupt an existing save.

const SAVE_DIR := "user://saves"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func write_slot(slot: int, data: Dictionary) -> Error:
	var path := _slot_path(slot)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return err
	_write_meta(slot, data)
	return OK


func read_slot(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("Corrupt save in slot %d" % slot)
	return {}


func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func delete_slot(slot: int) -> Error:
	for path in [_slot_path(slot), _meta_path(slot)]:
		if FileAccess.file_exists(path):
			var err := DirAccess.remove_absolute(path)
			if err != OK:
				return err
	return OK


func list_slots() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".meta.json"):
			var slot := name.trim_suffix(".meta.json").trim_prefix("slot_").to_int()
			var text := FileAccess.get_file_as_string(SAVE_DIR.path_join(name))
			var meta = JSON.parse_string(text)
			if meta is Dictionary:
				out[slot] = meta
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _write_meta(slot: int, data: Dictionary) -> void:
	var meta: Dictionary = data.get("meta", {})
	var file := FileAccess.open(_meta_path(slot), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(meta, "\t"))
	file.close()


func _slot_path(slot: int) -> String:
	return SAVE_DIR.path_join("slot_%d.json" % slot)


func _meta_path(slot: int) -> String:
	return SAVE_DIR.path_join("slot_%d.meta.json" % slot)
