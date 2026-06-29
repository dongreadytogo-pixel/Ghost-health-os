class_name AiBrain
extends RefCounted
## Utility-based decision making for AI citizens.
##
## On each decision tick the brain scores every candidate action with a utility
## function that blends four forces:
##   1. need pressure   — a starving citizen *must* eat, overriding preference;
##   2. personality      — a Gambler weights "gamble" high, a Farmer weights it low;
##   3. economic context — can they afford it? is there opportunity?
##   4. memory            — past wins/losses nudge gambling appetite up or down.
## The highest-scoring affordable action wins (with a little softmax noise so
## crowds don't move in lockstep). Because everything is data and arithmetic,
## behaviour is fully testable and deterministic under a fixed RNG — and a
## remote player can later replace the brain without touching anything else.
##
## The brain is *pure*: it reads a read-only snapshot of the world and returns a
## decision. Executing the decision (moving the avatar, spending money) is the
## job of `CitizenAgent`, keeping policy and effect cleanly separated.

const CANDIDATES := [
	"eat", "sleep", "socialise", "work",
	"gamble", "shop", "invest",
	"buy_pet", "sell_pet", "breed_pet",
	"buy_land", "build", "decorate",
]

## Reserve cash a citizen tries to keep, scaled by frugality.
const _BASE_RESERVE := 200


## Decide the next action for `citizen`. `world` is a read-only context with:
##   balance: int, hour: int,
##   slot_machine_ids: Array, pet_market_ids: Array, land_for_sale: Array,
##   ownable_buildings: Array.
static func decide(citizen: Citizen, personality: Personality, world: Dictionary, rng: RandomNumberGenerator) -> AiDecision:
	var scores: Dictionary = {}
	var params: Dictionary = {}
	for action in CANDIDATES:
		var result := _score(action, citizen, personality, world)
		if float(result["score"]) > 0.0:
			scores[action] = result["score"]
			params[action] = result["params"]

	if scores.is_empty():
		return AiDecision.new("idle")

	var chosen := _softmax_pick(scores, rng)
	return AiDecision.new(chosen, params[chosen], scores[chosen])


# --- Per-action utility ------------------------------------------------------

static func _score(action: String, c: Citizen, p: Personality, world: Dictionary) -> Dictionary:
	var balance: int = world.get("balance", 0)
	var pref := p.weight_for(action)
	var score := 0.0
	var params := {}

	match action:
		"eat":
			# Need pressure dominates; rises sharply as hunger empties.
			score = _need_pressure(c.hunger) * 2.0 + pref * 0.2
			params = {"cost": 30}
			if balance < 30:
				score *= 0.3  # can still scavenge cheap food, but reluctantly
		"sleep":
			var hour: int = world.get("hour", 12)
			var night_bonus := 1.0 if (hour >= 22 or hour < 6) else 0.0
			score = _need_pressure(c.energy) * 1.8 + night_bonus + pref * 0.2
		"socialise":
			score = _need_pressure(c.social) * 1.2 * (0.5 + p.sociability) + pref * 0.3
		"work":
			# Working is attractive when cash is low and energy remains.
			var poverty := clampf(1.0 - float(balance) / 500.0, 0.0, 1.0)
			score = (0.6 * poverty + 0.4 * pref) * c.energy
			params = {"job_id": c.job_id}
		"gamble":
			score = _gamble_utility(c, p, balance)
			params = {"machine_ids": world.get("slot_machine_ids", [])}
		"shop":
			score = pref * (1.0 - p.frugality) * _afford_gate(balance, 50)
		"invest":
			# Investors buy income-producing assets when flush with cash.
			var surplus := clampf(float(balance) / 2000.0, 0.0, 1.0)
			score = pref * surplus
		"buy_pet":
			score = pref * _afford_gate(balance, 150) * (0.5 + 0.5 * (1.0 - p.frugality))
			params = {"species_ids": world.get("pet_market_ids", [])}
		"sell_pet":
			score = pref * (1.0 if c.pet_ids.size() > 2 else 0.0)
		"breed_pet":
			score = pref * (1.0 if c.pet_ids.size() >= 2 else 0.0)
		"buy_land":
			var land: Array = world.get("land_for_sale", [])
			score = pref * _afford_gate(balance, 1000) * (1.0 if not land.is_empty() else 0.0)
			params = {"plots": land}
		"build":
			score = pref * _afford_gate(balance, 800) * (1.0 if c.plot_ids.size() > 0 else 0.0)
			params = {"buildings": world.get("ownable_buildings", [])}
		"decorate":
			score = pref * 0.5 * _afford_gate(balance, 100)

	# A tired/hungry citizen should not wander off to decorate; survival first.
	if action not in ["eat", "sleep"]:
		var distress := maxf(_need_pressure(c.hunger), _need_pressure(c.energy))
		score *= (1.0 - 0.7 * distress)

	return {"score": maxf(0.0, score), "params": params}


# --- Helpers -----------------------------------------------------------------

## Maps a need level (1 = full) to pressure (0 = none, ~1+ = urgent), rising
## steeply as the need empties.
static func _need_pressure(level: float) -> float:
	var deficit := clampf(1.0 - level, 0.0, 1.0)
	return deficit * deficit  # quadratic: low until it gets serious


static func _afford_gate(balance: int, cost: int) -> float:
	return 1.0 if balance >= cost else 0.0


static func _gamble_utility(c: Citizen, p: Personality, balance: int) -> float:
	if balance < 50:
		return 0.0
	var base := p.weight_for("gamble") * (0.4 + p.risk_tolerance)
	# Memory: a hot streak emboldens, heavy losses chasten (loss-chasing for
	# high risk_tolerance, caution for the risk-averse).
	var net: int = int(c.memory.get("net_gambling", 0))
	var memory_bias := 0.0
	if net > 0:
		memory_bias = 0.2
	elif net < -500:
		memory_bias = lerpf(-0.3, 0.2, p.risk_tolerance)  # risk lovers chase
	# Keeping a cash reserve (frugality) suppresses gambling.
	var reserve := _BASE_RESERVE * (1.0 + 2.0 * p.frugality)
	var cushion := clampf(float(balance) / reserve, 0.0, 1.0)
	return maxf(0.0, (base + memory_bias) * cushion)


## Pick an action by softmax over scores so behaviour is varied but still
## dominated by the best option. `temperature` controls randomness.
static func _softmax_pick(scores: Dictionary, rng: RandomNumberGenerator, temperature: float = 0.5) -> String:
	var weights: Dictionary = {}
	var max_score := -INF
	for s in scores.values():
		max_score = maxf(max_score, s)
	for action in scores:
		# Subtract max for numerical stability before exponentiating.
		weights[action] = exp((scores[action] - max_score) / maxf(0.01, temperature))
	return _weighted_choice(weights, rng)


static func _weighted_choice(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := rng.randf() * total
	for action in weights:
		roll -= weights[action]
		if roll <= 0.0:
			return action
	return weights.keys().back()
