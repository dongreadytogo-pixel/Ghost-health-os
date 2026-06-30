extends CanvasLayer
## In-game pause menu with full multi-slot save/load (toggle with Esc).
##
## Delivers the design's "manual save / multiple save slots / load" via one
## screen: a row per slot showing its headline metadata (read cheaply from the
## save's `.meta` sidecar — no full deserialise), with Save and Load actions,
## plus an auto-save row. Loading rebuilds the world scene so the visible city
## matches the freshly-loaded model.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"

@onready var _root: Control = $Root
@onready var _slot_list: VBoxContainer = $Root/Panel/Margin/VBox/Scroll/SlotList
@onready var _info_label: Label = $Root/Panel/Margin/VBox/InfoLabel
@onready var _resume_button: Button = $Root/Panel/Margin/VBox/Buttons/ResumeButton
@onready var _menu_button: Button = $Root/Panel/Margin/VBox/Buttons/MenuButton
@onready var _quit_button: Button = $Root/Panel/Margin/VBox/Buttons/QuitButton


func _ready() -> void:
	_root.hide()
	_resume_button.pressed.connect(_close)
	_menu_button.pressed.connect(_on_main_menu)
	_quit_button.pressed.connect(func(): get_tree().quit())
	EventBus.game_saved.connect(_on_saved)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_menu"):
		toggle()


func toggle() -> void:
	if _root.visible:
		_close()
	else:
		_open()


func _open() -> void:
	_root.show()
	GameClock.set_paused(true)
	EventBus.ui_modal_changed.emit(true)
	_refresh()


func _close() -> void:
	_root.hide()
	GameClock.set_paused(false)
	EventBus.ui_modal_changed.emit(false)


func _on_saved(_slot: int) -> void:
	if _root.visible:
		_refresh()


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	_info_label.text = ""
	for child in _slot_list.get_children():
		child.queue_free()
	var metas := SaveManager.list_slots()
	_add_slot_row(SaveManager.AUTOSAVE_SLOT, "Auto-save", metas.get(SaveManager.AUTOSAVE_SLOT, {}), false)
	for slot in range(1, SaveManager.MAX_MANUAL_SLOTS + 1):
		_add_slot_row(slot, "Slot %d" % slot, metas.get(slot, {}), true)


func _add_slot_row(slot: int, label_text: String, meta: Dictionary, can_save: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if meta.is_empty():
		info.text = "%s — (empty)" % label_text
	else:
		info.text = "%s — Day %d, $%s  [%s]" % [
			label_text, int(meta.get("day", 0)),
			Money.of(int(meta.get("net_worth", 0))).format_short(),
			meta.get("saved_at", ""),
		]
	row.add_child(info)

	if can_save:
		var save_btn := Button.new()
		save_btn.text = "Save"
		save_btn.pressed.connect(func(): _on_save(slot))
		row.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.disabled = meta.is_empty()
	load_btn.pressed.connect(func(): _on_load(slot))
	row.add_child(load_btn)

	_slot_list.add_child(row)


# --- Actions -----------------------------------------------------------------

func _on_save(slot: int) -> void:
	if SaveManager.save_to_slot(slot):
		_info_label.text = "Saved to slot %d." % slot


func _on_load(slot: int) -> void:
	if not SaveManager.load_from_slot(slot):
		_info_label.text = "Could not load slot %d." % slot
		return
	# Rebuild the world so visible avatars/props match the loaded model.
	GameClock.set_paused(false)
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_main_menu() -> void:
	GameClock.set_paused(false)
	get_tree().change_scene_to_file(MENU_SCENE)
