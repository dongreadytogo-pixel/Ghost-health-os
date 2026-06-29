class_name AiDecision
extends RefCounted
## The output of `AiBrain.decide`: a chosen action plus parameters and the
## utility score it won with (kept for debugging and on-screen "thought" UI).

var action: String = "idle"
var params: Dictionary = {}
var score: float = 0.0


func _init(action: String = "idle", params: Dictionary = {}, score: float = 0.0) -> void:
	self.action = action
	self.params = params
	self.score = score


func _to_string() -> String:
	return "AiDecision(%s, %.2f, %s)" % [action, score, str(params)]
