class_name Pet
extends RefCounted
## A single owned creature.
##
## Pets are one of the largest systems in the game (dogs, cats, foxes, dragons,
## ghost pets, legendary creatures…). A pet is pure data so it can live in the
## market, be auctioned, bred, and serialised without dragging a scene around.
## Species-level facts (base stats, allowed traits, art) come from the
## data-driven `pet_species` registry; per-individual facts (level, genes,
## mutations) live on the instance.

## Genes are heritable numeric alleles in [0,1] that bias derived stats. Two
## parents blend their genes with mutation, enabling the breeding meta-game.
var id: String = ""
var species_id: String = ""
var nickname: String = ""

var level: int = 1
var experience: int = 0

## gene name -> float allele in [0,1].
var genes: Dictionary = {}
## Named discrete traits unlocked by genes/mutations (e.g. "glowing", "twin_tail").
var traits: Array = []
## Rare, value-boosting deviations rolled at birth.
var mutations: Array = []

var happiness: float = 0.8
var birth_day: int = 1
var owner_id: String = ""


static func new_id() -> String:
	return "pet_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]


## Create a fresh pet of a species with randomised genes from a named RNG
## stream (so breeding/spawning is reproducible).
static func spawn(species_id: String, rng: RandomNumberGenerator, owner_id: String = "", day: int = 1) -> Pet:
	var pet := Pet.new()
	pet.id = new_id()
	pet.species_id = species_id
	pet.owner_id = owner_id
	pet.birth_day = day
	var def := DataRegistry.get_def("pet_species", species_id)
	pet.nickname = def.get("display_name", species_id)
	for gene_name in def.get("genes", []):
		pet.genes[gene_name] = rng.randf()
	pet._roll_traits(def, rng)
	return pet


func _roll_traits(def: Dictionary, rng: RandomNumberGenerator) -> void:
	for trait_def in def.get("traits", []):
		var gene_name: String = trait_def.get("gene", "")
		var threshold: float = float(trait_def.get("threshold", 0.9))
		if genes.get(gene_name, 0.0) >= threshold:
			traits.append(trait_def.get("name", gene_name))
	var mutation_chance: float = float(def.get("mutation_chance", 0.02))
	if rng.randf() < mutation_chance:
		var pool: Array = def.get("mutation_pool", [])
		if not pool.is_empty():
			mutations.append(pool[rng.randi_range(0, pool.size() - 1)])


## Quality score in [0,1] aggregating genes; drives market value and prestige.
func quality() -> float:
	if genes.is_empty():
		return 0.5
	var sum := 0.0
	for v in genes.values():
		sum += float(v)
	var base := sum / float(genes.size())
	var bonus := 0.05 * float(traits.size()) + 0.15 * float(mutations.size())
	return clampf(base + bonus, 0.0, 1.0)


## Estimated market value in coins, combining species base, level and quality.
func market_value() -> int:
	var def := DataRegistry.get_def("pet_species", species_id)
	var base := int(def.get("base_value", 100))
	var level_factor := 1.0 + 0.1 * float(level - 1)
	var quality_factor := 0.5 + 1.5 * quality()
	return int(round(float(base) * level_factor * quality_factor))


func add_experience(amount: int) -> void:
	experience += amount
	while experience >= _xp_for_next_level():
		experience -= _xp_for_next_level()
		level += 1


func _xp_for_next_level() -> int:
	return 100 + (level - 1) * 50


func to_dict() -> Dictionary:
	return {
		"id": id,
		"species_id": species_id,
		"nickname": nickname,
		"level": level,
		"experience": experience,
		"genes": genes.duplicate(),
		"traits": traits.duplicate(),
		"mutations": mutations.duplicate(),
		"happiness": happiness,
		"birth_day": birth_day,
		"owner_id": owner_id,
	}


static func from_dict(data: Dictionary) -> Pet:
	var pet := Pet.new()
	pet.id = data.get("id", new_id())
	pet.species_id = data.get("species_id", "")
	pet.nickname = data.get("nickname", "")
	pet.level = int(data.get("level", 1))
	pet.experience = int(data.get("experience", 0))
	pet.genes = data.get("genes", {}).duplicate()
	pet.traits = data.get("traits", []).duplicate()
	pet.mutations = data.get("mutations", []).duplicate()
	pet.happiness = float(data.get("happiness", 0.8))
	pet.birth_day = int(data.get("birth_day", 1))
	pet.owner_id = data.get("owner_id", "")
	return pet
