extends "res://scripts/core/behaviors/atom_behavior.gd"


func press_action() -> String:
	return "drag"


func can_catch() -> bool:
	return true


func type_after_catch() -> String:
	return "movable"
