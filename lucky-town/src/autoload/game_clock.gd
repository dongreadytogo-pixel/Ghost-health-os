extends Node
## Simulation time: the heartbeat that drives the living city.
##
## Real seconds are scaled into in-game minutes. The clock emits `hour_ticked`
## and `day_started` on the `EventBus`; AI schedules, economy updates, world
## events and save/auto-save all hang off those signals rather than polling.
## Time can be paused (menus) and fast-forwarded (idle catch-up) without any
## subscriber needing to know.

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const MINUTES_PER_DAY := 24 * 60
const DAYS_PER_SEASON := 28

## How many in-game minutes pass per real second at 1x speed.
@export var minutes_per_real_second: float = 60.0

var _paused := false
var _speed := 1.0
var _accumulated_minutes := 0.0

var total_minutes: int = 8 * 60  # start at 08:00 on day 1
var day: int = 1
var hour: int = 8
var minute: int = 0
var season: int = Season.SPRING

var _last_emitted_hour := -1


func _process(delta: float) -> void:
	if _paused:
		return
	_accumulated_minutes += delta * minutes_per_real_second * _speed
	if _accumulated_minutes < 1.0:
		return
	var whole := int(_accumulated_minutes)
	_accumulated_minutes -= float(whole)
	_advance_minutes(whole)


func set_paused(value: bool) -> void:
	_paused = value


func is_paused() -> bool:
	return _paused


func set_speed(multiplier: float) -> void:
	_speed = maxf(0.0, multiplier)


func get_speed() -> float:
	return _speed


## Advance the world by `minutes`, emitting hour/day boundaries crossed. Used
## both by `_process` and by the idle/offline catch-up routine.
func _advance_minutes(minutes: int) -> void:
	for _i in minutes:
		total_minutes += 1
		_recompute()
		if hour != _last_emitted_hour:
			_last_emitted_hour = hour
			EventBus.hour_ticked.emit(day, hour)
			if hour == 0:
				EventBus.day_started.emit(day)
				_maybe_change_season()


func _recompute() -> void:
	var day_index := total_minutes / MINUTES_PER_DAY
	day = day_index + 1
	var minute_of_day := total_minutes % MINUTES_PER_DAY
	hour = minute_of_day / 60
	minute = minute_of_day % 60


func _maybe_change_season() -> void:
	var new_season := ((day - 1) / DAYS_PER_SEASON) % 4
	if new_season != season:
		season = new_season
		EventBus.season_changed.emit(season)


## Normalised time of day in [0,1), handy for sun/lighting interpolation.
## Total whole in-game hours elapsed since the start of time. Used as a stable
## monotonic stamp for scheduling (e.g. auction close times).
func total_hours() -> int:
	return total_minutes / 60


func day_fraction() -> float:
	return float(total_minutes % MINUTES_PER_DAY) / float(MINUTES_PER_DAY)


func is_daytime() -> bool:
	return hour >= 6 and hour < 20


func time_string() -> String:
	return "%02d:%02d" % [hour, minute]


func season_name() -> String:
	return ["Spring", "Summer", "Autumn", "Winter"][season]


func to_save() -> Dictionary:
	return {"total_minutes": total_minutes}


func from_save(data: Dictionary) -> void:
	total_minutes = int(data.get("total_minutes", 8 * 60))
	_recompute()
	_maybe_change_season()
	_last_emitted_hour = hour
