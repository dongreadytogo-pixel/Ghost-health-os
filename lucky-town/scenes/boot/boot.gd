extends Node
## Entry point. Waits for data to finish loading, then routes to the main menu.
##
## Keeping boot trivial (and separate from the menu) means engine warm-up,
## future splash screens and migration checks all have one obvious home.

const MAIN_MENU := "res://scenes/menu/main_menu.tscn"


func _ready() -> void:
	if DataRegistry.is_loaded():
		_go_to_menu()
	else:
		DataRegistry.data_loaded.connect(_go_to_menu, CONNECT_ONE_SHOT)


func _go_to_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
