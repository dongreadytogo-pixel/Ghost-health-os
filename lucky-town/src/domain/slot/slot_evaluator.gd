class_name SlotEvaluator
extends RefCounted
## Pure slot mathematics: spin a machine and score the outcome.
##
## This class is deliberately free of any scene/UI/economy dependency so it can
## be unit-tested in isolation and its return-to-player (RTP) estimated by
## Monte-Carlo. All randomness is injected via a `RandomNumberGenerator`, so a
## given seed always yields the same grid — the foundation of provable fairness.

const _WILD := "__wild__"


## Spin `config` with `rng`, betting `bet` coins. `jackpot_pot` is the current
## progressive pot, awarded in full on a jackpot line.
static func spin(config: SlotMachineConfig, rng: RandomNumberGenerator, bet: int, jackpot_pot: int = 0) -> SlotSpinResult:
	var result := SlotSpinResult.new()
	result.total_bet = bet
	result.grid = _roll_grid(config, rng)
	_score_lines(config, result, bet)
	_score_scatters(config, result, bet)
	_check_jackpot(config, result, jackpot_pot)
	return result


# --- Grid generation ---------------------------------------------------------

static func _roll_grid(config: SlotMachineConfig, rng: RandomNumberGenerator) -> Array:
	var grid: Array = []
	for reel_index in config.reels.size():
		var strip: Array = config.reels[reel_index]
		var stop := rng.randi_range(0, strip.size() - 1)
		var column: Array = []
		for row in config.rows:
			var idx := (stop + row) % strip.size()
			column.append(StringName(strip[idx]))
		grid.append(column)
	return grid


# --- Line scoring ------------------------------------------------------------

static func _score_lines(config: SlotMachineConfig, result: SlotSpinResult, bet: int) -> void:
	var wild_set := _to_set(config.wild_ids)
	for line_index in config.paylines.size():
		var line: Array = config.paylines[line_index]
		var symbols := _symbols_on_line(result.grid, line)
		var run := _matching_run(symbols, wild_set)
		var run_symbol: String = run["symbol"]
		var run_length: int = run["length"]
		if run_symbol == "" or run_length < 2:
			continue
		var payout := _line_payout(config, run_symbol, run_length, bet)
		if payout > 0:
			result.line_wins.append({
				"line_index": line_index,
				"symbol": run_symbol,
				"count": run_length,
				"payout": payout,
			})
			result.total_payout += payout


static func _symbols_on_line(grid: Array, line: Array) -> Array:
	var out: Array = []
	for reel_index in line.size():
		var row: int = line[reel_index]
		out.append(grid[reel_index][row])
	return out


## Length of the leading run of matching symbols from reel 0, treating wilds as
## substitutes. The "base symbol" is the first non-wild; an all-wild prefix
## still counts (resolved to wild, which has no paytable entry and pays 0).
static func _matching_run(symbols: Array, wild_set: Dictionary) -> Dictionary:
	var base := ""
	var length := 0
	for s in symbols:
		var key := String(s)
		var is_wild := wild_set.has(key)
		if base == "":
			if not is_wild:
				base = key
			length += 1
		elif key == base or is_wild:
			length += 1
		else:
			break
	return {"symbol": base, "length": length}


static func _line_payout(config: SlotMachineConfig, symbol: String, length: int, bet: int) -> int:
	if not config.paytable.has(symbol):
		return 0
	var multipliers: Array = config.paytable[symbol]
	var index := length - 1
	if index < 0 or index >= multipliers.size():
		return 0
	var multiplier := float(multipliers[index])
	# Multipliers are expressed per-bet, so the payout scales with the wager.
	return int(round(multiplier * float(bet)))


# --- Scatter scoring ---------------------------------------------------------

static func _score_scatters(config: SlotMachineConfig, result: SlotSpinResult, bet: int) -> void:
	if config.scatter_ids.is_empty():
		return
	for scatter_id in config.scatter_ids:
		var key := String(scatter_id)
		var count := _count_symbol(result.grid, key)
		var payout := _scatter_payout(config, key, count, bet)
		if payout > 0:
			result.scatter_wins.append({"symbol": key, "count": count, "payout": payout})
			result.total_payout += payout


static func _scatter_payout(config: SlotMachineConfig, symbol: String, count: int, bet: int) -> int:
	if not config.scatter_pays.has(symbol):
		return 0
	var table: Dictionary = config.scatter_pays[symbol]
	# Find the highest threshold that the count satisfies.
	var best := -1
	var best_mult := 0.0
	for threshold_key in table:
		var threshold := int(threshold_key)
		if count >= threshold and threshold > best:
			best = threshold
			best_mult = float(table[threshold_key])
	if best < 0:
		return 0
	return int(round(best_mult * float(bet)))


# --- Jackpot -----------------------------------------------------------------

static func _check_jackpot(config: SlotMachineConfig, result: SlotSpinResult, jackpot_pot: int) -> void:
	if String(config.jackpot_symbol) == "" or jackpot_pot <= 0:
		return
	for line in config.paylines:
		var symbols := _symbols_on_line(result.grid, line)
		var hits := 0
		for s in symbols:
			if String(s) == String(config.jackpot_symbol):
				hits += 1
			else:
				break
		if hits >= config.jackpot_line_length:
			result.jackpot_won = true
			result.jackpot_amount = jackpot_pot
			return


# --- Analysis ----------------------------------------------------------------

## Monte-Carlo estimate of return-to-player over `iterations` spins at `bet`.
## Returns the ratio paid_out / wagered (jackpot excluded — it is funded
## separately). Used by tooling and tests to keep machines within a fair band.
static func estimate_rtp(config: SlotMachineConfig, rng: RandomNumberGenerator, iterations: int = 100000, bet: int = 100) -> float:
	var wagered := 0
	var paid := 0
	for _i in iterations:
		var r := spin(config, rng, bet, 0)
		wagered += bet
		paid += r.total_payout
	if wagered == 0:
		return 0.0
	return float(paid) / float(wagered)


# --- Helpers -----------------------------------------------------------------

static func _count_symbol(grid: Array, symbol: String) -> int:
	var n := 0
	for column in grid:
		for s in column:
			if String(s) == symbol:
				n += 1
	return n


static func _to_set(ids: Array) -> Dictionary:
	var set := {}
	for id in ids:
		set[String(id)] = true
	return set
