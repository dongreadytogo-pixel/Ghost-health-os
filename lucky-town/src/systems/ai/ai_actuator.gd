class_name AiActuator
extends RefCounted
## Executes an `AiDecision` against the world model and economy.
##
## The brain decides *what*; the actuator performs the *effect* — spending
## money, satisfying needs, buying pets/land, gambling on a real slot machine.
## Visible, nearby citizens animate these actions through their `CitizenAgent`;
## off-screen citizens are resolved here instantly so the whole city keeps
## living even where the camera isn't looking. Either way the economic result is
## identical, because it routes through the same `Economy` ledger.

const SlotEvaluatorRef := preload("res://src/domain/slot/slot_evaluator.gd")


## Apply `decision` for `citizen`. Emits the relevant EventBus signals so UI and
## statistics stay in sync regardless of whether the actor was on-screen.
static func execute(citizen: Citizen, decision: AiDecision) -> void:
	EventBus.citizen_action_started.emit(citizen.id, decision.action)
	match decision.action:
		"eat": _eat(citizen, decision)
		"sleep": _sleep(citizen)
		"socialise": _socialise(citizen)
		"work": _work(citizen)
		"gamble": _gamble(citizen, decision)
		"shop": _shop(citizen, decision)
		"invest": _invest(citizen)
		"buy_pet": _buy_pet(citizen, decision)
		"sell_pet": _sell_pet(citizen)
		"breed_pet": _breed_pet(citizen)
		"buy_land": _buy_land(citizen, decision)
		"build": _build(citizen, decision)
		"decorate": _decorate(citizen)
		_: pass
	EventBus.citizen_action_finished.emit(citizen.id, decision.action)


# --- Survival ----------------------------------------------------------------

static func _eat(c: Citizen, d: AiDecision) -> void:
	var cost: int = int(d.params.get("cost", 30))
	if Economy.debit(c.id, cost, "food"):
		c.stats["total_spent"] += cost
	c.satisfy("hunger", 0.6)
	c.satisfy("happiness", 0.05)


static func _sleep(c: Citizen) -> void:
	c.satisfy("energy", 0.8)


static func _socialise(c: Citizen) -> void:
	c.satisfy("social", 0.5)
	# Improve a relationship with a random other citizen.
	var others := GameState.ai_citizens()
	if others.size() > 1:
		var other: Citizen = others[RngService.range_i("social", 0, others.size() - 1)]
		if other.id != c.id:
			c.adjust_relationship(other.id, 0.05)
			other.adjust_relationship(c.id, 0.05)
			EventBus.citizen_relationship_changed.emit(c.id, other.id, 0.05)


static func _work(c: Citizen) -> void:
	# A simple wage; jobs become data-driven in Phase 2.
	var wage := RngService.range_i("work", 40, 120)
	Economy.credit(c.id, wage, "wages")
	c.stats["total_earned"] += wage
	c.energy = clampf(c.energy - 0.2, 0.0, 1.0)


# --- Gambling ----------------------------------------------------------------

static func _gamble(c: Citizen, d: AiDecision) -> void:
	var machine_ids: Array = d.params.get("machine_ids", [])
	if machine_ids.is_empty():
		return
	var machine_id: String = machine_ids[RngService.range_i("gamble_pick", 0, machine_ids.size() - 1)]
	var config := DataRegistry.slot_config(machine_id)
	if config == null:
		return
	var bet := _choose_bet(c, config)
	if not Economy.debit(c.id, bet, "slot_bet:%s" % machine_id):
		return
	Economy.contribute_jackpot(machine_id, int(round(float(bet) * config.jackpot_contribution)))
	var result := SlotEvaluatorRef.spin(config, RngService.stream("slot:%s" % machine_id), bet, Economy.jackpot(machine_id))
	if result.total_payout > 0:
		Economy.credit(c.id, result.total_payout, "slot_win:%s" % machine_id)
	if result.jackpot_won:
		Economy.claim_jackpot(machine_id, c.id)
	c.record_slot_result(result.net(), machine_id)
	c.satisfy("happiness", 0.1 if result.is_win() else -0.05)
	EventBus.slot_spun.emit(machine_id, c.id, result.to_dict())


static func _choose_bet(c: Citizen, config: SlotMachineConfig) -> int:
	var personality := _personality(c)
	var balance := Economy.balance(c.id)
	# Bet a fraction of cash scaled by risk appetite, clamped to machine limits.
	var fraction := lerpf(0.02, 0.15, personality.risk_tolerance)
	var desired := int(round(float(balance) * fraction))
	return config.clamp_bet(maxi(config.min_bet, desired))


