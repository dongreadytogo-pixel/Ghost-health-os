extends SceneTree
## Dependency-free headless test runner for Lucky Town's pure logic.
##
## Run with:  godot --headless --script res://tests/run_tests.gd
##
## We deliberately avoid a plugin (GUT) so tests run in any CI with just the
## Godot binary. Only *autoload-free* logic is covered here — the deterministic
## core (money maths, slot evaluation, config validation, genetics blending).
## Integration tests that need the full autoload tree live as GUT scenes later.

var _passed := 0
var _failed := 0
var _current := ""


func _initialize() -> void:
	print("=== Lucky Town test run ===")
	_run(test_money_formatting)
	_run(test_money_arithmetic)
	_run(test_slot_config_validation)
	_run(test_slot_bet_clamp)
	_run(test_slot_deterministic_under_seed)
	_run(test_slot_line_win_pays)
	_run(test_slot_rtp_in_band)
	_run(test_pet_quality_bounds)
	_run(test_quest_advance)
	_run(test_quest_roll_dailies)
	_run(test_quest_recovery)
	_run(test_auction_min_bid)
	_run(test_auction_willingness)

	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --- Tests -------------------------------------------------------------------

func test_money_formatting() -> void:
	_eq(Money.of(1500).format_short(), "1.5K", "short 1.5K")
	_eq(Money.of(2000000).format_short(), "2M", "short 2M")
	_eq(Money.of(1500000).format_full(), "1,500,000", "full grouping")
	_eq(Money.of(-2500).format_short(), "-2.5K", "negative short")


func test_money_arithmetic() -> void:
	var a := Money.of(100)
	var b := Money.of(40)
	_eq(a.plus(b).amount(), 140, "plus")
	_eq(a.minus(b).amount(), 60, "minus")
	_true(a.can_afford(b), "can afford")
	_true(not b.can_afford(a), "cannot afford")
	_eq(a.scaled(1.5).amount(), 150, "scaled")


func test_slot_config_validation() -> void:
	var cfg := _make_test_config()
	_true(cfg.validate().is_empty(), "valid config has no problems")
	var bad := SlotMachineConfig.new()
	_true(not bad.validate().is_empty(), "empty config is invalid")


func test_slot_bet_clamp() -> void:
	var cfg := _make_test_config()
	_eq(cfg.clamp_bet(5), 10, "clamp below min")
	_eq(cfg.clamp_bet(13), 10, "snap to step")
	_eq(cfg.clamp_bet(99999), 1000, "clamp above max")


func test_slot_deterministic_under_seed() -> void:
	var cfg := _make_test_config()
	var r1 := SlotEvaluator.spin(cfg, _seeded_rng(42), 100, 0)
	var r2 := SlotEvaluator.spin(cfg, _seeded_rng(42), 100, 0)
	_eq(str(r1.grid), str(r2.grid), "same seed => same grid")


func test_slot_line_win_pays() -> void:
	# A config whose single reel-set guarantees three "seven" on the middle line.
	var cfg := SlotMachineConfig.new()
	cfg.id = &"forced"
	cfg.rows = 1
	cfg.reels = [["seven"], ["seven"], ["seven"]]
	cfg.paylines = [[0, 0, 0]]
	cfg.paytable = {"seven": [0, 0, 5]}  # 5x for three
	cfg.min_bet = 10
	cfg.max_bet = 100
	cfg.bet_step = 10
	var r := SlotEvaluator.spin(cfg, _seeded_rng(1), 10, 0)
	_eq(r.total_payout, 50, "three sevens pay 5x bet")
	_true(r.is_win(), "is a win")


func test_slot_rtp_in_band() -> void:
	var cfg := _make_test_config()
	var rtp := SlotEvaluator.estimate_rtp(cfg, _seeded_rng(7), 40000, 100)
	# Broad sanity band: the machine must pay *something* but not be a money
	# printer. Tighten per-machine once art/economy are tuned.
	_true(rtp > 0.05 and rtp < 1.5, "RTP within sane band (got %f)" % rtp)


func test_pet_quality_bounds() -> void:
	var pet := Pet.new()
	pet.genes = {"a": 0.0, "b": 0.0}
	_true(pet.quality() >= 0.0 and pet.quality() <= 1.0, "quality is bounded")
	pet.genes = {"a": 1.0, "b": 1.0}
	_true(pet.quality() <= 1.0, "quality capped at 1.0")


