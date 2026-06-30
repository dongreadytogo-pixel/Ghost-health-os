extends Node
## The networking seam — dormant until switched on.
##
## This is the concrete proof of the project's core promise: online play can be
## *added* without rewriting gameplay. The whole game already communicates in
## plain-data facts on the `EventBus`; `NetSync` simply mirrors a curated set of
## those facts onto a `NetTransport` and re-emits inbound ones locally.
##
## CRUCIAL: while `enabled` is false (the default) this node connects nothing,
## polls nothing and allocates nothing per frame — the offline game is byte-for-
## byte unaffected. Flipping `enable()` is purely additive.
##
## Today it relays events (the foundation for spectator views, telemetry and a
## host-and-play loopback). Turning the relay into authoritative state sync means
## adding apply-handlers that mutate `Economy`/`GameState` from inbound messages;
## because all state already funnels through those two singletons, that work is
## localised — no gameplay system needs to change shape. See docs/NETWORKING.md.

signal peer_event_applied(type: String, payload: Dictionary)

var enabled: bool = false
var peer_id: String = "local"
var transport: NetTransport

var _seq: int = 0
var _applying: bool = false
var _connected_signals: Array = []

# Curated authoritative facts to mirror, grouped by argument count.
const _ARITY1 := ["transaction_recorded", "auction_listed", "auction_expired", "day_started", "weather_changed"]
const _ARITY2 := ["pet_acquired", "building_constructed", "citizen_action_finished", "world_event_started"]
const _ARITY3 := ["money_changed", "slot_spun", "slot_jackpot_won", "property_purchased",
	"property_sold", "pet_bred", "pet_sold", "auction_bid", "auction_sold"]


func _ready() -> void:
	set_process(false)  # nothing to pump until enabled


## Turn networking on with a transport and our peer identity. Idempotent.
func enable(net_transport: NetTransport, local_peer_id: String = "local") -> void:
	if enabled:
		return
	transport = net_transport
	peer_id = local_peer_id
	transport.message_received.connect(_on_message_received)
	_connect_outbound()
	set_process(true)
	enabled = true
	Log.info("Net", "NetSync enabled as peer '%s'" % peer_id)


func disable() -> void:
	if not enabled:
		return
	_disconnect_outbound()
	if transport:
		if transport.message_received.is_connected(_on_message_received):
			transport.message_received.disconnect(_on_message_received)
		transport.close()
	set_process(false)
	enabled = false


func _process(_delta: float) -> void:
	if transport:
		transport.poll()


# --- Outbound mirroring ------------------------------------------------------

func _connect_outbound() -> void:
	for sig in _ARITY1:
		_connect(sig, _forward1.bind(sig))
	for sig in _ARITY2:
		_connect(sig, _forward2.bind(sig))
	for sig in _ARITY3:
		_connect(sig, _forward3.bind(sig))


func _connect(signal_name: String, callable: Callable) -> void:
	EventBus.connect(signal_name, callable)
	_connected_signals.append({"signal": signal_name, "callable": callable})


func _disconnect_outbound() -> void:
	for entry in _connected_signals:
		if EventBus.is_connected(entry["signal"], entry["callable"]):
			EventBus.disconnect(entry["signal"], entry["callable"])
	_connected_signals.clear()


func _forward1(a, signal_name: String) -> void:
	_send(signal_name, [a])


func _forward2(a, b, signal_name: String) -> void:
	_send(signal_name, [a, b])


func _forward3(a, b, c, signal_name: String) -> void:
	_send(signal_name, [a, b, c])


func _send(type: String, args: Array) -> void:
	# Never re-broadcast something we are in the middle of applying from a peer.
	if _applying or transport == null:
		return
	_seq += 1
	transport.send(NetMessage.new(type, {"args": args}, peer_id, _seq))


# --- Inbound application -----------------------------------------------------

func _on_message_received(message: NetMessage) -> void:
	if message == null or message.origin == peer_id:
		return  # ignore our own echo
	_apply(message)


func _apply(message: NetMessage) -> void:
	var args: Array = message.payload.get("args", [])
	_applying = true
	match args.size():
		0: EventBus.emit_signal(message.type)
		1: EventBus.emit_signal(message.type, args[0])
		2: EventBus.emit_signal(message.type, args[0], args[1])
		3: EventBus.emit_signal(message.type, args[0], args[1], args[2])
	_applying = false
	peer_event_applied.emit(message.type, message.payload)
