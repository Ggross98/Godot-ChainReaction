class_name MapPack
extends RefCounted

const _MapSchema := preload("res://scripts/core/map_schema.gd")

var schema_version: int = _MapSchema.SCHEMA_VERSION
var id: String = ""
var maps: Array = []


func map_by_id(map_id: String):
	for m in maps:
		if m.id == map_id:
			return m
	return null


class MapData:
	extends RefCounted
	var id: String = ""
	var name: String = ""
	var width: int = 1
	var height: int = 1
	var steps: int = 1
	var atoms: Array = []


class AtomData:
	extends RefCounted
	var x: int = 0
	var y: int = 0
	var type: String = "normal"
	var group: int = 0
	var orbits: Array = []


	func neutron_count() -> int:
		var n := 0
		for layer in orbits:
			n += layer.size()
		return n
