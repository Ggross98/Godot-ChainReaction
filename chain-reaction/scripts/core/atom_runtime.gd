class_name AtomRuntime
extends RefCounted

var id: int = 0
var x: int = 0
var y: int = 0
var type: String = "normal"
var group: int = 0
var collapsed: bool = false
var parked: Array = []
var current_layer: int = -1
var catch_window_end: float = -1.0


func parked_count() -> int:
	var n := 0
	for layer in parked:
		n += layer.size()
	return n
