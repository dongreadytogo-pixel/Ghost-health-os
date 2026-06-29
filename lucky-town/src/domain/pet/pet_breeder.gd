class_name PetBreeder
extends RefCounted
## Pure genetics: combine two parents into an offspring.
##
## Kept separate from `Pet` so the breeding rules can be unit-tested and tuned
## in isolation. Offspring genes are a noisy average of the parents' alleles
## (classic blending inheritance with mutation), which lets dedicated breeders
## push a line toward higher quality over generations — the heart of the pet
## meta-game.

const _MUTATION_SIGMA := 0.08


## Breed `a` and `b` (must share a species). Returns the child, or null if the
## species are incompatible.
static func breed(a: Pet, b: Pet, rng: RandomNumberGenerator, owner_id: String, day: int) -> Pet:
	if a.species_id != b.species_id:
		return null
	var child := Pet.new()
	child.id = Pet.new_id()
	child.species_id = a.species_id
	child.owner_id = owner_id
	child.birth_day = day
	var def := DataRegistry.get_def("pet_species", a.species_id)
	child.nickname = def.get("display_name", a.species_id)

	for gene_name in def.get("genes", []):
		var pa: float = float(a.genes.get(gene_name, rng.randf()))
		var pb: float = float(b.genes.get(gene_name, rng.randf()))
		var blended := (pa + pb) * 0.5
		var mutated := blended + rng.randfn(0.0, _MUTATION_SIGMA)
		child.genes[gene_name] = clampf(mutated, 0.0, 1.0)

	child._roll_traits(def, rng)
	# Inheriting a parent's mutation is possible but rare.
	for parent in [a, b]:
		for m in parent.mutations:
			if rng.randf() < 0.25 and not child.mutations.has(m):
				child.mutations.append(m)
	return child
