extends Node
## Lightweight, level-based logger used across the whole game.
##
## Centralising logging here means we can later route messages to a file,
## an in-game console, or a telemetry sink (when networking is added) without
## touching call sites. Autoloaded as `Log`.

enum Level { DEBUG, INFO, WARN, ERROR }

## Minimum level that will be printed. Lower this to Level.DEBUG while developing.
@export var min_level: Level = Level.DEBUG

## When true, every record is also appended to `user://lucky_town.log`.
@export var file_logging: bool = false

const _LOG_PATH := "user://lucky_town.log"
const _LABELS := {
	Level.DEBUG: "DEBUG",
	Level.INFO: "INFO",
	Level.WARN: "WARN",
	Level.ERROR: "ERROR",
}


func debug(tag: String, message: String) -> void:
	_write(Level.DEBUG, tag, message)


func info(tag: String, message: String) -> void:
	_write(Level.INFO, tag, message)


func warn(tag: String, message: String) -> void:
	_write(Level.WARN, tag, message)


func error(tag: String, message: String) -> void:
	_write(Level.ERROR, tag, message)


func _write(level: Level, tag: String, message: String) -> void:
	if level < min_level:
		return
	var line := "[%s][%s] %s" % [_LABELS[level], tag, message]
	if level >= Level.WARN:
		push_warning(line) if level == Level.WARN else push_error(line)
	print(line)
	if file_logging:
		_append_to_file(line)


func _append_to_file(line: String) -> void:
	var file := FileAccess.open(_LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(_LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("%s %s" % [Time.get_datetime_string_from_system(), line])
	file.close()
