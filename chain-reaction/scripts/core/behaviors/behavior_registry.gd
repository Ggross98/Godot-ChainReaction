class_name BehaviorRegistry
extends RefCounted

const _Normal := preload("res://scripts/core/behaviors/normal_behavior.gd")
const _Movable := preload("res://scripts/core/behaviors/movable_behavior.gd")
const _Catching := preload("res://scripts/core/behaviors/catching_behavior.gd")
const _CatchingMovable := preload("res://scripts/core/behaviors/catching_movable_behavior.gd")
const _Entangled := preload("res://scripts/core/behaviors/entangled_behavior.gd")
const _EntangledMovable := preload("res://scripts/core/behaviors/entangled_movable_behavior.gd")

static var _instances: Dictionary = {}


static func of(type: String):
	if _instances.is_empty():
		_instances = {
			"normal": _Normal.new(),
			"movable": _Movable.new(),
			"catching": _Catching.new(),
			"catching_movable": _CatchingMovable.new(),
			"entangled": _Entangled.new(),
			"entangled_movable": _EntangledMovable.new(),
		}
	return _instances.get(type, _Normal.new())
