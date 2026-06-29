extends Interactable
## A slot machine the player can walk up to and play.
##
## Bridges the physical world (an object in the 3D city) to the slot UI. The
## machine knows only *which* data-driven config it represents; the actual maths
## and money live in `SlotService`. Opening the UI is requested via the
## `EventBus` so the HUD/UI layer owns presentation.

## Which machine in the `slot_machines` registry this object plays.
@export var machine_id: String = "slot_fantasy"


func prompt_text() -> String:
	var def := DataRegistry.get_def("slot_machines", machine_id)
	return "Play %s" % def.get("display_name", "Slots")


func interact(_actor: Node) -> void:
	# The UI layer (world scene) owns presentation and player input-locking; we
	# only announce intent with the machine id.
	EventBus.slot_ui_requested.emit(machine_id)
