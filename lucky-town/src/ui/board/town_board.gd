extends CanvasLayer
## The player's management hub: quests, city rankings, odd jobs and shopping.
##
## Phase 1 made buildings "management screens"; this is the first of them. It is
## a pure view over the model + services: it never mutates state directly, only
## calls `PlayerActions` / `QuestSystem` and rebuilds itself from the resulting
## events. Toggle with the `toggle_board` action (B). Opening pauses the clock so
## the player can plan without the city moving underneath them.

@onready var _root: Control = $Root
@onready var _money_label: Label = $Root/Panel/Margin/VBox/MoneyLabel
@onready var _quest_list: VBoxContainer = $Root/Panel/Margin/VBox/Columns/Left/QuestScroll/QuestList
@onready var _ranking_list: VBoxContainer = $Root/Panel/Margin/VBox/Columns/Right/RankingList
@onready var _pet_list: VBoxContainer = $Root/Panel/Margin/VBox/Columns/Right/PetList
@onready var _log_label: Label = $Root/Panel/Margin/VBox/LogLabel
@onready var _work_button: Button = $Root/Panel/Margin/VBox/Columns/Left/WorkButton
@onready var _land_button: Button = $Root/Panel/Margin/VBox/Columns/Left/LandButton
@onready var _build_button: Button = $Root/Panel/Margin/VBox/Columns/Left/BuildButton
@onready var _upgrade_button: Button = $Root/Panel/Margin/VBox/Columns/Left/UpgradeButton

func _ready() -> void:
	_root.hide()
	_work_button.pressed.connect(_on_work)
	_land_button.pressed.connect(_on_buy_land)
	_build_button.pressed.connect(_on_build)
	_upgrade_button.pressed.connect(_on_upgrade)
	$Root/Panel/Margin/VBox/CloseButton.pressed.connect(_close)
	# Refresh whenever the world changes, but only while we're on screen. Each
	# signal is forwarded through a matching-arity stub (GDScript lambdas don't
	# support default-valued params, so we can't use one generic handler).
	EventBus.quest_issued.connect(_refresh1)
	EventBus.quest_completed.connect(_refresh1)
	EventBus.quest_claimed.connect(_refresh2)
	EventBus.quest_progressed.connect(_refresh3)
	EventBus.pet_acquired.connect(_refresh2)
	EventBus.property_purchased.connect(_refresh3)
	EventBus.building_constructed.connect(_refresh2)
	EventBus.money_changed.connect(_refresh3)


func _refresh1(_a) -> void:
	_refresh_if_visible()


func _refresh2(_a, _b) -> void:
	_refresh_if_visible()


func _refresh3(_a, _b, _c) -> void:
	_refresh_if_visible()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_board"):
		toggle()


func toggle() -> void:
	if _root.visible:
		_close()
	else:
		_open()


func _open() -> void:
	_root.show()
	GameClock.set_paused(true)
	EventBus.ui_modal_changed.emit(true)
	_refresh()


func _close() -> void:
	_root.hide()
	GameClock.set_paused(false)
	EventBus.ui_modal_changed.emit(false)


func _refresh_if_visible() -> void:
	if _root.visible:
		_refresh()


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	_money_label.text = "Net worth: $%s    Cash: $%s" % [
		Money.of(_player_net_worth()).format_full(),
		Money.of(Economy.balance(GameState.player_id)).format_full(),
	]
	_render_quests()
	_render_rankings()
	_render_pet_shop()
	_update_land_buttons()


func _render_quests() -> void:
	_clear(_quest_list)
	var quests: Array = QuestSystem.active_quests()
	if quests.is_empty():
		_quest_list.add_child(_label("No active quests."))
		return
	for q in quests:
		var row := HBoxContainer.new()
		var text := "%s  (%d/%d)  +%d" % [q.title, q.progress, q.target, q.reward_coins]
		var lbl := _label(text)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		if q.state == Quest.State.COMPLETED:
			var claim := Button.new()
			claim.text = "Claim"
			var qid: String = q.id
			claim.pressed.connect(func(): _on_claim(qid))
			row.add_child(claim)
		_quest_list.add_child(row)


func _render_rankings() -> void:
	_clear(_ranking_list)
	_render_ranking_block("Richest", WorldDirector.ranking_richest(), true, 3)
	_render_ranking_block("Most Land", WorldDirector.ranking_landowners(), false, 3)
	_render_ranking_block("Most Pets", WorldDirector.ranking_most_pets(), false, 3)
	_render_ranking_block("Luckiest", WorldDirector.ranking_luckiest(), true, 3)


