class_name MapLoader
extends RefCounted

const _HexGrid := preload("res://scripts/core/hex_grid.gd")
const _MapSchema := preload("res://scripts/core/map_schema.gd")
const _MapPack := preload("res://scripts/core/map_data.gd")

const _PACK_KEYS: PackedStringArray = ["schema_version", "id", "maps"]
const _MAP_KEYS: PackedStringArray = ["id", "name", "width", "height", "steps", "atoms"]
const _ATOM_KEYS: PackedStringArray = ["x", "y", "type", "group", "orbits"]


class MapLoadResult:
	extends RefCounted
	var ok: bool = false
	var pack: _MapPack
	var map
	var errors: PackedStringArray = PackedStringArray()
	var warnings: PackedStringArray = PackedStringArray()


static func level_file_name(map_id: String) -> String:
	return "level_%s.json" % map_id


func load_pack_file(path: String) -> MapLoadResult:
	var cleaned := path.rstrip("/\\")
	if cleaned.get_file() == "pack.json":
		return load_pack_dir(cleaned.get_base_dir())
	var dir := DirAccess.open(cleaned)
	if dir != null:
		return load_pack_dir(cleaned)
	return _load_pack_json_file(cleaned)


func load_pack_dir(dir_path: String) -> MapLoadResult:
	var result := MapLoadResult.new()
	var cleaned := dir_path.rstrip("/\\")
	var index_path := "%s/pack.json" % cleaned
	if not FileAccess.file_exists(index_path):
		result.errors.append("file not found: %s" % index_path)
		return result
	var parsed := _read_json_object(index_path, result)
	if parsed.is_empty() and not result.errors.is_empty():
		return result
	_warn_unknown_keys(result, parsed, _PACK_KEYS, "pack")
	if not parsed.has("schema_version"):
		result.errors.append("schema_version is missing")
	else:
		var version = _try_int(parsed["schema_version"])
		if version == null:
			result.errors.append("schema_version must be an integer")
		elif int(version) != _MapSchema.SCHEMA_VERSION:
			result.errors.append("unsupported schema_version %s (expected %d)" % [str(version), _MapSchema.SCHEMA_VERSION])
	var pack_id := ""
	if not parsed.has("id") or str(parsed["id"]).strip_edges() == "":
		result.errors.append("pack id is missing")
	else:
		pack_id = str(parsed["id"])
	if not parsed.has("maps") or typeof(parsed["maps"]) != TYPE_ARRAY:
		result.errors.append("maps must be an array")
		return _finalize(result, null)
	var pack := _MapPack.new()
	pack.schema_version = _MapSchema.SCHEMA_VERSION
	pack.id = pack_id
	var seen_ids := {}
	var maps: Array = parsed["maps"]
	for i in maps.size():
		var raw_id: Variant = maps[i]
		if typeof(raw_id) != TYPE_STRING or str(raw_id).strip_edges() == "":
			result.errors.append("maps[%d] must be a map id string" % i)
			continue
		var map_id := str(raw_id)
		if seen_ids.has(map_id):
			result.errors.append("duplicate map id '%s'" % map_id)
			continue
		seen_ids[map_id] = true
		var map_path := "%s/%s" % [cleaned, level_file_name(map_id)]
		if not FileAccess.file_exists(map_path):
			result.errors.append("missing %s" % map_path)
			continue
		var map_raw := _read_json_object(map_path, result)
		if map_raw.is_empty():
			continue
		var map_obj = _load_map(result, map_raw, i)
		if map_obj == null:
			continue
		if map_obj.id != map_id:
			result.errors.append("%s id is '%s' (expected '%s')" % [level_file_name(map_id), map_obj.id, map_id])
			continue
		pack.maps.append(map_obj)
	return _finalize(result, pack)


func _load_pack_json_file(path: String) -> MapLoadResult:
	var result := MapLoadResult.new()
	if not FileAccess.file_exists(path):
		result.errors.append("file not found: %s" % path)
		return result
	var parsed := _read_json_object(path, result)
	if parsed.is_empty() and not result.errors.is_empty():
		return result
	return load_pack(parsed)


