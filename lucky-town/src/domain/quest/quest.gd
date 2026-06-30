class_name Quest
extends RefCounted
## A single objective the player is working toward.
##
## Quests are data: a quest tracks one measurable goal (a "metric" and a target
## count), a coin reward, and its lifecycle state. The brief requires several
## flavours — main story, daily/weekly missions, achievements and, crucially,
## *recovery missions* so a bankrupt player can always earn their way back
## through play rather than waiting or paying. All of those are the same shape;
## only the data differs, so one class covers them.

enum State { ACTIVE, COMPLETED, CLAIMED }
enum Kind { STORY, DAILY, WEEKLY, ACHIEVEMENT, RECOVERY }

var id: String = ""
var title: String = ""
var description: String = ""
var kind: int = Kind.DAILY

## What to count and how much is needed. `metric` matches the keys advanced by
## `QuestSystem` (e.g. "spin_slot", "coins_earned", "buy_land", "work").
var metric: String = ""
var target: int = 1
var progress: int = 0

var reward_coins: int = 0
var state: int = State.ACTIVE

## Day the quest was issued / expires (0 = never expires). Dailies expire next day.
var issued_day: int = 0
var expires_day: int = 0


static func from_def(def: Dictionary, day: int = 0) -> Quest:
	var q := Quest.new()
	q.id = def.get("id", "")
	q.title = def.get("title", "")
	q.description = def.get("description", "")
	q.kind = int(def.get("kind", Kind.DAILY))
	q.metric = def.get("metric", "")
	q.target = int(def.get("target", 1))
	q.reward_coins = int(def.get("reward_coins", 0))
	q.issued_day = day
	q.expires_day = int(def.get("expires_day", 0))
	return q


## Advance by `amount` if this quest tracks `metric`. Returns true when the
## quest tips from ACTIVE into COMPLETED on this call (so the caller can notify).
func advance(metric_name: String, amount: int) -> bool:
	if state != State.ACTIVE or metric_name != metric:
		return false
	progress = mini(progress + amount, target)
	if progress >= target:
		state = State.COMPLETED
		return true
	return false


func is_complete() -> bool:
	return state == State.COMPLETED or state == State.CLAIMED


func is_expired(day: int) -> bool:
	return expires_day > 0 and day >= expires_day and state == State.ACTIVE


func ratio() -> float:
	return clampf(float(progress) / float(maxi(1, target)), 0.0, 1.0)


func to_dict() -> Dictionary:
	return {
		"id": id, "title": title, "description": description, "kind": kind,
		"metric": metric, "target": target, "progress": progress,
		"reward_coins": reward_coins, "state": state,
		"issued_day": issued_day, "expires_day": expires_day,
	}


static func from_dict(data: Dictionary) -> Quest:
	var q := Quest.new()
	q.id = data.get("id", "")
	q.title = data.get("title", "")
	q.description = data.get("description", "")
	q.kind = int(data.get("kind", Kind.DAILY))
	q.metric = data.get("metric", "")
	q.target = int(data.get("target", 1))
	q.progress = int(data.get("progress", 0))
	q.reward_coins = int(data.get("reward_coins", 0))
	q.state = int(data.get("state", State.ACTIVE))
	q.issued_day = int(data.get("issued_day", 0))
	q.expires_day = int(data.get("expires_day", 0))
	return q
