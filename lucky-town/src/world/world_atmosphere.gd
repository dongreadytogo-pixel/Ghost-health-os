extends Node3D
## Turns simulation time and weather into visible sky, sun and fog.
##
## A pure *view* over `GameClock` and `WorldDirector`: it reads the time of day
## each frame and tilts/dims the sun accordingly, and reacts to `weather_changed`
## by adjusting ambient tint and fog. No gameplay lives here — the world would
## play identically with this node removed, it just wouldn't look alive.

## Set in the scene to the sibling DirectionalLight3D and WorldEnvironment.
@export var sun_path: NodePath
@export var environment_path: NodePath

@export var day_sun_energy: float = 1.2
@export var night_sun_energy: float = 0.05

var _sun: DirectionalLight3D
var _world_env: WorldEnvironment
var _env: Environment


func _ready() -> void:
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	_world_env = get_node_or_null(environment_path) as WorldEnvironment
	if _world_env:
		_env = _world_env.environment
	EventBus.weather_changed.connect(_on_weather_changed)
	_apply_weather(WorldDirector.current_weather)


func _process(_delta: float) -> void:
	if _sun == null:
		return
	# Elevation: +1 at noon, 0 at sunrise/sunset, -1 at midnight.
	var fraction := GameClock.day_fraction()
	var elevation := sin((fraction - 0.25) * TAU)
	# Tilt the sun: straight down at noon, along the horizon at dawn/dusk.
	_sun.rotation_degrees.x = -clampf(elevation, -1.0, 1.0) * 85.0
	var daylight := clampf(elevation, 0.0, 1.0)
	_sun.light_energy = lerpf(night_sun_energy, day_sun_energy, daylight)
	# Warm light near the horizon, neutral-cool at noon.
	_sun.light_color = Color(1.0, 0.6, 0.4).lerp(Color(1.0, 0.97, 0.9), daylight)
	if _env:
		_env.ambient_light_energy = lerpf(0.1, 0.6, daylight)


func _on_weather_changed(weather: int) -> void:
	_apply_weather(weather)


func _apply_weather(weather: int) -> void:
	if _env == null:
		return
	# Defaults (clear).
	_env.fog_enabled = false
	match weather:
		WorldDirector.Weather.FOG:
			_env.fog_enabled = true
			_env.fog_density = 0.04
			_env.fog_light_color = Color(0.75, 0.78, 0.82)
		WorldDirector.Weather.RAIN:
			_env.fog_enabled = true
			_env.fog_density = 0.015
			_env.fog_light_color = Color(0.5, 0.55, 0.6)
		WorldDirector.Weather.CLOUDY:
			_env.fog_enabled = true
			_env.fog_density = 0.006
			_env.fog_light_color = Color(0.7, 0.72, 0.75)
		_:
			_env.fog_enabled = false
