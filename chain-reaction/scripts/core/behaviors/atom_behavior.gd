class_name AtomBehavior
extends RefCounted


func press_action() -> String:
	return "ignore"


func can_drag() -> bool:
	return press_action() == "drag"


func can_catch() -> bool:
	return false


func is_entangled() -> bool:
	return false


func type_after_catch() -> String:
	return ""
