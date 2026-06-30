extends Node
## Earned cosmetic titles (the "Titles" slice of player customization).
##
## Titles are data (`data/titles/*.json`): a label, a tier, and the achievement
## that unlocks them. The player automatically wears the highest-tier title they
## have earned; it shows on the HUD and could later gate emotes/flair. Selection
## is automatic for now (no UI churn), but `select()` is here for a future
## title picker — the data and unlock rules already support it.
##
## Stateless: the chosen title lives on the player `Citizen` (and is saved with
## it); this autoload only derives availability from `AchievementSystem`.


func _ready() -> void:
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)


func _on_achievement_unlocked(_id: String, _title: String) -> void:
	refresh_player_title()


## Titles the player has unlocked, as an array of def dicts (incl. defaults).
func available_titles() -> Array:
	var out: Array = []
	for id in DataRegistry.ids("titles"):
		var def := DataRegistry.get_def("titles", id)
		var unlock := String(def.get("unlock", "default"))
		if unlock == "default" or AchievementSystem.is_unlocked(unlock):
			out.append(def)
	return out


func label_for(title_id: String) -> String:
	var def := DataRegistry.get_def("titles", title_id)
	return def.get("label", title_id)


## Equip a specific title if the player has unlocked it.
func select(title_id: String) -> bool:
	var player := GameState.player()
	if player == null:
		return false
	for def in available_titles():
		if def.get("id", "") == title_id:
			player.title = title_id
			EventBus.title_changed.emit(label_for(title_id))
			return true
	return false


## Auto-equip the best (highest-tier) unlocked title.
func refresh_player_title() -> void:
	var player := GameState.player()
	if player == null:
		return
	var best_id := player.title
	var best_tier := -1
	for def in available_titles():
		var tier := int(def.get("tier", 0))
		if tier > best_tier:
			best_tier = tier
			best_id = def.get("id", best_id)
	if best_id != player.title:
		player.title = best_id
		EventBus.title_changed.emit(label_for(best_id))
