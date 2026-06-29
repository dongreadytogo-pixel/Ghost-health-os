class_name SaveBackend
extends RefCounted
## Abstract persistence backend.
##
## The design calls for "SQLite + JSON" saves. We hide the storage mechanism
## behind this tiny interface so the game logic only ever deals with a
## Dictionary snapshot. The shipping default is `JsonSaveBackend` (zero
## dependencies, human-readable, perfect for offline-first). A `SqliteSaveBackend`
## can be dropped in later for large cities / incremental writes without any
## change to `SaveManager` or gameplay — that is the whole point of the seam.

## Persist `data` for save slot `slot`. Returns OK or a Godot error code.
func write_slot(slot: int, data: Dictionary) -> Error:
	push_error("SaveBackend.write_slot not implemented")
	return ERR_UNAVAILABLE


## Load the snapshot for `slot`, or an empty dictionary if none exists.
func read_slot(slot: int) -> Dictionary:
	push_error("SaveBackend.read_slot not implemented")
	return {}


func has_slot(slot: int) -> bool:
	return false


func delete_slot(slot: int) -> Error:
	return ERR_UNAVAILABLE


## Lightweight metadata for every populated slot (for the load-game menu),
## without deserialising the whole save. Returns slot -> Dictionary.
func list_slots() -> Dictionary:
	return {}