func _render_ranking_block(title: String, rows: Array, money: bool, count: int) -> void:
	_ranking_list.add_child(_heading(title))
	for i in mini(count, rows.size()):
		var r: Dictionary = rows[i]
		var marker := "  (you)" if r["id"] == GameState.player_id else ""
		var value_text := "$%s" % Money.of(int(r["value"])).format_short() if money else str(int(r["value"]))
		_ranking_list.add_child(_label("%d. %s — %s%s" % [i + 1, r["name"], value_text, marker]))


func _render_pet_shop() -> void:
	_clear(_pet_list)
	_pet_list.add_child(_heading("Pet Shop"))
	for species_id in DataRegistry.ids("pet_species"):
		var def := DataRegistry.get_def("pet_species", species_id)
		var price := int(def.get("base_value", 100))
		var row := HBoxContainer.new()
		var lbl := _label("%s — $%d" % [def.get("display_name", species_id), price])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var buy := Button.new()
		buy.text = "Adopt"
		buy.disabled = not Economy.can_afford(GameState.player_id, price)
		var sid: String = species_id
		buy.pressed.connect(func(): _do(PlayerActions.buy_pet(sid)))
		row.add_child(buy)
		_pet_list.add_child(row)


func _update_land_buttons() -> void:
	var cheapest := _cheapest_plot_for_sale()
	if cheapest == null:
		_land_button.text = "No land for sale"
		_land_button.disabled = true
	else:
		_land_button.text = "Buy cheapest plot ($%d)" % cheapest.list_price
		_land_button.disabled = not Economy.can_afford(GameState.player_id, cheapest.list_price)
	var empty := _first_empty_owned_plot()
	var shop_cost := int(DataRegistry.get_def("buildings", "shop").get("build_cost", 1200))
	_build_button.text = "Build a Shop ($%d)" % shop_cost
	_build_button.disabled = empty == null or not Economy.can_afford(GameState.player_id, shop_cost)
	var upgradable := _first_upgradable_plot()
	if upgradable == null:
		_upgrade_button.text = "Upgrade a building"
		_upgrade_button.disabled = true
	else:
		var cost := upgradable.upgrade_cost()
		_upgrade_button.text = "Upgrade %s ($%d)" % [upgradable.building_id, cost]
		_upgrade_button.disabled = not Economy.can_afford(GameState.player_id, cost)


# --- Actions -----------------------------------------------------------------

func _on_work() -> void:
	_do(PlayerActions.work())


func _on_buy_land() -> void:
	var plot := _cheapest_plot_for_sale()
	if plot:
		_do(PlayerActions.buy_land(plot.id))


func _on_build() -> void:
	var plot := _first_empty_owned_plot()
	if plot:
		_do(PlayerActions.build(plot.id, "shop"))


func _on_upgrade() -> void:
	var plot := _first_upgradable_plot()
	if plot:
		_do(PlayerActions.upgrade_building(plot.id))


func _on_claim(quest_id: String) -> void:
	QuestSystem.claim(quest_id)
	_refresh()


func _do(result: Dictionary) -> void:
	_log_label.text = result.get("message", "")
	_refresh()


# --- Helpers -----------------------------------------------------------------

func _cheapest_plot_for_sale() -> PropertyPlot:
	var best: PropertyPlot = null
	for plot in GameState.plots_for_sale():
		if best == null or plot.list_price < best.list_price:
			best = plot
	return best


func _first_empty_owned_plot() -> PropertyPlot:
	var player := GameState.player()
	if player == null:
		return null
	for plot_id in player.plot_ids:
		var plot := GameState.get_plot(plot_id)
		if plot and plot.is_empty():
			return plot
	return null


func _first_upgradable_plot() -> PropertyPlot:
	var player := GameState.player()
	if player == null:
		return null
	for plot_id in player.plot_ids:
		var plot := GameState.get_plot(plot_id)
		if plot and plot.can_upgrade():
			return plot
	return null


func _player_net_worth() -> int:
	var worth := Economy.balance(GameState.player_id)
	var player := GameState.player()
	if player == null:
		return worth
	for plot_id in player.plot_ids:
		var plot := GameState.get_plot(plot_id)
		if plot:
			worth += plot.appraised_value()
	for pet_id in player.pet_ids:
		var pet := GameState.get_pet(pet_id)
		if pet:
			worth += pet.market_value()
	return worth


func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.96, 0.77, 0.19))
	return l
