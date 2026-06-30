class_name PlayerActions
extends RefCounted
## The player's verbs: the same economic actions the AI performs, exposed for
## UI buttons.
##
## Routing player actions through one service (rather than scattering money
## logic across screens) guarantees the player and AI obey identical rules and
## emit identical `EventBus` events — which is what lets the quest system, stats
## and a future network layer treat player and AI uniformly. Every method
## returns a `{ ok, message }` result the UI can show directly.

static func _result(ok: bool, message: String) -> Dictionary:
	return {"ok": ok, "message": message}


## An "odd job" — the always-available way to earn, and the backbone of the
## recovery mission. Pays a modest wage and emits a `work` action.
static func work() -> Dictionary:
	var wage := RngService.range_i("player_work", 40, 90)
	Economy.credit(GameState.player_id, wage, "wages")
	var player := GameState.player()
	if player:
		player.stats["total_earned"] += wage
		player.energy = clampf(player.energy - 0.1, 0.0, 1.0)
	EventBus.citizen_action_finished.emit(GameState.player_id, "work")
	return _result(true, "You earned %d coins from an odd job." % wage)


static func buy_land(plot_id: String) -> Dictionary:
	var plot := GameState.get_plot(plot_id)
	if plot == null or not plot.for_sale or plot.is_owned():
		return _result(false, "That plot isn't for sale.")
	if not Economy.debit(GameState.player_id, plot.list_price, "buy_land:%s" % plot_id):
		return _result(false, "Not enough coins (need %d)." % plot.list_price)
	plot.owner_id = GameState.player_id
	plot.for_sale = false
	var player := GameState.player()
	if player:
		player.plot_ids.append(plot_id)
		player.stats["total_spent"] += plot.list_price
	EventBus.property_purchased.emit(plot_id, GameState.player_id, plot.list_price)
	return _result(true, "Bought %s for %d coins." % [plot_id, plot.list_price])


static func build(plot_id: String, building_id: String) -> Dictionary:
	var plot := GameState.get_plot(plot_id)
	if plot == null or plot.owner_id != GameState.player_id:
		return _result(false, "You don't own that plot.")
	if not plot.is_empty():
		return _result(false, "That plot already has a building.")
	var def := DataRegistry.get_def("buildings", building_id)
	if def.is_empty():
		return _result(false, "Unknown building.")
	var cost := int(def.get("build_cost", 0))
	if not Economy.debit(GameState.player_id, cost, "build:%s" % building_id):
		return _result(false, "Not enough coins (need %d)." % cost)
	plot.building_id = building_id
	plot.building_level = 1
	var player := GameState.player()
	if player:
		player.stats["buildings_built"] += 1
		player.stats["total_spent"] += cost
	EventBus.building_constructed.emit(plot_id, building_id)
	return _result(true, "Built a %s." % def.get("display_name", building_id))


static func buy_pet(species_id: String) -> Dictionary:
	var def := DataRegistry.get_def("pet_species", species_id)
	if def.is_empty():
		return _result(false, "Unknown species.")
	var price := int(def.get("base_value", 100))
	if not Economy.debit(GameState.player_id, price, "buy_pet:%s" % species_id):
		return _result(false, "Not enough coins (need %d)." % price)
	var pet := Pet.spawn(species_id, RngService.stream("pet_genes"), GameState.player_id, GameClock.day)
	GameState.add_pet(pet)
	var player := GameState.player()
	if player:
		player.stats["total_spent"] += price
	EventBus.pet_acquired.emit(GameState.player_id, pet.id)
	return _result(true, "Adopted a %s (quality %d%%)." % [def.get("display_name", species_id), int(pet.quality() * 100.0)])


static func sell_pet(pet_id: String) -> Dictionary:
	var pet := GameState.get_pet(pet_id)
	if pet == null or pet.owner_id != GameState.player_id:
		return _result(false, "You don't own that pet.")
	var price := pet.market_value()
	Economy.credit(GameState.player_id, price, "sell_pet")
	GameState.remove_pet(pet_id)
	EventBus.pet_sold.emit(GameState.player_id, pet_id, price)
	return _result(true, "Sold %s for %d coins." % [pet.nickname, price])


static func breed(parent_a_id: String, parent_b_id: String) -> Dictionary:
	var a := GameState.get_pet(parent_a_id)
	var b := GameState.get_pet(parent_b_id)
	if a == null or b == null:
		return _result(false, "Select two pets to breed.")
	if a.species_id != b.species_id:
		return _result(false, "Pets must be the same species.")
	var child := PetBreeder.breed(a, b, RngService.stream("pet_breed"), GameState.player_id, GameClock.day)
	if child == null:
		return _result(false, "Breeding failed.")
	GameState.add_pet(child)
	var player := GameState.player()
	if player:
		player.stats["pets_bred"] += 1
	EventBus.pet_bred.emit(a.id, b.id, child.id)
	return _result(true, "A new %s was born (quality %d%%)!" % [child.nickname, int(child.quality() * 100.0)])
