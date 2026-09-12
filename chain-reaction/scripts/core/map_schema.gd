class_name MapSchema
extends RefCounted

const SCHEMA_VERSION := 1

const TYPE_NORMAL := "normal"
const TYPE_MOVABLE := "movable"
const TYPE_CATCHING := "catching"
const TYPE_CATCHING_MOVABLE := "catching_movable"
const TYPE_ENTANGLED := "entangled"
const TYPE_ENTANGLED_MOVABLE := "entangled_movable"

const TYPES: PackedStringArray = [
	TYPE_NORMAL,
	TYPE_MOVABLE,
	TYPE_CATCHING,
	TYPE_CATCHING_MOVABLE,
	TYPE_ENTANGLED,
	TYPE_ENTANGLED_MOVABLE,
]

const DIR_W := "W"
const DIR_NW := "NW"
const DIR_NE := "NE"
const DIR_E := "E"
const DIR_SE := "SE"
const DIR_SW := "SW"

const DIRECTIONS: PackedStringArray = [
	DIR_W, DIR_NW, DIR_NE, DIR_E, DIR_SE, DIR_SW,
]


static func is_valid_type(id: String) -> bool:
	return TYPES.has(id)


static func is_valid_direction(id: String) -> bool:
	return DIRECTIONS.has(id)


static func is_catching_type(id: String) -> bool:
	return id == TYPE_CATCHING or id == TYPE_CATCHING_MOVABLE


static func is_entangled_type(id: String) -> bool:
	return id == TYPE_ENTANGLED or id == TYPE_ENTANGLED_MOVABLE


static func legacy_type_to_id(legacy: int) -> String:
	if legacy < 0 or legacy >= TYPES.size():
		return ""
	return TYPES[legacy]


static func legacy_dir_to_id(legacy: int) -> String:
	if legacy < 0 or legacy >= DIRECTIONS.size():
		return ""
	return DIRECTIONS[legacy]
