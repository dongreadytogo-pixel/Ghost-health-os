extends Control
## Title screen: New Game, Continue (auto-save), Quit.
##
## The menu only decides *which* game to enter; world construction lives in the
## world scene. "Continue" is enabled only when an auto-save exists.

const WORLD_SCENE := "res://scenes/world/world.tscn"

@onready var _continue_button: Button = $Center/VBox/ContinueButton


func _ready() -> void:
	_continue_button.disabled = not SaveManager.has_slot(SaveManager.AUTOSAVE_SLOT)


func _on_new_game_pressed() -> void:
	GameState.new_game()
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_continue_pressed() -> void:
	if SaveManager.load_from_slot(SaveManager.AUTOSAVE_SLOT):
		get_tree().change_scene_to_file(WORLD_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
