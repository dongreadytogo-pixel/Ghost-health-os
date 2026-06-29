class_name SlotSpinResult
extends RefCounted
## Immutable outcome of a single spin.
##
## Produced by `SlotEvaluator`. It carries everything the UI needs to animate
## the result and everything the economy needs to settle the bet, plus a
## `to_dict()` so the result can travel across the `EventBus` and be logged.

## grid[reel][row] -> symbol id (StringName).
var grid: Array = []

## One entry per winning payline: {line_index, symbol, count, payout}.
var line_wins: Array = []

## Scatter wins: {symbol, count, payout}.
var scatter_wins: Array = []

var total_bet: int = 0
var total_payout: int = 0
var jackpot_won: bool = false
var jackpot_amount: int = 0


func net() -> int:
	return total_payout + jackpot_amount - total_bet


func is_win() -> bool:
	return (total_payout + jackpot_amount) > 0


func to_dict() -> Dictionary:
	return {
		"grid": grid,
		"line_wins": line_wins,
		"scatter_wins": scatter_wins,
		"total_bet": total_bet,
		"total_payout": total_payout,
		"jackpot_won": jackpot_won,
		"jackpot_amount": jackpot_amount,
		"net": net(),
	}
