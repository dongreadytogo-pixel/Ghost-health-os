class_name Interactable
extends Area3D
## Base class for anything the player can walk up to and activate.
##
## A building front, a slot machine, an auction kiosk — all extend this. The
## `Interactable` only manages proximity detection and dispatch; subclasses
## override `interact()` and `prompt_text()` to define behaviour. This is the
## single, uniform contract the `PlayerController` talks to, so new interactive
## content slots into the world without touching the player.

## Shown in the on-screen prompt, e.g. "Play Slots".
@export var prompt: String = "Interact"


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func prompt_text() -> String:
	return prompt


## Override in subclasses. `actor` is the player controller.
func interact(_actor: Node) -> void:
	pass


func _on_body_entered(body: Node) -> void:
	if body.has_method("set_nearby_interactable"):
		body.set_nearby_interactable(self)


func _on_body_exited(body: Node) -> void:
	if body.has_method("clear_nearby_interactable"):
		body.clear_nearby_interactable(self)
