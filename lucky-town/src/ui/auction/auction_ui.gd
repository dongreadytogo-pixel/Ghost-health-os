extends CanvasLayer
## The auction house screen (toggle with V).
##
## Lists every open lot with its estimated value, current high bid and bidder,
## and a one-tap "Bid" at the next minimum increment. The player can also list
## their most valuable pet for sale. Like the Town Board it is a pure view: it
## calls `PlayerActions` / `AuctionHouse` and rebuilds itself from the resulting
## `EventBus` signals, so AI bids that arrive while it is open show up live.

@onready var _root: Control = $Root
@onready var _money_label: Label = $Root/Panel/Margin/VBox/MoneyLabel
@onready var _lot_list: VBoxContainer = $Root/Panel/Margin/VBox/Scroll/LotList
@onready var _log_label: Label = $Root/Panel/Margin/VBox/LogLabel
@onready var _list_pet_button: Button = $Root/Panel/Margin/VBox/ListPetButton


func _ready() -> void:
	_root.hide()
	_list_pet_button.pressed.connect(_on_list_pet)
	EventBus.auction_listed.connect(_refresh1)
	EventBus.auction_bid.connect(_refresh3)
	EventBus.auction_sold.connect(_refresh3)
	EventBus.auction_expired.connect(_refresh1)
	EventBus.money_changed.connect(_refresh3)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_auction"):
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


func _refresh1(_a) -> void:
	_refresh_if_visible()


func _refresh3(_a, _b, _c) -> void:
	_refresh_if_visible()


func _refresh_if_visible() -> void:
	if _root.visible:
		_refresh()


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	_money_label.text = "Cash: $%s" % Money.of(Economy.balance(GameState.player_id)).format_full()
	_clear(_lot_list)
	var lots: Array = AuctionHouse.open_lots()
	if lots.is_empty():
		_lot_list.add_child(_label("No open lots. Check back soon — citizens list pets daily."))
		return
	for lot in lots:
		_lot_list.add_child(_lot_row(lot))


func _lot_row(lot: AuctionLot) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var value := AuctionHouse.intrinsic_value(lot)
	var bidder_name := "—"
	if lot.has_bid():
		var c := GameState.get_citizen(lot.current_bidder)
		bidder_name = c.citizen_name if c else lot.current_bidder
	var info := _label("%s — est. $%s | bid $%s (%s)" % [
		_lot_name(lot), Money.of(value).format_short(),
		Money.of(lot.current_bid).format_short(), bidder_name,
	])
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var next := lot.next_min_bid()
	var bid_button := Button.new()
	bid_button.text = "Bid $%s" % Money.of(next).format_short()
	var is_self := lot.seller_id == GameState.player_id or lot.current_bidder == GameState.player_id
	bid_button.disabled = is_self or not Economy.can_afford(GameState.player_id, next)
	var lot_id: String = lot.id
	bid_button.pressed.connect(func(): _do(PlayerActions.bid(lot_id, next)))
	row.add_child(bid_button)
	return row


func _lot_name(lot: AuctionLot) -> String:
	match lot.item_type:
		AuctionLot.ItemType.PET:
			var pet := GameState.get_pet(lot.item_id)
			if pet:
				var def := DataRegistry.get_def("pet_species", pet.species_id)
				return "%s (Lv%d, %d%%)" % [def.get("display_name", pet.species_id), pet.level, int(pet.quality() * 100.0)]
			return "Pet"
		AuctionLot.ItemType.PLOT:
			var plot := GameState.get_plot(lot.item_id)
			return "Plot (%d,%d)" % [plot.grid_x, plot.grid_y] if plot else "Plot"
		AuctionLot.ItemType.ITEM:
			return "%d x %s" % [lot.quantity, lot.item_id]
	return lot.title()


# --- Actions -----------------------------------------------------------------

func _on_list_pet() -> void:
	var best := _player_best_pet()
	if best == null:
		_log_label.text = "You have no pets to list."
		return
	_do(PlayerActions.list_pet_auction(best.id))


func _player_best_pet() -> Pet:
	var player := GameState.player()
	if player == null:
		return null
	var best: Pet = null
	for pet_id in player.pet_ids:
		var pet := GameState.get_pet(pet_id)
		if pet and (best == null or pet.market_value() > best.market_value()):
			best = pet
	return best


func _do(result: Dictionary) -> void:
	_log_label.text = result.get("message", "")
	_refresh()


# --- Helpers -----------------------------------------------------------------

func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l