# --- Commerce ----------------------------------------------------------------

static func _shop(c: Citizen, _d: AiDecision) -> void:
	var item_ids := DataRegistry.ids("market_items")
	if item_ids.is_empty():
		return
	var item_id: String = item_ids[RngService.range_i("shop", 0, item_ids.size() - 1)]
	var price := Economy.price(item_id)
	if price > 0 and Economy.debit(c.id, price, "buy:%s" % item_id):
		c.inventory[item_id] = int(c.inventory.get(item_id, 0)) + 1
		c.stats["total_spent"] += price
		Economy.register_purchase(item_id)
		c.satisfy("happiness", 0.08)


static func _invest(c: Citizen) -> void:
	# Treat investing as buying land if any is affordable; otherwise no-op.
	_buy_land(c, AiDecision.new("buy_land", {"plots": GameState.plots_for_sale()}))


static func _buy_pet(c: Citizen, d: AiDecision) -> void:
	var species_ids: Array = d.params.get("species_ids", DataRegistry.ids("pet_species"))
	if species_ids.is_empty():
		return
	var species_id: String = species_ids[RngService.range_i("pet_buy", 0, species_ids.size() - 1)]
	var def := DataRegistry.get_def("pet_species", species_id)
	var price := int(def.get("base_value", 100))
	if not Economy.debit(c.id, price, "buy_pet:%s" % species_id):
		return
	var pet := Pet.spawn(species_id, RngService.stream("pet_genes"), c.id, GameClock.day)
	GameState.add_pet(pet)
	EventBus.pet_acquired.emit(c.id, pet.id)


static func _sell_pet(c: Citizen) -> void:
	if c.pet_ids.is_empty():
		return
	# Sell the lowest-quality pet to keep the best of the litter.
	var worst_id := ""
	var worst_value := INF
	for pet_id in c.pet_ids:
		var pet := GameState.get_pet(pet_id)
		if pet and pet.market_value() < worst_value:
			worst_value = pet.market_value()
			worst_id = pet_id
	if worst_id == "":
		return
	var price := int(worst_value)
	Economy.credit(c.id, price, "sell_pet")
	GameState.remove_pet(worst_id)
	EventBus.pet_sold.emit(c.id, worst_id, price)


static func _breed_pet(c: Citizen) -> void:
	if c.pet_ids.size() < 2:
		return
	var a := GameState.get_pet(c.pet_ids[0])
	var b := GameState.get_pet(c.pet_ids[1])
	if a == null or b == null:
		return
	var child := PetBreeder.breed(a, b, RngService.stream("pet_breed"), c.id, GameClock.day)
	if child:
		GameState.add_pet(child)
		c.stats["pets_bred"] += 1
		EventBus.pet_bred.emit(a.id, b.id, child.id)


# --- Property ----------------------------------------------------------------

static func _buy_land(c: Citizen, d: AiDecision) -> void:
	var plots: Array = d.params.get("plots", GameState.plots_for_sale())
	if plots.is_empty():
		return
	# Buy the cheapest affordable plot.
	plots.sort_custom(func(x, y): return x.list_price < y.list_price)
	for plot in plots:
		if Economy.debit(c.id, plot.list_price, "buy_land:%s" % plot.id):
			plot.owner_id = c.id
			plot.for_sale = false
			c.plot_ids.append(plot.id)
			EventBus.property_purchased.emit(plot.id, c.id, plot.list_price)
			return


static func _build(c: Citizen, d: AiDecision) -> void:
	var empty_plot: PropertyPlot = null
	for plot_id in c.plot_ids:
		var plot := GameState.get_plot(plot_id)
		if plot and plot.is_empty():
			empty_plot = plot
			break
	if empty_plot == null:
		return
	var buildings: Array = d.params.get("buildings", DataRegistry.ids("buildings"))
	if buildings.is_empty():
		return
	var building_id: String = buildings[RngService.range_i("build", 0, buildings.size() - 1)]
	var def := DataRegistry.get_def("buildings", building_id)
	var cost := int(def.get("build_cost", 800))
	if Economy.debit(c.id, cost, "build:%s" % building_id):
		empty_plot.building_id = building_id
		empty_plot.building_level = 1
		c.stats["buildings_built"] += 1
		EventBus.building_constructed.emit(empty_plot.id, building_id)


static func _decorate(c: Citizen) -> void:
	c.satisfy("happiness", 0.05)


# --- Helpers -----------------------------------------------------------------

static func _personality(c: Citizen) -> Personality:
	return Personality.from_def(DataRegistry.get_def("personalities", c.personality_id))
