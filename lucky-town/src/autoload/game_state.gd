extends Node
## The authoritative in-memory model of the world: every citizen, pet and plot.
##
## Autoloads like `Economy` own *financial* state; `GameState` owns *entity*
## state and the registry that ties ids together. Scene nodes (avatars,
## buildings) are thin views that look up their model here by id and render it.
## Because the whole world is plain data hanging off one node, saving is just
## "serialise GameState + the other autoloads", and a future server could hold
## the very same structures authoritatively.

const STARTING_CASH := 500
const CITY_GRID := Vector2i(8, 8)

var player_id: String = Economy.PLAYER_ID

var citizens: Dictionary = {}   # id -> Citizen
var pets: Dictionary = {}        # id -> Pet
var plots: Dictionary = {}       # id -> PropertyPlot

var initialised := false


func _ready() -> void:
	# A fresh game is created on demand by the boot flow / "New Game".
	pass


# --- New game ----------------------------------------------------------------

## Build a brand-new city: the player, their starter plot+house, a grid of land
## for sale, and a population of AI citizens with assigned personalities.
func new_game(citizen_count: int = 12) -> void:
	citizens.clear()
	pets.clear()
	plots.clear()
	RngService.randomize_master()

	_generate_city_grid()
	_create_player()
	_populate_citizens(citizen_count)
	_seed_jackpots()

	initialised = true
	QuestSystem.bootstrap()
	Log.info("GameState", "New game: %d citizens, %d plots" % [citizens.size(), plots.size()])
	EventBus.notification_posted.emit("Welcome to Lucky Town!", 0)


func _generate_city_grid() -> void:
	for y in CITY_GRID.y:
		for x in CITY_GRID.x:
			var id := "plot_%d_%d" % [x, y]
			# Land near the centre is pricier (scarcity + desirability).
			var dist := Vector2(x, y).distance_to(Vector2(CITY_GRID) * 0.5)
			var base := int(800 + 400.0 * maxf(0.0, 4.0 - dist))
			plots[id] = PropertyPlot.make(id, x, y, base)


func _create_player() -> void:
	var player := Citizen.new()
	player.id = player_id
	player.citizen_name = "You"
	player.is_player = true
	player.control_mode = Citizen.ControlMode.LOCAL
	player.personality_id = "casual"
	citizens[player_id] = player
	Economy.open_account(player_id, STARTING_CASH)

	# Grant the starter plot with a small house, free of charge.
	var start_plot: PropertyPlot = plots["plot_0_0"]
	start_plot.owner_id = player_id
	start_plot.for_sale = false
	start_plot.building_id = "house"
	start_plot.building_level = 1
	player.plot_ids.append(start_plot.id)
	player.home_plot_id = start_plot.id


func _populate_citizens(count: int) -> void:
	var personality_ids := DataRegistry.ids("personalities")
	if personality_ids.is_empty():
		personality_ids = ["casual"]
	var names := _name_pool()
	for i in count:
		var c := Citizen.new()
		c.id = Citizen.new_id()
		c.citizen_name = names[i % names.size()]
		c.age = RngService.range_i("citizen_gen", 18, 70)
		c.personality_id = personality_ids[i % personality_ids.size()]
		citizens[c.id] = c
		Economy.open_account(c.id, RngService.range_i("citizen_gen", 200, 2000))
	Log.info("GameState", "Spawned %d AI citizens" % count)


func _seed_jackpots() -> void:
	for machine_id in DataRegistry.ids("slot_machines"):
		Economy.seed_jackpot(machine_id, 5000)


# --- Lookups -----------------------------------------------------------------

func player() -> Citizen:
	return citizens.get(player_id)


func get_citizen(id: String) -> Citizen:
	return citizens.get(id)


func get_pet(id: String) -> Pet:
	return pets.get(id)


func get_plot(id: String) -> PropertyPlot:
	return plots.get(id)


func ai_citizens() -> Array:
	var out: Array = []
	for c in citizens.values():
		if not c.is_player:
			out.append(c)
	return out


func plots_for_sale() -> Array:
	var out: Array = []
	for plot in plots.values():
		if plot.for_sale and not plot.is_owned():
			out.append(plot)
	return out


# --- Mutations ---------------------------------------------------------------

func add_pet(pet: Pet) -> void:
	pets[pet.id] = pet
	var owner := get_citizen(pet.owner_id)
	if owner and not owner.pet_ids.has(pet.id):
		owner.pet_ids.append(pet.id)


func remove_pet(pet_id: String) -> void:
	var pet := get_pet(pet_id)
	if pet == null:
		return
	var owner := get_citizen(pet.owner_id)
	if owner:
		owner.pet_ids.erase(pet_id)
	pets.erase(pet_id)


# --- Persistence -------------------------------------------------------------

func to_save() -> Dictionary:
	var citizen_dicts: Array = []
	for c in citizens.values():
		citizen_dicts.append(c.to_dict())
	var pet_dicts: Array = []
	for p in pets.values():
		pet_dicts.append(p.to_dict())
	var plot_dicts: Array = []
	for plot in plots.values():
		plot_dicts.append(plot.to_dict())
	return {
		"player_id": player_id,
		"citizens": citizen_dicts,
		"pets": pet_dicts,
		"plots": plot_dicts,
	}


func from_save(data: Dictionary) -> void:
	citizens.clear()
	pets.clear()
	plots.clear()
	player_id = data.get("player_id", Economy.PLAYER_ID)
	for d in data.get("citizens", []):
		var c := Citizen.from_dict(d)
		citizens[c.id] = c
	for d in data.get("pets", []):
		var p := Pet.from_dict(d)
		pets[p.id] = p
	for d in data.get("plots", []):
		var plot := PropertyPlot.from_dict(d)
		plots[plot.id] = plot
	initialised = true


func _name_pool() -> Array:
	return [
		"Aria", "Bram", "Cleo", "Dahlia", "Enzo", "Fern", "Goro", "Hana",
		"Iris", "Juno", "Kira", "Lio", "Mika", "Nico", "Opal", "Pax",
		"Quinn", "Remy", "Sora", "Taro", "Uma", "Vera", "Wren", "Yuki",
	]
