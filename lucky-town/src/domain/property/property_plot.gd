class_name PropertyPlot
extends RefCounted
## A buildable plot of land in the city grid.
##
## Plots are a finite resource — scarcity is what gives land its value. A plot
## tracks who owns it, what is built on it, and a `value` that the economy can
## push up or down. Buildings are referenced by a data-driven building id; the
## plot itself does not know what a building *does*, only that one stands here.

var id: String = ""
var grid_x: int = 0
var grid_y: int = 0

var owner_id: String = ""          # "" == unowned / for sale from the city
var building_id: String = ""        # "" == empty lot
var building_level: int = 1

var base_value: int = 1000
var value: int = 1000               # current market value (mutated by economy)
var for_sale: bool = false
var list_price: int = 0


static func make(id: String, x: int, y: int, base_value: int) -> PropertyPlot:
	var plot := PropertyPlot.new()
	plot.id = id
	plot.grid_x = x
	plot.grid_y = y
	plot.base_value = base_value
	plot.value = base_value
	plot.for_sale = true
	plot.list_price = base_value
	return plot


func is_owned() -> bool:
	return owner_id != ""


func is_empty() -> bool:
	return building_id == ""


## Total worth = land value plus a premium for whatever is built on it.
func appraised_value() -> int:
	var building_premium := 0
	if not is_empty():
		var def := DataRegistry.get_def("buildings", building_id)
		var build_cost := int(def.get("build_cost", 0))
		building_premium = int(round(float(build_cost) * (0.6 + 0.2 * float(building_level))))
	return value + building_premium


## Maximum level the current building can reach (1 if empty).
func max_level() -> int:
	if is_empty():
		return 1
	return int(DataRegistry.get_def("buildings", building_id).get("max_level", 5))


func can_upgrade() -> bool:
	return not is_empty() and building_level < max_level()


## Cost to upgrade to the next level, scaling with the current level.
func upgrade_cost() -> int:
	if not can_upgrade():
		return 0
	var def := DataRegistry.get_def("buildings", building_id)
	var base := int(def.get("build_cost", 0))
	return int(round(float(base) * 0.6 * float(building_level)))


## Passive income per day from the building on this plot (0 if empty).
func daily_income() -> int:
	if is_empty():
		return 0
	var def := DataRegistry.get_def("buildings", building_id)
	var base_income := int(def.get("daily_income", 0))
	return base_income * building_level


func to_dict() -> Dictionary:
	return {
		"id": id,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"owner_id": owner_id,
		"building_id": building_id,
		"building_level": building_level,
		"base_value": base_value,
		"value": value,
		"for_sale": for_sale,
		"list_price": list_price,
	}


static func from_dict(data: Dictionary) -> PropertyPlot:
	var plot := PropertyPlot.new()
	plot.id = data.get("id", "")
	plot.grid_x = int(data.get("grid_x", 0))
	plot.grid_y = int(data.get("grid_y", 0))
	plot.owner_id = data.get("owner_id", "")
	plot.building_id = data.get("building_id", "")
	plot.building_level = int(data.get("building_level", 1))
	plot.base_value = int(data.get("base_value", 1000))
	plot.value = int(data.get("value", plot.base_value))
	plot.for_sale = bool(data.get("for_sale", false))
	plot.list_price = int(data.get("list_price", 0))
	return plot
