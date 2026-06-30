class_name LoopbackTransport
extends NetTransport
## In-process transport: messages "sent" are queued and delivered back on the
## next `poll()`.
##
## This is the offline-safe default. On its own it lets a single client mirror
## its own events through the full NetSync path (invaluable for tests and for a
## host-and-play mode where the host *is* a peer). Swapping in a real socket
## transport later changes nothing in `NetSync`.

var _inbox: Array = []          # Array[NetMessage]
var _loopback_self: bool = false  # echo our own sends back (off by default)


func set_loopback_self(enabled: bool) -> void:
	_loopback_self = enabled


func send(message: NetMessage) -> Error:
	if _loopback_self:
		_inbox.append(message)
	return OK


## Inject a message as if it came from a peer (used by tests and by a host
## feeding remote-player input into the simulation).
func inject(message: NetMessage) -> void:
	_inbox.append(message)


func poll() -> void:
	if _inbox.is_empty():
		return
	var pending := _inbox
	_inbox = []
	for message in pending:
		message_received.emit(message)


func is_connected_to_peers() -> bool:
	return true
