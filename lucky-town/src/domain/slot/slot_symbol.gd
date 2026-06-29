class_name SlotSymbol
extends Resource
## A single symbol that can appear on a slot reel.
##
## Symbols are data: designers create one `.tres` per symbol (or define them in
## a theme JSON) and reference them from reel strips. Keeping them as Resources
## lets the editor preview icons and lets tooling validate paytables.

## Stable identifier used in paytables and save data. Never localise this.
@export var id: StringName = &""

## Player-facing name (localisation key or literal).
@export var display_name: String = ""

## Icon shown on the reel. Optional during early development.
@export var icon: Texture2D

## Higher tiers are rarer and pay more; used for sorting and UI emphasis.
@export var tier: int = 0

## Special behaviours. A symbol may have several (e.g. wild + scatter).
@export var is_wild: bool = false
@export var is_scatter: bool = false


func _to_string() -> String:
	return "SlotSymbol(%s)" % id
