class_name AuctionLot
extends RefCounted
## One item up for auction.
##
## A lot is a thin, serialisable record: *what* is being sold (a pet, a plot, or
## a stack of a market item), *who* is selling, the current high bid and bidder,
## and when bidding closes. The auction house owns the lifecycle; this is just
## the data. Keeping the sold thing as a typed reference (`item_type` + `item_id`)
## rather than the object itself means lots survive save/load and never pin a
## live entity.

enum ItemType { PET, PLOT, ITEM }
enum State { OPEN, SOLD, EXPIRED }

var id: String = ""
var item_type: int = ItemType.PET
var item_id: String = ""          # pet id, plot id, or market item id
var quantity: int = 1             # for ITEM stacks
var seller_id: String = ""

var min_bid: int = 0
var current_bid: int = 0
var current_bidder: String = ""   # "" == no bids yet

## Closes when GameClock total hours reaches `close_hour_stamp`.
var close_hour_stamp: int = 0
var state: int = State.OPEN


static func new_id() -> String:
	return "lot_%d_%d" % [Time.get_ticks_usec(), randi() % 100000]


func has_bid() -> bool:
	return current_bidder != ""


## The minimum a new bid must reach to be valid (a 5% or +10 step over current).
func next_min_bid() -> int:
	if not has_bid():
		return min_bid
	return current_bid + maxi(10, int(round(float(current_bid) * 0.05)))


func is_closed(now_hour_stamp: int) -> bool:
	return now_hour_stamp >= close_hour_stamp


func title() -> String:
	match item_type:
		ItemType.PET:
			return "Pet"
		ItemType.PLOT:
			return "Land plot"
		ItemType.ITEM:
			return "%d x item" % quantity
	return "Lot"


func to_dict() -> Dictionary:
	return {
		"id": id, "item_type": item_type, "item_id": item_id, "quantity": quantity,
		"seller_id": seller_id, "min_bid": min_bid, "current_bid": current_bid,
		"current_bidder": current_bidder, "close_hour_stamp": close_hour_stamp,
		"state": state,
	}


static func from_dict(data: Dictionary) -> AuctionLot:
	var lot := AuctionLot.new()
	lot.id = data.get("id", new_id())
	lot.item_type = int(data.get("item_type", ItemType.PET))
	lot.item_id = data.get("item_id", "")
	lot.quantity = int(data.get("quantity", 1))
	lot.seller_id = data.get("seller_id", "")
	lot.min_bid = int(data.get("min_bid", 0))
	lot.current_bid = int(data.get("current_bid", 0))
	lot.current_bidder = data.get("current_bidder", "")
	lot.close_hour_stamp = int(data.get("close_hour_stamp", 0))
	lot.state = int(data.get("state", State.OPEN))
	return lot
