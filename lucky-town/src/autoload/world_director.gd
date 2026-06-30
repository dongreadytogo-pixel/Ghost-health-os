extends Node
## The world manager that makes the city feel alive.
##
## It hangs off the `GameClock` signals and, each hour, advances every AI
## citizen: needs decay, the `AiBrain` chooses an action, the `AiActuator`
## performs it. Each day it pays out passive income from buildings, ages the
## population's statistics, and rolls for world events (festivals, market
## shocks, rare-pet appearances). It also computes the city rankings ("richest
## citizen", etc.). This is the single component responsible for global pacing,
## so designers tune the world's rhythm in one place.

## How many AI citizens get a fresh decision per hour tick. Spreading decisions
## across ticks keeps the simulation cheap even with a large population.
@export var decisions_per_hour: int = 6

## Daily probability of each kind of world event.
@export var festival_chance: float = 0.12
@export var market_shock_chance: float = 0.10
@export var rare_pet_chance: float = 0.08

enum Weather { CLEAR, CLOUDY, RAIN, FOG }

var _decision_cursor := 0
var _active_events: Dictionary = {}   # event_id -> remaining days
var current_weather: int = Weather.CLEAR


func _ready() -> void:
	EventBus.hour_ticked.connect(_on_hour)
	EventBus.day_started.connect(_on_day)


# --- Hourly simulation -------------------------------------------------------

func _on_hour(_day: int, _hour: int) -> void:
	if not GameState.initialised:
		return
	var ai := GameState.ai_citizens()
	if ai.is_empty():
		return
	# Decay everyone a little each hour (cheap), but only a slice makes a
	# decision this tick (round-robin) to bound per-frame cost.
	for c in ai:
		c.decay_needs(1.0)
	for _i in mini(decisions_per_hour, ai.size()):
		_decision_cursor = (_decision_cursor + 1) % ai.size()
		_tick_citizen(ai[_decision_cursor])


func _tick_citizen(c: Citizen) -> void:
	var personality := Personality.from_def(DataRegistry.get_def("personalities", c.personality_id))
	var world := _world_context(c)
	var decision := AiBrain.decide(c, personality, world, RngService.stream("ai:%s" % c.id))
	AiActuator.execute(c, decision)


func _world_context(c: Citizen) -> Dictionary:
	return {
		"balance": Economy.balance(c.id),
		"hour": GameClock.hour,
		"slot_machine_ids": DataRegistry.ids("slot_machines"),
		"pet_market_ids": DataRegistry.ids("pet_species"),
		"land_for_sale": GameState.plots_for_sale(),
		"ownable_buildings": DataRegistry.ids("buildings"),
	}


# --- Daily routines ----------------------------------------------------------

func _on_day(day: int) -> void:
	if not GameState.initialised:
		return
	_roll_weather()
	_pay_passive_income()
	_pet_farm_production()
	_seed_auctions()
	_age_population()
	_expire_events()
	_roll_world_events(day)


## Buildings generate passive income for their owners overnight.
func _pay_passive_income() -> void:
	for plot in GameState.plots.values():
		if not plot.is_owned():
			continue
		var income := plot.daily_income()
		if income > 0:
			Economy.credit(plot.owner_id, income, "rent:%s" % plot.id)
			var owner := GameState.get_citizen(plot.owner_id)
			if owner:
				owner.stats["total_earned"] += income


func _age_population() -> void:
	for c in GameState.citizens.values():
		c.stats["days_lived"] += 1


## Pet farms work passively: an owner of a farm/pet-shop with two same-species
## pets has a daily chance to breed an offspring automatically — idle production
## that rewards building the right infrastructure.
func _pet_farm_production() -> void:
	var rng := RngService.stream("pet_farm")
	for plot in GameState.plots.values():
		if plot.building_id != "farm" and plot.building_id != "pet_shop":
			continue
		var owner := GameState.get_citizen(plot.owner_id)
		if owner == null or owner.pet_ids.size() < 2:
			continue
		# Yield improves with building level.
		if rng.randf() >= 0.25 + 0.1 * float(plot.building_level):
			continue
		_auto_breed_for(owner, rng)


func _auto_breed_for(owner: Citizen, rng: RandomNumberGenerator) -> void:
	# Find a species the owner has at least two of.
	var by_species: Dictionary = {}
	for pet_id in owner.pet_ids:
		var pet := GameState.get_pet(pet_id)
		if pet == null:
			continue
		if not by_species.has(pet.species_id):
			by_species[pet.species_id] = []
		by_species[pet.species_id].append(pet)
	for species_id in by_species:
		var group: Array = by_species[species_id]
		if group.size() >= 2:
			var child := PetBreeder.breed(group[0], group[1], rng, owner.id, GameClock.day)
			if child:
				GameState.add_pet(child)
				owner.stats["pets_bred"] += 1
				EventBus.pet_bred.emit(group[0].id, group[1].id, child.id)
			return


## Keep the auction house stocked: each day a few well-stocked AI citizens list
## their best spare pet, giving the player something to compete for.
func _seed_auctions() -> void:
	if AuctionHouse.open_lots().size() >= 6:
		return
	var rng := RngService.stream("auction_seed")
	var sellers := GameState.ai_citizens()
	for c in sellers:
		if c.pet_ids.size() < 3:
			continue
		if rng.randf() >= 0.15:
			continue
		var best := _best_pet_of(c)
		if best:
			AuctionHouse.list_pet(c.id, best.id)
		if AuctionHouse.open_lots().size() >= 6:
			return