func _read_json_object(path: String, result: MapLoadResult) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.errors.append("cannot open: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		result.errors.append("root is not an object: %s" % path)
		return {}
	return parsed


func load_map_file(path: String) -> MapLoadResult:
	var result := MapLoadResult.new()
	if not FileAccess.file_exists(path):
		result.errors.append("file not found: %s" % path)
		return result
	var parsed := _read_json_object(path, result)
	if parsed.is_empty() and not result.errors.is_empty():
		return result
	var map_obj = _load_map(result, parsed, 0)
	if map_obj == null:
		return _finalize(result, null)
	result.map = map_obj
	var pack := _MapPack.new()
	pack.schema_version = _MapSchema.SCHEMA_VERSION
	pack.id = "single"
	pack.maps.append(map_obj)
	return _finalize(result, pack)


func map_to_dict(map) -> Dictionary:
	var atoms: Array = []
	if map != null:
		for atom in map.atoms:
			atoms.append(_atom_to_dict(atom))
	return {
		"id": str(map.id) if map else "",
		"name": str(map.name) if map else "",
		"width": int(map.width) if map else 1,
		"height": int(map.height) if map else 1,
		"steps": int(map.steps) if map else 1,
		"atoms": atoms,
	}


func save_map_file(path: String, map) -> bool:
	return _write_json(path, map_to_dict(map))


func validate_map(map) -> MapLoadResult:
	var result := MapLoadResult.new()
	if map == null:
		result.errors.append("map is missing")
		return result
	var reloaded = _load_map(result, map_to_dict(map), 0)
	if reloaded == null:
		return _finalize(result, null)
	result.map = reloaded
	var pack := _MapPack.new()
	pack.schema_version = _MapSchema.SCHEMA_VERSION
	pack.id = "single"
	pack.maps.append(reloaded)
	return _finalize(result, pack)


func upsert_custom_map(map, pack_dir: String = "res://data/maps/custom") -> MapLoadResult:
	var result := validate_map(map)
	if not result.ok:
		return result
	var dir := pack_dir.rstrip("/\\")
	var abs_dir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var map_path := "%s/%s" % [dir, level_file_name(result.map.id)]
	if not save_map_file(map_path, result.map):
		var fail := MapLoadResult.new()
		fail.errors.append("cannot write %s" % map_path)
		return fail
	var index_path := "%s/pack.json" % dir
	var pack_id := "custom"
	var schema_version: int = _MapSchema.SCHEMA_VERSION
	var ids: Array = []
	if FileAccess.file_exists(index_path):
		var index_result := MapLoadResult.new()
		var raw := _read_json_object(index_path, index_result)
		if raw.has("id") and str(raw["id"]).strip_edges() != "":
			pack_id = str(raw["id"])
		var version = _try_int(raw.get("schema_version", schema_version))
		if version != null:
			schema_version = int(version)
		if raw.has("maps") and typeof(raw["maps"]) == TYPE_ARRAY:
			for item in raw["maps"]:
				ids.append(str(item))
	if not ids.has(result.map.id):
		ids.append(result.map.id)
	if not _write_json(index_path, {
		"schema_version": schema_version,
		"id": pack_id,
		"maps": ids,
	}):
		var fail := MapLoadResult.new()
		fail.errors.append("cannot write %s" % index_path)
		return fail
	return result


func list_custom_ids(pack_dir: String = "res://data/maps/custom") -> PackedStringArray:
	var ids := PackedStringArray()
	var index_path := "%s/pack.json" % pack_dir.rstrip("/\\")
	if not FileAccess.file_exists(index_path):
		return ids
	var index_result := MapLoadResult.new()
	var raw := _read_json_object(index_path, index_result)
	if not raw.has("maps") or typeof(raw["maps"]) != TYPE_ARRAY:
		return ids
	for item in raw["maps"]:
		var map_id := str(item).strip_edges()
		if map_id != "":
			ids.append(map_id)
	return ids


func load_pack(data: Variant) -> MapLoadResult:
	var result := MapLoadResult.new()
	if typeof(data) != TYPE_DICTIONARY:
		result.errors.append("pack root is not an object")
		return result
	var root: Dictionary = data
	_warn_unknown_keys(result, root, _PACK_KEYS, "pack")

	if not root.has("schema_version"):
		result.errors.append("schema_version is missing")
	else:
		var version = _try_int(root["schema_version"])
		if version == null:
			result.errors.append("schema_version must be an integer")
		elif int(version) != _MapSchema.SCHEMA_VERSION:
			result.errors.append("unsupported schema_version %s (expected %d)" % [str(version), _MapSchema.SCHEMA_VERSION])

	var pack_id := ""
	if not root.has("id") or str(root["id"]).strip_edges() == "":
		result.errors.append("pack id is missing")
	else:
		pack_id = str(root["id"])

	if not root.has("maps") or typeof(root["maps"]) != TYPE_ARRAY:
		result.errors.append("maps must be an array")
		return _finalize(result, null)

	var pack := _MapPack.new()
	pack.schema_version = _MapSchema.SCHEMA_VERSION
	pack.id = pack_id
	var seen_ids := {}
	var maps: Array = root["maps"]
	for i in maps.size():
		var map_obj = _load_map(result, maps[i], i)
		if map_obj == null:
			continue
		if seen_ids.has(map_obj.id):
			result.errors.append("duplicate map id '%s'" % map_obj.id)
			continue
		seen_ids[map_obj.id] = true
		pack.maps.append(map_obj)

	return _finalize(result, pack)


func _finalize(result: MapLoadResult, pack: _MapPack) -> MapLoadResult:
	if result.errors.is_empty() and pack != null:
		result.ok = true
		result.pack = pack
	else:
		result.ok = false
		result.pack = null
	return result


func _load_map(result: MapLoadResult, raw: Variant, index: int) -> _MapPack.MapData:
	var prefix := "maps[%d]" % index
	if typeof(raw) != TYPE_DICTIONARY:
		result.errors.append("%s is not an object" % prefix)
		return null
	var data: Dictionary = raw
	_warn_unknown_keys(result, data, _MAP_KEYS, prefix)

	var map := _MapPack.MapData.new()
	if not data.has("id") or str(data["id"]).strip_edges() == "":
		result.errors.append("%s.id is missing" % prefix)
	else:
		map.id = str(data["id"])
		prefix = "map '%s'" % map.id

	if not data.has("name") or str(data["name"]).strip_edges() == "":
		result.errors.append("%s.name is missing" % prefix)
	else:
		map.name = str(data["name"])

	var width = _try_positive_int(data.get("width", null))
	var height = _try_positive_int(data.get("height", null))
	var steps = _try_positive_int(data.get("steps", null))
	if width == null:
		result.errors.append("%s.width must be a positive integer" % prefix)
	else:
		map.width = int(width)
	if height == null:
		result.errors.append("%s.height must be a positive integer" % prefix)
	else:
		map.height = int(height)
	if steps == null:
		result.errors.append("%s.steps must be a positive integer" % prefix)
	else:
		map.steps = int(steps)

	if not data.has("atoms") or typeof(data["atoms"]) != TYPE_ARRAY:
		result.errors.append("%s.atoms must be an array" % prefix)
		return map

	if width == null or height == null:
		return map

	var occupied := {}
	var atoms: Array = data["atoms"]
	for j in atoms.size():
		var atom := _load_atom(result, atoms[j], "%s.atoms[%d]" % [prefix, j], map.width, map.height)
		if atom == null:
			continue
		var key := "%d,%d" % [atom.x, atom.y]
		if occupied.has(key):
			result.errors.append("%s has two atoms at (%d,%d)" % [prefix, atom.x, atom.y])
			continue
		occupied[key] = true
		map.atoms.append(atom)
	return map


func _load_atom(result: MapLoadResult, raw: Variant, prefix: String, width: int, height: int) -> _MapPack.AtomData:
	if typeof(raw) != TYPE_DICTIONARY:
		result.errors.append("%s is not an object" % prefix)
		return null
	var data: Dictionary = raw
	_warn_unknown_keys(result, data, _ATOM_KEYS, prefix)

	var atom := _MapPack.AtomData.new()
	var x = _try_int(data.get("x", null))
	var y = _try_int(data.get("y", null))
	if x == null or y == null:
		result.errors.append("%s.x and y must be integers" % prefix)
		return null
	atom.x = int(x)
	atom.y = int(y)
	if not _HexGrid.is_in_map(width, height, atom.x, atom.y):
		result.errors.append("%s cell (%d,%d) is outside the board" % [prefix, atom.x, atom.y])
		return null

	if not data.has("type") or typeof(data["type"]) != TYPE_STRING:
		result.errors.append("%s.type is missing" % prefix)
		return null
	atom.type = data["type"]
	if not _MapSchema.is_valid_type(atom.type):
		result.errors.append("%s has unknown type '%s'" % [prefix, atom.type])
		return null

	if _MapSchema.is_entangled_type(atom.type):
		var group = _try_positive_int(data.get("group", null))
		if group == null:
			result.errors.append("%s is entangled and needs a positive group" % prefix)
			return null
		atom.group = int(group)
	elif data.has("group"):
		result.warnings.append("%s is not entangled; ignoring group" % prefix)

	if data.has("orbits"):
		if typeof(data["orbits"]) != TYPE_ARRAY:
			result.errors.append("%s.orbits must be an array" % prefix)
			return null
		var orbits: Array = data["orbits"]
		if orbits.size() > 2:
			result.errors.append("%s.orbits has more than 2 layers" % prefix)
			return null
		for layer_i in orbits.size():
			var layer_raw = orbits[layer_i]
			if typeof(layer_raw) != TYPE_ARRAY:
				result.errors.append("%s.orbits[%d] must be an array of directions" % [prefix, layer_i])
				return null
			var layer: PackedStringArray = PackedStringArray()
			for dir_raw in layer_raw:
				var dir := str(dir_raw)
				if not _MapSchema.is_valid_direction(dir):
					result.errors.append("%s.orbits[%d] has invalid direction '%s'" % [prefix, layer_i, dir])
					return null
				layer.append(dir)
			atom.orbits.append(layer)
	elif not _MapSchema.is_catching_type(atom.type):
		result.errors.append("%s has no neutrons" % prefix)
		return null

	if not _MapSchema.is_catching_type(atom.type) and atom.neutron_count() == 0:
		result.errors.append("%s has no neutrons" % prefix)
		return null

	return atom


func _atom_to_dict(atom) -> Dictionary:
	var data := {
		"x": int(atom.x),
		"y": int(atom.y),
		"type": str(atom.type),
	}
	if _MapSchema.is_entangled_type(str(atom.type)) and int(atom.group) > 0:
		data["group"] = int(atom.group)
	var layers: Array = []
	for layer in atom.orbits:
		var dirs: Array = []
		for dir_id in layer:
			dirs.append(str(dir_id))
		layers.append(dirs)
	while layers.size() > 0 and layers[layers.size() - 1].is_empty():
		layers.pop_back()
	if not layers.is_empty():
		data["orbits"] = layers
	return data


func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t") + "\n")
	return true


func _warn_unknown_keys(result: MapLoadResult, data: Dictionary, known: PackedStringArray, prefix: String) -> void:
	for key in data.keys():
		if not known.has(str(key)):
			result.warnings.append("%s has unknown field '%s'" % [prefix, str(key)])


func _try_int(v: Variant) -> Variant:
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			if is_equal_approx(v, roundf(v)):
				return int(roundf(v))
		TYPE_STRING:
			if String(v).is_valid_int():
				return int(v)
	return null


func _try_positive_int(v: Variant) -> Variant:
	var n = _try_int(v)
	if n == null or int(n) < 1:
		return null
	return n
