extends Node
## The city's financial system: a single authoritative ledger plus a dynamic
## market and the progressive slot jackpots.
##
## Every actor — the player and every AI citizen — has a balance keyed by a
## stable owner id. Centralising balances here (rather than scattering money on
## nodes) makes "richest citizen" rankings, auctions and the dynamic economy
## trivial to compute, keeps the save file authoritative, and gives a single
## choke point that a future server could become.
##
## Market prices move with supply and demand: buying raises demand (and price),
## selling raises supply (and lowers price), and both relax toward a baseline
## each day. Nothing stays static forever, exactly as the design demands.

const PLAYER_ID := "player"

# owner_id -> int balance (coins)
var _balances: Dictionary = {}
# machine_id -> int progressive pot
var _jackpots: Dictionary = {}
# item_id -> { base, supply, demand, price, min, max }
var _market: Dictionary = {}

var _transaction_seq := 0


func _ready() -> void:
	EventBus.day_started.connect(_on_day_started)
	DataRegistry.data_loaded.connect(_init_market)
	if DataRegistry.is_loaded():
		_init_market()


# --- Balances ----------------------------------------------------------------

func open_account(owner_id: String, starting: int = 0) -> void:
	if not _balances.has(owner_id):
		_balances[owner_id] = starting


func balance(owner_id: String) -> int:
	return int(_balances.get(owner_id, 0))


func balance_money(owner_id: String) -> Money:
	return Money.of(balance(owner_id))


func can_afford(owner_id: String, cost: int) -> bool:
	return balance(owner_id) >= cost


## Add coins. Use a meaningful `reason` for the transaction log.
func credit(owner_id: String, amount: int, reason: String = "") -> void:
	if amount == 0:
		return
	open_account(owner_id)
	_balances[owner_id] += amount
	_record(owner_id, amount, reason)
	EventBus.money_changed.emit(owner_id, _balances[owner_id], amount)


## Remove coins if affordable. Returns false (and changes nothing) otherwise.
func debit(owner_id: String, amount: int, reason: String = "") -> bool:
	if amount <= 0:
		return amount == 0
	if not can_afford(owner_id, amount):
		return false
	_balances[owner_id] -= amount
	_record(owner_id, -amount, reason)
	EventBus.money_changed.emit(owner_id, _balances[owner_id], -amount)
	return true


## Move coins between two actors atomically. Returns false if the payer cannot
## afford it.
func transfer(from_id: String, to_id: String, amount: int, reason: String = "") -> bool:
	if not debit(from_id, amount, reason):
		return false
	credit(to_id, amount, reason)
	return true


# --- Jackpots ----------------------------------------------------------------

func jackpot(machine_id: String) -> int:
	return int(_jackpots.get(machine_id, 0))


func seed_jackpot(machine_id: String, amount: int) -> void:
	_jackpots[machine_id] = maxi(int(_jackpots.get(machine_id, 0)), amount)


func contribute_jackpot(machine_id: String, amount: int) -> void:
	_jackpots[machine_id] = int(_jackpots.get(machine_id, 0)) + amount


## Pay out and reset a jackpot. Returns the amount awarded.
func claim_jackpot(machine_id: String, winner_id: String) -> int:
	var pot := jackpot(machine_id)
	if pot > 0:
		credit(winner_id, pot, "jackpot:%s" % machine_id)
		_jackpots[machine_id] = 0
		EventBus.slot_jackpot_won.emit(machine_id, winner_id, pot)
	return pot


# --- Market ------------------------------------------------------------------

func _init_market() -> void:
	for id in DataRegistry.ids("market_items"):
		var def := DataRegistry.get_def("market_items", id)
		var base := int(def.get("base_price", 100))
		_market[id] = {
			"base": base,
			"price": base,
			"supply": float(def.get("supply", 100.0)),
			"demand": float(def.get("demand", 100.0)),
			"min": int(def.get("min_price", maxi(1, base / 5))),
			"max": int(def.get("max_price", base * 5)),
		}
	Log.info("Economy", "Market initialised with %d items" % _market.size())


func price(item_id: String) -> int:
	return int(_market.get(item_id, {}).get("price", 0))


## Register demand pressure from a purchase of `qty` units (raises price).
func register_purchase(item_id: String, qty: int = 1) -> void:
	if not _market.has(item_id):
		return
	_market[item_id]["demand"] += float(qty)
	_reprice(item_id)


## Register supply pressure from a sale of `qty` units (lowers price).
func register_sale(item_id: String, qty: int = 1) -> void:
	if not _market.has(item_id):
		return
	_market[item_id]["supply"] += float(qty)
	_reprice(item_id)


func _reprice(item_id: String) -> void:
	var m: Dictionary = _market[item_id]
	var supply: float = maxf(1.0, m["supply"])
	var demand: float = maxf(1.0, m["demand"])
	# Price scales with the demand/supply ratio around the baseline.
	var ratio := demand / supply
	var new_price := int(round(float(m["base"]) * ratio))
	m["price"] = clampi(new_price, m["min"], m["max"])
	EventBus.market_price_changed.emit(item_id, m["price"])


# Each day, supply and demand relax toward the baseline so shocks fade.
func _on_day_started(_day: int) -> void:
	for item_id in _market:
		var m: Dictionary = _market[item_id]
		m["supply"] = lerpf(m["supply"], 100.0, 0.15)
		m["demand"] = lerpf(m["demand"], 100.0, 0.15)
		_reprice(item_id)


func _record(owner_id: String, delta: int, reason: String) -> void:
	_transaction_seq += 1
	var record := {
		"seq": _transaction_seq,
		"owner": owner_id,
		"delta": delta,
		"balance": _balances[owner_id],
		"reason": reason,
		"day": GameClock.day,
	}
	EventBus.transaction_recorded.emit(record)


# --- Persistence -------------------------------------------------------------

func to_save() -> Dictionary:
	return {
		"balances": _balances.duplicate(true),
		"jackpots": _jackpots.duplicate(true),
		"market": _market.duplicate(true),
		"transaction_seq": _transaction_seq,
	}


func from_save(data: Dictionary) -> void:
	_balances = data.get("balances", {}).duplicate(true)
	_jackpots = data.get("jackpots", {}).duplicate(true)
	_market = data.get("market", {}).duplicate(true)
	_transaction_seq = int(data.get("transaction_seq", 0))
	if _market.is_empty():
		_init_market()
