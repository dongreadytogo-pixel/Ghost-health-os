extends Node
## The city's auction house: list, bid, settle.
##
## Players and AI sell pets, land and rare goods here. Bids are escrowed — when
## someone is outbid their coins are refunded immediately and the new high bid
## is debited — so the winning funds always exist at settlement and no one can
## bid money they don't have. AI citizens evaluate open lots each hour via the
## pure `AuctionValuation`, so a Collector will chase a rare pet and a
## Speculator a central plot, making the market feel contested.
##
## Settlement runs on the clock: when a lot's close stamp passes, the item moves
## to the winner and the seller is paid (or the item returns to the seller if
## there were no bids). Everything is serialised with the save.

## How many AI bidders are sampled per open lot each hour (bounds cost).
@export var ai_bidders_per_lot: int = 3
@export var default_duration_hours: int = 8

var _lots: Dictionary = {}        # lot_id -> AuctionLot (open lots only)


func _ready() -> void:
	EventBus.hour_ticked.connect(_on_hour)


# --- Listing -----------------------------------------------------------------

func open_lots() -> Array:
	return _lots.values()

## List a pet. The pet is escrowed (removed from the seller's roster) until the
## auction settles. Returns the new lot id, or "" on failure.
func list_pet(seller_id: String, pet_id: String, min_bid: int = -1, duration_hours: int = -1) -> String:
	var pet := GameState.get_pet(pet_id)
	if pet == null or pet.owner_id != seller_id:
		return ""
	var lot := _new_lot(AuctionLot.ItemType.PET, pet_id, seller_id, min_bid, duration_hours)
	lot.min_bid = min_bid if min_bid >= 0 else int(round(float(pet.market_value()) * 0.7))
	lot.current_bid = lot.min_bid
	# Escrow: detach from owner so it can't be sold twice; the pet object stays
	# in GameState.pets so bidders can appraise it.
	var owner := GameState.get_citizen(seller_id)
	if owner:
		owner.pet_ids.erase(pet_id)
	pet.owner_id = ""
	_register(lot)
	return lot.id


## List a plot the seller owns.
func list_plot(seller_id: String, plot_id: String, min_bid: int = -1, duration_hours: int = -1) -> String:
	var plot := GameState.get_plot(plot_id)
	if plot == null or plot.owner_id != seller_id:
		return ""
	var lot := _new_lot(AuctionLot.ItemType.PLOT, plot_id, seller_id, min_bid, duration_hours)
	lot.min_bid = min_bid if min_bid >= 0 else int(round(float(plot.appraised_value()) * 0.8))
	lot.current_bid = lot.min_bid
	plot.for_sale = false
	_register(lot)
	return lot.id


# --- Bidding -----------------------------------------------------------------

## Place a bid. Returns true on success. Escrows the bid and refunds the prior
## high bidder.
func place_bid(lot_id: String, bidder_id: String, amount: int) -> bool:
	var lot: AuctionLot = _lots.get(lot_id)
	if lot == null or lot.state != AuctionLot.State.OPEN:
		return false
	if bidder_id == lot.seller_id or bidder_id == lot.current_bidder:
		return false
	var required := lot.next_min_bid()
	if amount < required:
		return false
	# Escrow the new high bid first; only once it is secured do we refund the
	# outbid leader, so a failed debit can never hand out money for nothing.
	if not Economy.debit(bidder_id, amount, "auction_bid:%s" % lot_id):
		return false
	if lot.has_bid():
		Economy.credit(lot.current_bidder, lot.current_bid, "auction_refund:%s" % lot_id)
	lot.current_bid = amount
	lot.current_bidder = bidder_id
	EventBus.auction_bid.emit(lot_id, bidder_id, amount)
	return true


func intrinsic_value(lot: AuctionLot) -> int:
	match lot.item_type:
		AuctionLot.ItemType.PET:
			var pet := GameState.get_pet(lot.item_id)
			return pet.market_value() if pet else 0
		AuctionLot.ItemType.PLOT:
			var plot := GameState.get_plot(lot.item_id)
			return plot.appraised_value() if plot else 0
		AuctionLot.ItemType.ITEM:
			return Economy.price(lot.item_id) * lot.quantity
	return 0


# --- Hourly AI bidding + settlement ------------------------------------------

func _on_hour(_day: int, _hour: int) -> void:
	if not GameState.initialised:
		return
	_run_ai_bidding()
	_settle_closed()


func _run_ai_bidding() -> void:
	var ai := GameState.ai_citizens()
	if ai.is_empty():
		return
	for lot in _lots.values():
		if lot.state != AuctionLot.State.OPEN:
			continue
		var value := intrinsic_value(lot)
		if value <= 0:
			continue
		for _i in mini(ai_bidders_per_lot, ai.size()):
			var bidder: Citizen = ai[RngService.range_i("auction_pick", 0, ai.size() - 1)]
			_maybe_ai_bid(lot, bidder, value)


