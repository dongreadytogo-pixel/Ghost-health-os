class_name NetTransport
extends RefCounted
## Abstract message transport.
##
## `NetSync` talks only to this interface, never to a concrete socket. The
## shipping default is `LoopbackTransport` (in-process, used for tests and a
## future split-screen/host-and-play mode); an ENet, WebSocket or relay
## transport can be dropped in later with zero changes above this line. That is
## the seam that lets multiplayer be *added*, not retrofitted.

## Emitted when a message arrives from a peer.
signal message_received(message: NetMessage)


## Send a message to peers. Returns OK or an error code.
func send(_message: NetMessage) -> Error:
	push_error("NetTransport.send not implemented")
	return ERR_UNAVAILABLE


## Pump the transport (poll sockets, flush queues). Called each frame by NetSync.
func poll() -> void:
	pass


func is_connected_to_peers() -> bool:
	return false


func close() -> void:
	pass
