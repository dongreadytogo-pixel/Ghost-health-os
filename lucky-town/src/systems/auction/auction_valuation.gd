class_name AuctionValuation
extends RefCounted
## Pure logic: how much is a lot worth to a given bidder?
##
## Decoupled from the auction house so the bidding maths can be unit-tested and
## tuned. An AI's willingness-to-pay is the lot's intrinsic value scaled by how
## much their personality wants that kind of thing (a Collector overpays for
## pets; a Speculator for land) and bounded by what they can actually afford
## while keeping a personality-sized cash cushion.

## Intrinsic value of a lot, independent of any bidder. Caller supplies the
## resolved intrinsic value (pet market value / plot appraisal / item price)
## because those need autoloads; this keeps the function pure and testable.
static func willingness_to_pay(intrinsic_value: int, balance: int, interest: float, risk_tolerance: float, frugality: float) -> int:
	if intrinsic_value <= 0 or balance <= 0:
		return 0
	# Eagerness: how far above intrinsic value this bidder will reach.
	# interest (0..~1) and risk_tolerance push it up; frugality pulls it down.
	var eagerness := clampf(0.6 + 0.6 * interest + 0.3 * risk_tolerance - 0.4 * frugality, 0.2, 1.6)
	var target := int(round(float(intrinsic_value) * eagerness))
	# Never spend below a reserve cushion sized by frugality.
	var cushion := int(round(float(balance) * (0.1 + 0.4 * frugality)))
	var spendable := maxi(0, balance - cushion)
	return mini(target, spendable)


## Map a personality's category interest onto a lot type. Returns 0..~1.
static func interest_in(item_type: int, action_weights: Dictionary) -> float:
	match item_type:
		AuctionLot.ItemType.PET:
			return maxf(float(action_weights.get("buy_pet", 0.0)), float(action_weights.get("breed_pet", 0.0)))
		AuctionLot.ItemType.PLOT:
			return maxf(float(action_weights.get("buy_land", 0.0)), float(action_weights.get("invest", 0.0)))
		AuctionLot.ItemType.ITEM:
			return float(action_weights.get("shop", 0.0))
	return 0.0
