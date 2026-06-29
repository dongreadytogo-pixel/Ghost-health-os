extends Node
## Deterministic, named random-number streams.
##
## Every gameplay system pulls randomness from a *named stream* here rather than
## from the global `randi()`. Each stream is seeded from a single master seed,
## so a saved game can be reproduced exactly and tests can assert on outcomes.
## This is essential for fair, auditable slot mechanics and for debugging AI.
##
## Streams are lazily created. A stream's seed is derived from
## `hash(master_seed, stream_name)` so adding a new stream never disturbs the
## sequence of existing ones.

var _master_seed: int = 0
var _streams: Dictionary = {}  # String -> RandomNumberGenerator


func _ready() -> void:
	randomize_master()


## Re-seed everything from the OS entropy source (new game / "I feel lucky").
func randomize_master() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	set_master_seed(rng.seed)


## Seed everything deterministically (loading a save, or a test).
func set_master_seed(seed_value: int) -> void:
	_master_seed = seed_value
	_streams.clear()
	Log.info("RNG", "Master seed set to %d" % _master_seed)


func get_master_seed() -> int:
	return _master_seed


## Fetch (or lazily create) a named stream.
func stream(name: String) -> RandomNumberGenerator:
	if not _streams.has(name):
		var rng := RandomNumberGenerator.new()
		rng.seed = _derive_seed(name)
		_streams[name] = rng
	return _streams[name]


## Integer in [from, to] inclusive, from the named stream.
func range_i(name: String, from: int, to: int) -> int:
	return stream(name).randi_range(from, to)


## Float in [from, to), from the named stream.
func range_f(name: String, from: float, to: float) -> float:
	return stream(name).randf_range(from, to)


## Returns true with probability `p` (0..1).
func chance(name: String, p: float) -> bool:
	return stream(name).randf() < p


## Weighted pick. `weights` maps any key -> non-negative weight.
## Returns the chosen key, or `null` if the table is empty / all-zero.
func weighted_pick(name: String, weights: Dictionary) -> Variant:
	var total := 0.0
	for w in weights.values():
		total += float(w)
	if total <= 0.0:
		return null
	var roll := stream(name).randf() * total
	for key in weights:
		roll -= float(weights[key])
		if roll <= 0.0:
			return key
	return weights.keys().back()


func _derive_seed(name: String) -> int:
	# Combine master seed and stream name into a stable 64-bit seed.
	return hash(str(_master_seed) + "::" + name)


## Snapshot for the save system. Stream cursors are intentionally *not*
## persisted (slot fairness does not depend on resuming mid-sequence); only the
## master seed is, which keeps saves small and forward-compatible.
func to_save() -> Dictionary:
	return {"master_seed": _master_seed}


func from_save(data: Dictionary) -> void:
	set_master_seed(int(data.get("master_seed", 0)))
