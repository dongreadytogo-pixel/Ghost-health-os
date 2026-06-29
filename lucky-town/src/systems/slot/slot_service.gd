class_name SlotService
extends RefCounted
## Player-facing slot orchestration.
##
## Wraps the pure `SlotEvaluator` with the side effects a real spin needs:
## validating and taking the bet through the `Economy`, feeding the progressive
## jackpot, crediting winnings, updating the gambler's memory, and broadcasting
## the result on the `EventBus` for the UI to animate. Keeping this out of the UI
## means the player and AI gamble through the exact same rules — the foundation
## of a fair, auditable economy.

const SlotEvaluatorRef := preload("res://src/domain/slot/slot_evaluator.gd")


## Result of an attempted spin from the caller's point of view.
class SpinOutcome extends RefCounted:
	var ok: bool = false
	var reason: String = ""
	var result: SlotSpinResult = null


## Spin `machine_id` for `player_id` at `bet`. Returns a SpinOutcome; on failure
## `ok` is false and nothing is charged.
static func spin(machine_id: String, player_id: String, bet: int) -> SpinOutcome:
	var outcome := SpinOutcome.new()
	var config := DataRegistry.slot_config(machine_id)
	if config == null:
		outcome.reason = "unknown_machine"
		return outcome

	bet = config.clamp_bet(bet)
	if not Economy.can_afford(player_id, bet):
		outcome.reason = "insufficient_funds"
		return outcome

	Economy.debit(player_id, bet, "slot_bet:%s" % machine_id)
	Economy.contribute_jackpot(machine_id, int(round(float(bet) * config.jackpot_contribution)))

	var rng := RngService.stream("slot:%s" % machine_id)
	var result := SlotEvaluatorRef.spin(config, rng, bet, Economy.jackpot(machine_id))

	if result.total_payout > 0:
		Economy.credit(player_id, result.total_payout, "slot_win:%s" % machine_id)
	if result.jackpot_won:
		result.jackpot_amount = Economy.claim_jackpot(machine_id, player_id)

	var player := GameState.get_citizen(player_id)
	if player:
		player.record_slot_result(result.net(), machine_id)

	outcome.ok = true
	outcome.result = result
	EventBus.slot_spun.emit(machine_id, player_id, result.to_dict())
	return outcome