func _maybe_ai_bid(lot: AuctionLot, bidder: Citizen, value: int) -> void:
	if bidder.id == lot.seller_id or bidder.id == lot.current_bidder:
		return
	var personality := Personality.from_def(DataRegistry.get_def("personalities", bidder.personality_id))
	var interest := AuctionValuation.interest_in(lot.item_type, personality.action_weights)
	var max_pay := AuctionValuation.willingness_to_pay(
		value, Economy.balance(bidder.id), interest, personality.risk_tolerance, personality.frugality)
	var required := lot.next_min_bid()
	if max_pay < required:
		return
	# Bid the minimum increment most of the time; occasionally jump to discourage
	# rivals, scaled by risk tolerance.
	var aggressive := RngService.chance("auction_jump", 0.25 * personality.risk_tolerance)
	var amount := required if not aggressive else mini(max_pay, int(round(float(required) * 1.15)))
	place_bid(lot.id, bidder.id, amount)


func _settle_closed() -> void:
	var now := GameClock.total_hours()
	for lot_id in _lots.keys():
		var lot: AuctionLot = _lots[lot_id]
		if lot.state == AuctionLot.State.OPEN and lot.is_closed(now):
			_settle(lot)
			_lots.erase(lot_id)


func _settle(lot: AuctionLot) -> void:
	if lot.has_bid():
		_award(lot, lot.current_bidder)
		Economy.credit(lot.seller_id, lot.current_bid, "auction_sale:%s" % lot.id)
		lot.state = AuctionLot.State.SOLD
		EventBus.auction_sold.emit(lot.id, lot.current_bidder, lot.current_bid)
		if lot.current_bidder == GameState.player_id or lot.seller_id == GameState.player_id:
			EventBus.notification_posted.emit("Auction settled: %s" % lot.title(), 2)
	else:
		_return_to_seller(lot)
		lot.state = AuctionLot.State.EXPIRED
		EventBus.auction_expired.emit(lot.id)


func _award(lot: AuctionLot, winner_id: String) -> void:
	match lot.item_type:
		AuctionLot.ItemType.PET:
			var pet := GameState.get_pet(lot.item_id)
			if pet:
				pet.owner_id = winner_id
				var winner := GameState.get_citizen(winner_id)
				if winner and not winner.pet_ids.has(pet.id):
					winner.pet_ids.append(pet.id)
		AuctionLot.ItemType.PLOT:
			var plot := GameState.get_plot(lot.item_id)
			if plot:
				_reassign_plot(plot, winner_id)
		AuctionLot.ItemType.ITEM:
			var winner := GameState.get_citizen(winner_id)
			if winner:
				winner.inventory[lot.item_id] = int(winner.inventory.get(lot.item_id, 0)) + lot.quantity


func _return_to_seller(lot: AuctionLot) -> void:
	match lot.item_type:
		AuctionLot.ItemType.PET:
			var pet := GameState.get_pet(lot.item_id)
			if pet:
				pet.owner_id = lot.seller_id
				var seller := GameState.get_citizen(lot.seller_id)
				if seller and not seller.pet_ids.has(pet.id):
					seller.pet_ids.append(pet.id)
		AuctionLot.ItemType.PLOT:
			var plot := GameState.get_plot(lot.item_id)
			if plot:
				plot.for_sale = false  # stays with the seller


func _reassign_plot(plot: PropertyPlot, new_owner_id: String) -> void:
	var old := GameState.get_citizen(plot.owner_id)
	if old:
		old.plot_ids.erase(plot.id)
	plot.owner_id = new_owner_id
	plot.for_sale = false
	var owner := GameState.get_citizen(new_owner_id)
	if owner and not owner.plot_ids.has(plot.id):
		owner.plot_ids.append(plot.id)


# --- Helpers -----------------------------------------------------------------

func _new_lot(item_type: int, item_id: String, seller_id: String, _min_bid: int, duration_hours: int) -> AuctionLot:
	var lot := AuctionLot.new()
	lot.id = AuctionLot.new_id()
	lot.item_type = item_type
	lot.item_id = item_id
	lot.seller_id = seller_id
	var dur := duration_hours if duration_hours > 0 else default_duration_hours
	lot.close_hour_stamp = GameClock.total_hours() + dur
	return lot


func _register(lot: AuctionLot) -> void:
	_lots[lot.id] = lot
	EventBus.auction_listed.emit(lot.to_dict())


# --- Persistence -------------------------------------------------------------

func to_save() -> Dictionary:
	var arr: Array = []
	for lot in _lots.values():
		arr.append(lot.to_dict())
	return {"lots": arr}


func from_save(data: Dictionary) -> void:
	_lots.clear()
	for d in data.get("lots", []):
		var lot := AuctionLot.from_dict(d)
		_lots[lot.id] = lot
