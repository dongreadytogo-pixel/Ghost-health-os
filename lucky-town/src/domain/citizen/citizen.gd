class_name Citizen
extends RefCounted
## The data model for one inhabitant of the city.
##
## Every citizen is AI today and a potential online player tomorrow. The model
## holds only *state* — needs, memory, relationships, possessions — never any
## scene or rendering concern. Behaviour (deciding what to do next) lives in
## `AiBrain`, and the visible avatar lives in a `CitizenAgent` node. This split
## is exactly what lets a networked player later "inhabit" a citizen: swap the
## brain for remote input and nothing else changes.

## Who drives this citizen's decisions. The entire point of the model/view split
## is that this can change at runtime: an AI citizen can be handed to a remote
## player (REMOTE) with no other code change — the actuator, economy, save and
## rendering are identical regardless of the source of decisions.
enum ControlMode { AI, LOCAL, REMOTE }

# --- Identity ----------------------------------------------------------------
var id: String = ""
var citizen_name: String = ""
var age: int = 25
var personality_id: String = ""
var is_player: bool = false
var control_mode: int = ControlMode.AI

# --- Needs (0..1, 1 == fully satisfied) --------------------------------------
var hunger: float = 1.0
var energy: float = 1.0
var happiness: float = 0.7
var social: float = 0.7

# --- Possessions (money lives in the Economy ledger, keyed by id) ------------
var pet_ids: Array = []
var plot_ids: Array = []
var inventory: Dictionary = {}     # item_id -> qty
var job_id: String = ""
var home_plot_id: String = ""

# --- Memory: experiences that bias future decisions --------------------------
## Free-form counters and tallies, e.g. wins, losses, favourite_slot.
var memory: Dictionary = {
	"slot_wins": 0,
	"slot_losses": 0,
	"net_gambling": 0,
	"favourite_slot": "",
	"favourite_shop": "",
}
## other_citizen_id -> relationship score in [-1, 1].
var relationships: Dictionary = {}

# --- Lifetime statistics -----------------------------------------------------
var stats: Dictionary = {
	"days_lived": 0,
	"total_earned": 0,
	"total_spent": 0,
	"pets_bred": 0,
	"buildings_built": 0,
}


static func new_id() -> String:
	return "cit_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]


# --- Needs decay & satisfaction ---------------------------------------------

## Decay needs over `hours` of in-game time. Called from the simulation tick.
func decay_needs(hours: float) -> void:
	hunger = clampf(hunger - 0.05 * hours, 0.0, 1.0)
	energy = clampf(energy - 0.04 * hours, 0.0, 1.0)
	social = clampf(social - 0.03 * hours, 0.0, 1.0)
	# Happiness drifts toward the average of the other needs.
	var target := (hunger + energy + social) / 3.0
	happiness = clampf(lerpf(happiness, target, 0.1 * hours), 0.0, 1.0)


func satisfy(need: String, amount: float) -> void:
	match need:
		"hunger": hunger = clampf(hunger + amount, 0.0, 1.0)
		"energy": energy = clampf(energy + amount, 0.0, 1.0)
		"social": social = clampf(social + amount, 0.0, 1.0)
		"happiness": happiness = clampf(happiness + amount, 0.0, 1.0)


# --- Memory & relationships --------------------------------------------------

func record_slot_result(net: int, machine_id: String) -> void:
	if net >= 0:
		memory["slot_wins"] += 1
		memory["favourite_slot"] = machine_id
	else:
		memory["slot_losses"] += 1
	memory["net_gambling"] += net


func adjust_relationship(other_id: String, delta: float) -> void:
	var current := float(relationships.get(other_id, 0.0))
	relationships[other_id] = clampf(current + delta, -1.0, 1.0)


func relationship_with(other_id: String) -> float:
	return float(relationships.get(other_id, 0.0))


# --- Serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"id": id,
		"citizen_name": citizen_name,
		"age": age,
		"personality_id": personality_id,
		"is_player": is_player,
		"control_mode": control_mode,
		"hunger": hunger,
		"energy": energy,
		"happiness": happiness,
		"social": social,
		"pet_ids": pet_ids.duplicate(),
		"plot_ids": plot_ids.duplicate(),
		"inventory": inventory.duplicate(),
		"job_id": job_id,
		"home_plot_id": home_plot_id,
		"memory": memory.duplicate(true),
		"relationships": relationships.duplicate(),
		"stats": stats.duplicate(true),
	}


static func from_dict(data: Dictionary) -> Citizen:
	var c := Citizen.new()
	c.id = data.get("id", new_id())
	c.citizen_name = data.get("citizen_name", "Citizen")
	c.age = int(data.get("age", 25))
	c.personality_id = data.get("personality_id", "")
	c.is_player = bool(data.get("is_player", false))
	c.control_mode = int(data.get("control_mode", ControlMode.AI))
	c.hunger = float(data.get("hunger", 1.0))
	c.energy = float(data.get("energy", 1.0))
	c.happiness = float(data.get("happiness", 0.7))
	c.social = float(data.get("social", 0.7))
	c.pet_ids = data.get("pet_ids", []).duplicate()
	c.plot_ids = data.get("plot_ids", []).duplicate()
	c.inventory = data.get("inventory", {}).duplicate()
	c.job_id = data.get("job_id", "")
	c.home_plot_id = data.get("home_plot_id", "")
	c.memory = data.get("memory", {}).duplicate(true)
	c.relationships = data.get("relationships", {}).duplicate()
	c.stats = data.get("stats", {}).duplicate(true)
	return c