func test_quest_advance() -> void:
	var q := Quest.from_def({
		"id": "q1", "title": "Spin", "metric": "spin_slot", "target": 3, "reward_coins": 50,
	})
	_true(not q.advance("buy_pet", 1), "wrong metric does not advance")
	_true(not q.advance("spin_slot", 1), "partial progress not complete")
	_eq(q.progress, 1, "progress counted")
	_true(q.advance("spin_slot", 5), "reaching target completes (and clamps)")
	_eq(q.progress, 3, "progress clamped to target")
	_eq(q.state, Quest.State.COMPLETED, "state is completed")
	_true(not q.advance("spin_slot", 1), "completed quest ignores further advances")


func test_quest_roll_dailies() -> void:
	var pool := [
		{"id": "a", "metric": "spin_slot", "target": 1},
		{"id": "b", "metric": "win_slot", "target": 1},
		{"id": "c", "metric": "work", "target": 1},
		{"id": "d", "metric": "buy_pet", "target": 1},
	]
	var dailies := QuestGenerator.roll_dailies(pool, _seeded_rng(3), 5, 3)
	_eq(dailies.size(), 3, "rolls the requested count")
	for q in dailies:
		_eq(q.kind, Quest.Kind.DAILY, "tagged as daily")
		_eq(q.expires_day, 6, "expires next day")
	# Deterministic under a fixed seed.
	var again := QuestGenerator.roll_dailies(pool, _seeded_rng(3), 5, 3)
	_eq(again[0].id, dailies[0].id, "same seed => same selection")


func test_quest_recovery() -> void:
	var q := QuestGenerator.make_recovery(4)
	_eq(q.kind, Quest.Kind.RECOVERY, "recovery kind")
	_eq(q.metric, "work", "recovery is earned by working")
	_true(q.reward_coins > 0, "recovery pays out")
	_eq(q.expires_day, 0, "recovery never expires (always available)")


func test_auction_min_bid() -> void:
	var lot := AuctionLot.new()
	lot.min_bid = 100
	_eq(lot.next_min_bid(), 100, "no bids => min bid")
	lot.current_bid = 100
	lot.current_bidder = "x"
	# +5% of 100 = 5, but floor step is 10.
	_eq(lot.next_min_bid(), 110, "increment respects floor step")
	lot.current_bid = 1000
	_eq(lot.next_min_bid(), 1050, "increment is 5% when above the floor")


func test_auction_willingness() -> void:
	# No value or no money => no bid.
	_eq(AuctionValuation.willingness_to_pay(0, 1000, 1.0, 1.0, 0.0), 0, "zero value => 0")
	_eq(AuctionValuation.willingness_to_pay(500, 0, 1.0, 1.0, 0.0), 0, "no cash => 0")
	# A risk-taking, interested bidder pays more than a frugal, uninterested one.
	var eager := AuctionValuation.willingness_to_pay(500, 5000, 1.0, 0.9, 0.1)
	var meek := AuctionValuation.willingness_to_pay(500, 5000, 0.1, 0.1, 0.9)
	_true(eager > meek, "eagerness raises willingness (%d > %d)" % [eager, meek])
	# Willingness never exceeds what's spendable after the cushion.
	var capped := AuctionValuation.willingness_to_pay(100000, 1000, 1.0, 1.0, 0.0)
	_true(capped <= 1000, "never bids more than balance")


# --- Fixtures & helpers ------------------------------------------------------

func _make_test_config() -> SlotMachineConfig:
	return SlotMachineConfig.from_dict({
		"id": "test",
		"rows": 3,
		"reels": [
			["a", "b", "c", "d", "wild", "a", "b", "c", "scatter", "d"],
			["b", "c", "a", "d", "wild", "b", "c", "a", "scatter", "d"],
			["c", "a", "b", "d", "wild", "c", "a", "b", "scatter", "d"],
			["d", "b", "a", "c", "wild", "d", "b", "a", "scatter", "c"],
			["a", "c", "d", "b", "wild", "a", "c", "d", "scatter", "b"],
		],
		"paylines": [[1, 1, 1, 1, 1], [0, 0, 0, 0, 0], [2, 2, 2, 2, 2]],
		"paytable": {
			"a": [0, 0, 1, 2, 5],
			"b": [0, 0, 1, 3, 8],
			"c": [0, 0, 2, 4, 10],
			"d": [0, 0, 2, 5, 12],
		},
		"scatter_pays": {"scatter": {"3": 5, "4": 20}},
		"wild_ids": ["wild"],
		"scatter_ids": ["scatter"],
		"min_bet": 10,
		"max_bet": 1000,
		"bet_step": 10,
	})


func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _run(test: Callable) -> void:
	_current = test.get_method()
	test.call()


func _true(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL [%s] %s" % [_current, message])


func _eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL [%s] %s: expected %s, got %s" % [_current, message, str(expected), str(actual)])
