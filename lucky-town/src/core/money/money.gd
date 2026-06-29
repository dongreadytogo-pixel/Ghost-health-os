class_name Money
extends RefCounted
## Immutable currency value object.
##
## All in-game wealth is stored as a whole number of the smallest currency unit
## ("coins"). Using integers — never floats — guarantees that economic maths is
## exact and reproducible, which matters for slot payouts, auctions and the
## save file. Display formatting (e.g. "1.2K", "3.4M") is a pure function of the
## raw amount and lives here so every screen formats money identically.

var _amount: int = 0


func _init(amount: int = 0) -> void:
	_amount = amount


static func zero() -> Money:
	return Money.new(0)


static func of(amount: int) -> Money:
	return Money.new(amount)


func amount() -> int:
	return _amount


func is_zero() -> bool:
	return _amount == 0


func is_positive() -> bool:
	return _amount > 0


func plus(other: Money) -> Money:
	return Money.new(_amount + other._amount)


func minus(other: Money) -> Money:
	return Money.new(_amount - other._amount)


func scaled(factor: float) -> Money:
	return Money.new(int(round(float(_amount) * factor)))


## True when this balance can cover `cost` without going negative.
func can_afford(cost: Money) -> bool:
	return _amount >= cost._amount


func equals(other: Money) -> bool:
	return other != null and _amount == other._amount


func compare(other: Money) -> int:
	return signi(_amount - other._amount)


## Compact, human-friendly representation, e.g. 1500 -> "1.5K".
func format_short() -> String:
	var n := absi(_amount)
	var sign_str := "-" if _amount < 0 else ""
	if n < 1000:
		return "%s%d" % [sign_str, n]
	var units := ["K", "M", "B", "T"]
	var value := float(n)
	var index := -1
	while value >= 1000.0 and index < units.size() - 1:
		value /= 1000.0
		index += 1
	return "%s%s%s" % [sign_str, _trim(value), units[index]]


## Full grouped representation, e.g. 1500000 -> "1,500,000".
func format_full() -> String:
	var n := absi(_amount)
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i != 0:
			out = "," + out
	return ("-" if _amount < 0 else "") + out


func _trim(value: float) -> String:
	# One decimal place, dropping a trailing ".0".
	var text := "%.1f" % value
	if text.ends_with(".0"):
		text = text.substr(0, text.length() - 2)
	return text
