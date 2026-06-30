class_name NetMessage
extends RefCounted
## A single network envelope: a typed event plus its payload.
##
## The whole game already speaks in `EventBus` facts that carry only plain data,
## so mirroring the game over a wire is just (de)serialising those facts. A
## message records *what* happened (`type`, matching an EventBus signal name),
## the data, who originated it (`origin` peer id) and a monotonically increasing
## `seq` for ordering/dedup. Keeping this a tiny, engine-agnostic value object
## means any transport (loopback, ENet, WebSocket, a REST relay) can carry it.

var type: String = ""
var payload: Dictionary = {}
var origin: String = ""
var seq: int = 0


func _init(type: String = "", payload: Dictionary = {}, origin: String = "", seq: int = 0) -> void:
	self.type = type
	self.payload = payload
	self.origin = origin
	self.seq = seq


func to_dict() -> Dictionary:
	return {"type": type, "payload": payload, "origin": origin, "seq": seq}


static func from_dict(data: Dictionary) -> NetMessage:
	return NetMessage.new(
		data.get("type", ""),
		data.get("payload", {}),
		data.get("origin", ""),
		int(data.get("seq", 0)))


## Wire form. JSON keeps the protocol debuggable and transport-agnostic; a binary
## codec can replace this later without touching call sites.
func encode() -> String:
	return JSON.stringify(to_dict())


static func decode(text: String) -> NetMessage:
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return NetMessage.from_dict(parsed)
	return null
