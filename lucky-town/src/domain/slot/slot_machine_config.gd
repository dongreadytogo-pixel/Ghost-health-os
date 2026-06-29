class_name SlotMachineConfig
extends Resource
## Complete, data-driven definition of one slot machine.
##
## A machine is fully described by its reel strips, paylines and paytable, so
## new themed machines (Fantasy, Cyberpunk, Ghost, Sci-fi …) are authored as
## data — `.tres` Resources or JSON loaded via `from_dict` — with zero code
## changes. The mathematical fairness (return-to-player) is a property of this
## data and can be verified by `SlotEvaluator.estimate_rtp`.
##
## Grid model: `rows` × `reels.size()`. Each reel is a "strip": an ordered list
## of symbol ids. A spin picks a random stop index per reel and reads `rows`
## consecutive symbols (wrapping) from that strip — the classic virtual-reel
## model used by real machines, which makes the odds explicit and auditable.

@export var id: StringName = &""
@export var display_name: String = "Slot Machine"
@export var theme: String = "classic"

## Visible grid height. Width is `reels.size()`.
@export var rows: int = 3

## One entry per reel. Each entry is an Array[StringName] of symbol ids (the
## "strip"). Stored as Array to stay friendly to JSON authoring.
@export var reels: Array = []

## Paylines as row indices, one per reel. e.g. [1,1,1,1,1] is the middle row.
## A win requires matching symbols on consecutive reels along a line.
@export var paylines: Array = []

## Paytable: symbol id -> Array where index N is the multiplier for a run of
## (N+1) matching symbols. e.g. {"seven": [0, 0, 5, 20, 100]} pays 5x for three.
@export var paytable: Dictionary = {}

## Symbol id -> count threshold -> flat coin payout, independent of paylines.
## Used for scatter symbols. e.g. {"scatter": {"3": 50, "4": 200}}.
@export var scatter_pays: Dictionary = {}

## Symbol ids that substitute for any non-scatter symbol in a line.
@export var wild_ids: Array = []

## Symbol ids treated as scatters (counted anywhere on the grid).
@export var scatter_ids: Array = []

## Betting.
@export var min_bet: int = 10
@export var max_bet: int = 1000
@export var bet_step: int = 10

## Progressive jackpot: a fraction of each bet feeds a shared pot.
@export var jackpot_contribution: float = 0.01
@export var jackpot_symbol: StringName = &""
@export var jackpot_line_length: int = 5


## Build a config from a plain dictionary (JSON theme file). Unknown keys are
## ignored so themes can be forward-compatible.
static func from_dict(data: Dictionary) -> SlotMachineConfig:
	var cfg := SlotMachineConfig.new()
	cfg.id = StringName(data.get("id", ""))
	cfg.display_name = data.get("display_name", "Slot Machine")
	cfg.theme = data.get("theme", "classic")
	cfg.rows = int(data.get("rows", 3))
	cfg.reels = data.get("reels", [])
	cfg.paylines = data.get("paylines", [])
	cfg.paytable = data.get("paytable", {})
	cfg.scatter_pays = data.get("scatter_pays", {})
	cfg.wild_ids = data.get("wild_ids", [])
	cfg.scatter_ids = data.get("scatter_ids", [])
	cfg.min_bet = int(data.get("min_bet", 10))
	cfg.max_bet = int(data.get("max_bet", 1000))
	cfg.bet_step = int(data.get("bet_step", 10))
	cfg.jackpot_contribution = float(data.get("jackpot_contribution", 0.01))
	cfg.jackpot_symbol = StringName(data.get("jackpot_symbol", ""))
	cfg.jackpot_line_length = int(data.get("jackpot_line_length", 5))
	return cfg


func reel_count() -> int:
	return reels.size()


## Validate structural invariants. Returns an empty array when the config is
## sound, otherwise a list of human-readable problems (used by tests and tools).
func validate() -> Array:
	var problems: Array = []
	if reels.is_empty():
		problems.append("config '%s' has no reels" % id)
	if rows <= 0:
		problems.append("rows must be > 0")
	for i in reels.size():
		var strip = reels[i]
		if typeof(strip) != TYPE_ARRAY or strip.is_empty():
			problems.append("reel %d is empty" % i)
		elif strip.size() < rows:
			problems.append("reel %d shorter than rows (%d < %d)" % [i, strip.size(), rows])
	for line in paylines:
		if typeof(line) != TYPE_ARRAY or line.size() != reels.size():
			problems.append("payline %s does not cover every reel" % str(line))
	if min_bet <= 0 or max_bet < min_bet or bet_step <= 0:
		problems.append("invalid bet bounds")
	return problems


func clamp_bet(bet: int) -> int:
	var snapped := int(round(float(bet) / float(bet_step))) * bet_step
	return clampi(snapped, min_bet, max_bet)
