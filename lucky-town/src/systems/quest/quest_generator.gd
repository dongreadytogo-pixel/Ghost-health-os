class_name QuestGenerator
extends RefCounted
## Pure quest selection / construction.
##
## Kept free of autoloads so the rules (how many dailies, what a recovery
## mission looks like) can be unit-tested. `QuestSystem` supplies the data pool
## and RNG; this class just decides which templates become today's quests.

const DEFAULT_DAILY_COUNT := 3


## Pick `count` distinct daily templates from `pool` (array of def dicts) and
## instantiate them as Quests issued on `day`, expiring the next day.
static func roll_dailies(pool: Array, rng: RandomNumberGenerator, day: int, count: int = DEFAULT_DAILY_COUNT) -> Array:
	var candidates := pool.duplicate()
	_shuffle(candidates, rng)
	var out: Array = []
	for i in mini(count, candidates.size()):
		var q := Quest.from_def(candidates[i], day)
		q.kind = Quest.Kind.DAILY
		q.expires_day = day + 1
		out.append(q)
	return out


## Build the anti-bankruptcy recovery mission. Completing it (by doing odd jobs)
## earns the player back enough to re-enter the economy — recovery through play,
## never through waiting or paying.
static func make_recovery(day: int) -> Quest:
	var q := Quest.new()
	q.id = "recovery_%d" % day
	q.title = "Back on Your Feet"
	q.description = "Times are tight. Do 3 odd jobs at the Town Hall to earn a fresh start."
	q.kind = Quest.Kind.RECOVERY
	q.metric = "work"
	q.target = 3
	q.reward_coins = 250
	q.issued_day = day
	q.expires_day = 0  # never expires; the safety net is always available
	return q


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
