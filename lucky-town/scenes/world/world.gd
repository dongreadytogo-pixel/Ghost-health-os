extends Node3D
## The playable city: spawns the world from the loaded `GameState`.
##
## Responsibilities: place visible citizen avatars for a slice of the
## population, place slot machines and building fronts from the data, host the
## HUD, and bridge interactable requests (e.g. "open slot UI") to the UI layer.
## It reads the model; it never owns gameplay rules.

const CitizenAgentScene := preload("res://scenes/world/citizen_agent.tscn")
const SlotMachineScene := preload("res://scenes/world/slot_machine.tscn")
const SlotUiScene := preload("res://src/ui/slot/slot_ui.tscn")

## How many AI citizens are given a visible avatar (the rest are simulated only).
@export var visible_citizen_count: int = 8

@onready var _agents_root: Node3D = $Agents
@onready var _props_root: Node3D = $Props
@onready var _ui_root: CanvasLayer = $UiLayer

var _slot_ui: Control = null


func _ready() -> void:
	EventBus.slot_ui_requested.connect(_open_slot_ui)
	_spawn_slot_machines()
	_spawn_visible_citizens()
	GameClock.set_paused(false)


func _spawn_slot_machines() -> void:
	var ids := DataRegistry.ids("slot_machines")
	var angle_step := TAU / maxi(1, ids.size())
	for i in ids.size():
		var machine := SlotMachineScene.instantiate()
		machine.machine_id = ids[i]
		machine.position = Vector3(cos(angle_step * i), 0, sin(angle_step * i)) * 6.0
		_props_root.add_child(machine)


func _spawn_visible_citizens() -> void:
	var ai := GameState.ai_citizens()
	for i in mini(visible_citizen_count, ai.size()):
		var agent := CitizenAgentScene.instantiate()
		_agents_root.add_child(agent)
		agent.position = Vector3(randf_range(-8, 8), 1.0, randf_range(-8, 8))
		agent.bind(ai[i].id)


func _open_slot_ui(machine_id: String) -> void:
	if _slot_ui == null:
		_slot_ui = SlotUiScene.instantiate()
		_ui_root.add_child(_slot_ui)
		_slot_ui.closed.connect(func(): GameClock.set_paused(false))
	GameClock.set_paused(true)
	_slot_ui.open(machine_id)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		SaveManager.save_to_slot(1)
	elif event.is_action_pressed("toggle_menu"):
		get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