func _best_pet_of(c: Citizen) -> Pet:
	var best: Pet = null
	for pet_id in c.pet_ids:
		var pet := GameState.get_pet(pet_id)
		if pet and (best == null or pet.market_value() > best.market_value()):
			best = pet
	return best


# --- World events ------------------------------------------------------------

func _roll_world_events(day: int) -> void:
	var rng := RngService.stream("world_events")
	if rng.randf() < festival_chance:
		_start_event("festival", 2, {"name": "City Festival", "happiness_boost": 0.2})
		for c in GameState.citizens.values():
			c.satisfy("happiness", 0.2)
	if rng.randf() < market_shock_chance:
		_market_shock(rng)
	if rng.randf() < rare_pet_chance:
		var species := DataRegistry.ids("pet_species")
		if not species.is_empty():
			var pick: String = species[rng.randi_range(0, species.size() - 1)]
			_start_event("rare_pet", 1, {"species_id": pick})


func _market_shock(rng: RandomNumberGenerator) -> void:
	var items := DataRegistry.ids("market_items")
	if items.is_empty():
		return
	var item: String = items[rng.randi_range(0, items.size() - 1)]
	# A sudden surge or collapse in demand for one good.
	if rng.randf() < 0.5:
		Economy.register_purchase(item, 80)
	else:
		Economy.register_sale(item, 80)
	_start_event("market_shock", 1, {"item_id": item})


func _start_event(id: String, days: int, payload: Dictionary) -> void:
	_active_events[id] = days
	EventBus.world_event_started.emit(id, payload)
	EventBus.notification_posted.emit("Event: %s" % id.capitalize(), 1)


func _expire_events() -> void:
	for id in _active_events.keys():
		_active_events[id] -= 1
		if _active_events[id] <= 0:
			_active_events.erase(id)
			EventBus.world_event_ended.emit(id)


func active_events() -> Array:
	return _active_events.keys()


# --- Weather -----------------------------------------------------------------

## Pick the day's weather, biased by the current season (summers are clearer,
## winters foggier). Weather is cosmetic-plus: the `WorldAtmosphere` node reacts
## visually and a light economic nudge is applied (rainy days dampen shopping).
func _roll_weather() -> void:
	var weights := _season_weather_weights(GameClock.season)
	var picked = RngService.weighted_pick("weather", weights)
	var new_weather: int = picked if picked != null else Weather.CLEAR
	if new_weather != current_weather:
		current_weather = new_weather
		EventBus.weather_changed.emit(current_weather)
		EventBus.notification_posted.emit("Weather: %s" % weather_name(), 0)
	if current_weather == Weather.RAIN:
		# A rainy day softens demand for non-essentials across the market.
		for item_id in DataRegistry.ids("market_items"):
			Economy.register_sale(item_id, 5)


func _season_weather_weights(season: int) -> Dictionary:
	match season:
		GameClock.Season.SUMMER:
			return {Weather.CLEAR: 6.0, Weather.CLOUDY: 2.0, Weather.RAIN: 1.0, Weather.FOG: 0.3}
		GameClock.Season.WINTER:
			return {Weather.CLEAR: 2.0, Weather.CLOUDY: 3.0, Weather.RAIN: 1.5, Weather.FOG: 3.0}
		GameClock.Season.AUTUMN:
			return {Weather.CLEAR: 3.0, Weather.CLOUDY: 3.0, Weather.RAIN: 2.5, Weather.FOG: 1.5}
		_:  # spring
			return {Weather.CLEAR: 4.0, Weather.CLOUDY: 3.0, Weather.RAIN: 2.0, Weather.FOG: 1.0}


func weather_name() -> String:
	return ["Clear", "Cloudy", "Rain", "Fog"][current_weather]


# --- Rankings ----------------------------------------------------------------

## Returns an array of {id, name, value} sorted descending by net worth.
func ranking_richest() -> Array:
	var rows: Array = []
	for c in GameState.citizens.values():
		rows.append({"id": c.id, "name": c.citizen_name, "value": _net_worth(c)})
	rows.sort_custom(func(a, b): return a["value"] > b["value"])
	return rows


func ranking_landowners() -> Array:
	var rows: Array = []
	for c in GameState.citizens.values():
		rows.append({"id": c.id, "name": c.citizen_name, "value": c.plot_ids.size()})
	rows.sort_custom(func(a, b): return a["value"] > b["value"])
	return rows


func ranking_most_pets() -> Array:
	var rows: Array = []
	for c in GameState.citizens.values():
		rows.append({"id": c.id, "name": c.citizen_name, "value": c.pet_ids.size()})
	rows.sort_custom(func(a, b): return a["value"] > b["value"])
	return rows


## "Luckiest" = best net gambling result to date.
func ranking_luckiest() -> Array:
	var rows: Array = []
	for c in GameState.citizens.values():
		rows.append({"id": c.id, "name": c.citizen_name, "value": int(c.memory.get("net_gambling", 0))})
	rows.sort_custom(func(a, b): return a["value"] > b["value"])
	return rows


func _net_worth(c: Citizen) -> int:
	var worth := Economy.balance(c.id)
	for plot_id in c.plot_ids:
		var plot := GameState.get_plot(plot_id)
		if plot:
			worth += plot.appraised_value()
	for pet_id in c.pet_ids:
		var pet := GameState.get_pet(pet_id)
		if pet:
			worth += pet.market_value()
	return worth
