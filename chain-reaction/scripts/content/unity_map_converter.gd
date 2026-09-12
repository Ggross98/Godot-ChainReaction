class_name UnityMapConverter
extends SceneTree

const _HexGrid := preload("res://scripts/core/hex_grid.gd")
const _MapSchema := preload("res://scripts/core/map_schema.gd")

const CAMPAIGN_SRC := "res://tools/unity_import/Maps.json"
const CUSTOM_SRC := "res://tools/unity_import/CustomMaps.json"
const CAMPAIGN_OUT := "res://data/maps/campaign.json"
const CUSTOM_OUT := "res://data/maps/custom.json"
const REPORT_OUT := "res://data/maps/CONVERSION.md"


func _init() -> void:
	var code := run_cli()
	quit(code)


static func convert_map(unity_map: Dictionary) -> Dictionary:
	return convert_map_detailed(unity_map).map


static func convert_map_detailed(unity_map: Dictionary) -> Dictionary:
	var notes := PackedStringArray()
	var map := {}
	var name := str(unity_map.get("name", "Map"))
	map["id"] = _id_from_name(name)
	map["name"] = name
	map["width"] = _as_int(unity_map.get("width", 1), 1)
	map["height"] = _as_int(unity_map.get("height", 1), 1)
	map["steps"] = _as_int(unity_map.get("steps", 1), 1)

	var width: int = map["width"]
	var height: int = map["height"]
	var atoms: Array = []
	var occupied := {}
	var raw_atoms: Variant = unity_map.get("atoms", [])
	if typeof(raw_atoms) != TYPE_ARRAY:
		raw_atoms = []
	for ua in raw_atoms:
		if typeof(ua) != TYPE_DICTIONARY:
			notes.append("%s: skipped non-object atom" % map["id"])
			continue
		var atom := _convert_atom(ua)
		if atom.is_empty():
			notes.append("%s: skipped atom with invalid type or directions" % map["id"])
			continue
		var x: int = atom["x"]
		var y: int = atom["y"]
		if not _HexGrid.is_in_map(width, height, x, y):
			notes.append("%s: dropped out-of-bounds atom (%d,%d)" % [map["id"], x, y])
			continue
		var key := "%d,%d" % [x, y]
		if occupied.has(key):
			notes.append("%s: duplicate cell (%d,%d), last write wins" % [map["id"], x, y])
			atoms[occupied[key]] = atom
		else:
			occupied[key] = atoms.size()
			atoms.append(atom)
	map["atoms"] = atoms
	return {"map": map, "notes": notes}


static func convert_pack(unity_root: Dictionary, pack_id: String) -> Dictionary:
	var notes := PackedStringArray()
	var maps: Array = []
	var raw_maps: Variant = unity_root.get("maps", [])
	if typeof(raw_maps) != TYPE_ARRAY:
		return {
			"pack": {"schema_version": _MapSchema.SCHEMA_VERSION, "id": pack_id, "maps": []},
			"notes": PackedStringArray(["%s: missing maps array" % pack_id]),
		}
	for um in raw_maps:
		if typeof(um) != TYPE_DICTIONARY:
			notes.append("%s: skipped non-object map" % pack_id)
			continue
		var detailed := convert_map_detailed(um)
		maps.append(detailed.map)
		for line in detailed.notes:
			notes.append(line)
	return {
		"pack": {
			"schema_version": _MapSchema.SCHEMA_VERSION,
			"id": pack_id,
			"maps": maps,
		},
		"notes": notes,
	}


static func run_cli() -> int:
	var campaign_src := _read_json(CAMPAIGN_SRC)
	var custom_src := _read_json(CUSTOM_SRC)
	if campaign_src.is_empty() or custom_src.is_empty():
		push_error("Unity import JSON missing or invalid")
		return 1
	var campaign := convert_pack(campaign_src, "campaign")
	var custom := convert_pack(custom_src, "custom")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/maps"))
	if not _write_json(CAMPAIGN_OUT, campaign.pack):
		return 1
	if not _write_json(CUSTOM_OUT, custom.pack):
		return 1
	if not _write_text(REPORT_OUT, _render_report(campaign.notes, custom.notes)):
		return 1
	print("Converted campaign maps: %d" % campaign.pack.maps.size())
	print("Converted custom maps: %d" % custom.pack.maps.size())
	for line in campaign.notes:
		print("  ", line)
	for line in custom.notes:
		print("  ", line)
	return 0


static func _convert_atom(unity_atom: Dictionary) -> Dictionary:
	var type_id := _MapSchema.legacy_type_to_id(_as_int(unity_atom.get("type", 0), 0))
	if type_id == "":
		return {}
	var atom := {
		"x": _as_int(unity_atom.get("x", 0), 0),
		"y": _as_int(unity_atom.get("y", 0), 0),
		"type": type_id,
	}
	if _MapSchema.is_entangled_type(type_id):
		atom["group"] = _as_int(unity_atom.get("group", 0), 0)
		if atom["group"] < 1:
			return {}
	var orbits: Array = []
	var neutrons: Variant = unity_atom.get("neutrons", null)
	if typeof(neutrons) == TYPE_ARRAY:
		for layer_raw in neutrons:
			var layer: Array = []
			for ch in str(layer_raw):
				if not ch.is_valid_int():
					return {}
				var dir_id := _MapSchema.legacy_dir_to_id(int(ch))
				if dir_id == "":
					return {}
				layer.append(dir_id)
			orbits.append(layer)
	if orbits.is_empty():
		if not _MapSchema.is_catching_type(type_id):
			return {}
	else:
		if orbits.size() > 2:
			return {}
		atom["orbits"] = orbits
	return atom


static func _id_from_name(name: String) -> String:
	var re := RegEx.new()
	re.compile("^(X-\\d+|\\d+-\\d+)\\b")
	var matched := re.search(name)
	if matched != null:
		return matched.get_string()
	return name.strip_edges().to_lower().replace(" ", "-")


static func _as_int(v: Variant, fallback: int) -> int:
	match typeof(v):
		TYPE_INT:
			return v
		TYPE_FLOAT:
			return int(roundf(v))
		TYPE_STRING:
			if String(v).is_valid_int():
				return int(v)
	return fallback


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("missing %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("invalid JSON %s" % path)
		return {}
	return parsed


static func _write_json(path: String, data: Dictionary) -> bool:
	return _write_text(path, JSON.stringify(data, "\t") + "\n")


static func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % path)
		return false
	file.store_string(text)
	return true


static func _render_report(campaign_notes: PackedStringArray, custom_notes: PackedStringArray) -> String:
	var lines := PackedStringArray()
	lines.append("# Unity map conversion")
	lines.append("")
	lines.append("Generated from `tools/unity_import/`. Out-of-bounds atoms are dropped. Duplicate cells keep the last write.")
	lines.append("")
	lines.append("## campaign")
	lines.append("")
	if campaign_notes.is_empty():
		lines.append("- (no exceptions)")
	else:
		for note in campaign_notes:
			lines.append("- %s" % note)
	lines.append("")
	lines.append("## custom")
	lines.append("")
	if custom_notes.is_empty():
		lines.append("- (no exceptions)")
	else:
		for note in custom_notes:
			lines.append("- %s" % note)
	lines.append("")
	return "\n".join(lines)
