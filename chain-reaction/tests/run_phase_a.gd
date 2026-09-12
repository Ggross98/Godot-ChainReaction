extends SceneTree

const HexGrid := preload("res://scripts/core/hex_grid.gd")
const MapSchema := preload("res://scripts/core/map_schema.gd")
const MapLoader := preload("res://scripts/content/map_loader.gd")
const UnityMapConverter := preload("res://scripts/content/unity_map_converter.gd")

var _failures: int = 0


func _init() -> void:
	print("=== Phase A tests ===")
	_test_hex_grid()
	_test_map_schema()
	_test_map_loader_valid_pack()
	_test_map_loader_unknown_type()
	_test_map_loader_duplicate_cell()
	_test_map_loader_out_of_bounds()
	_test_map_loader_entangled_without_group()
	_test_map_loader_empty_normal()
	_test_converter_legacy_atom()
	_test_generated_packs()
	print("=== %d failure(s) ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)


func _test_hex_grid() -> void:
	print("-- HexGrid.is_in_map")
	_check(HexGrid.is_in_map(4, 3, 3, 0), "even row x=width-1 is in map")
	_check(not HexGrid.is_in_map(4, 3, 4, 0), "even row x=width is out")
	_check(HexGrid.is_in_map(4, 3, 2, 1), "odd row x=width-2 is in map")
	_check(not HexGrid.is_in_map(4, 3, 3, 1), "odd row x=width-1 is out")
	_check(not HexGrid.is_in_map(5, 3, 2, 3), "y=height is out")
	_check(not HexGrid.is_in_map(4, 3, -1, 0), "negative x is out")


func _test_map_schema() -> void:
	print("-- MapSchema legacy maps")
	_check(MapSchema.legacy_type_to_id(0) == "normal", "type 0 -> normal")
	_check(MapSchema.legacy_type_to_id(1) == "movable", "type 1 -> movable")
	_check(MapSchema.legacy_type_to_id(2) == "catching", "type 2 -> catching")
	_check(MapSchema.legacy_type_to_id(3) == "catching_movable", "type 3 -> catching_movable")
	_check(MapSchema.legacy_type_to_id(4) == "entangled", "type 4 -> entangled")
	_check(MapSchema.legacy_type_to_id(5) == "entangled_movable", "type 5 -> entangled_movable")
	_check(MapSchema.legacy_dir_to_id(0) == "W", "dir 0 -> W")
	_check(MapSchema.legacy_dir_to_id(1) == "NW", "dir 1 -> NW")
	_check(MapSchema.legacy_dir_to_id(2) == "NE", "dir 2 -> NE")
	_check(MapSchema.legacy_dir_to_id(3) == "E", "dir 3 -> E")
	_check(MapSchema.legacy_dir_to_id(4) == "SE", "dir 4 -> SE")
	_check(MapSchema.legacy_dir_to_id(5) == "SW", "dir 5 -> SW")


func _loader() -> MapLoader:
	return MapLoader.new()


func _parse(text: String) -> Dictionary:
	return JSON.parse_string(text)


func _test_map_loader_valid_pack() -> void:
	print("-- MapLoader valid mini pack")
	var data := _parse("""
	{
	  "schema_version": 1,
	  "id": "campaign",
	  "maps": [{
	    "id": "1-1",
	    "name": "1-1 Click to Release",
	    "width": 4,
	    "height": 3,
	    "steps": 1,
	    "atoms": [
	      {"x": 1, "y": 1, "type": "normal", "orbits": [["W", "NW", "NE", "E", "SE", "SW"]]},
	      {"x": 0, "y": 2, "type": "catching"}
	    ]
	  }]
	}
	""")
	var result := _loader().load_pack(data)
	_check(result.ok, "valid pack loads")
	_check(result.errors.is_empty(), "valid pack has no errors")
	_check(result.pack != null and result.pack.maps.size() == 1, "valid pack has 1 map")
	if result.pack != null and result.pack.maps.size() == 1:
		_check(result.pack.maps[0].atoms.size() == 2, "valid pack has 2 atoms")


func _test_map_loader_unknown_type() -> void:
	print("-- MapLoader unknown type")
	var data := {
		"schema_version": 1,
		"id": "t",
		"maps": [{
			"id": "m",
			"name": "m",
			"width": 1,
			"height": 1,
			"steps": 1,
			"atoms": [{"x": 0, "y": 0, "type": "portal", "orbits": [["E"]]}],
		}],
	}
	var result := _loader().load_pack(data)
	_check(not result.ok, "unknown type is not ok")
	_check(result.errors.size() >= 1, "unknown type has an error")


func _test_map_loader_duplicate_cell() -> void:
	print("-- MapLoader duplicate cell")
	var data := {
		"schema_version": 1,
		"id": "t",
		"maps": [{
			"id": "m",
			"name": "m",
			"width": 2,
			"height": 1,
			"steps": 1,
			"atoms": [
				{"x": 0, "y": 0, "type": "normal", "orbits": [["E"]]},
				{"x": 0, "y": 0, "type": "normal", "orbits": [["W"]]},
			],
		}],
	}
	var result := _loader().load_pack(data)
	_check(not result.ok, "duplicate cell is not ok")
	_check(result.errors.size() >= 1, "duplicate cell has an error")


func _test_map_loader_out_of_bounds() -> void:
	print("-- MapLoader out of bounds")
	var data := {
		"schema_version": 1,
		"id": "t",
		"maps": [{
			"id": "m",
			"name": "m",
			"width": 5,
			"height": 3,
			"steps": 1,
			"atoms": [{"x": 2, "y": 3, "type": "movable", "orbits": [["E"]]}],
		}],
	}
	var result := _loader().load_pack(data)
	_check(not result.ok, "out-of-bounds atom is not ok")
	_check(result.errors.size() >= 1, "out-of-bounds has an error")


func _test_map_loader_entangled_without_group() -> void:
	print("-- MapLoader entangled without group")
	var data := {
		"schema_version": 1,
		"id": "t",
		"maps": [{
			"id": "m",
			"name": "m",
			"width": 1,
			"height": 1,
			"steps": 1,
			"atoms": [{"x": 0, "y": 0, "type": "entangled", "orbits": [["E"]]}],
		}],
	}
	var result := _loader().load_pack(data)
	_check(not result.ok, "entangled without group is not ok")
	_check(result.errors.size() >= 1, "entangled without group has an error")


func _test_map_loader_empty_normal() -> void:
	print("-- MapLoader empty normal")
	var data := {
		"schema_version": 1,
		"id": "t",
		"maps": [{
			"id": "m",
			"name": "m",
			"width": 1,
			"height": 1,
			"steps": 1,
			"atoms": [{"x": 0, "y": 0, "type": "normal"}],
		}],
	}
	var result := _loader().load_pack(data)
	_check(not result.ok, "empty normal is not ok")
	_check(result.errors.size() >= 1, "empty normal has an error")


func _test_converter_legacy_atom() -> void:
	print("-- UnityMapConverter legacy atom")
	var unity_map := {
		"name": "4-1 Quantum Entanglement",
		"width": 3,
		"height": 3,
		"steps": 1,
		"atoms": [
			{"x": 0, "y": 0, "type": 4, "group": 1, "neutrons": ["3", "1"]},
		],
	}
	var converted: Dictionary = UnityMapConverter.convert_map(unity_map)
	_check(converted.get("id", "") == "4-1", "map id from name prefix")
	var atoms: Array = converted.get("atoms", [])
	_check(atoms.size() == 1, "converted one atom")
	if atoms.size() == 1:
		var atom: Dictionary = atoms[0]
		_check(atom.get("type", "") == "entangled", "legacy type 4 -> entangled")
		_check(int(atom.get("group", 0)) == 1, "group kept")
		_check(atom.get("orbits", []) == [["E"], ["NW"]], "neutrons 3,1 -> E then NW")


func _expected_campaign_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for chapter in ["1", "2", "3", "4", "X"]:
		for n in range(1, 9):
			ids.append("%s-%d" % [chapter, n])
	return ids


func _test_generated_packs() -> void:
	print("-- generated packs")
	var loader := _loader()
	var campaign := loader.load_pack_file("res://data/maps/campaign")
	_check(campaign.ok, "campaign pack loads")
	_check(campaign.errors.is_empty(), "campaign pack has no errors")
	_check(FileAccess.file_exists("res://data/maps/campaign/level_1-1.json"), "level_1-1.json exists")
	_check(FileAccess.file_exists("res://data/maps/campaign/pack.json"), "campaign pack.json exists")
	if campaign.pack == null:
		_check(false, "campaign pack is missing")
		return
	_check(campaign.pack.maps.size() == 40, "campaign has 40 maps (got %d)" % campaign.pack.maps.size())
	var expected := _expected_campaign_ids()
	var actual := PackedStringArray()
	for m in campaign.pack.maps:
		actual.append(m.id)
	_check(actual == expected, "campaign map order is 1-1..X-8")
	for m in campaign.pack.maps:
		if m.id == "1-5":
			var cells := {}
			var dup := false
			for atom in m.atoms:
				var key := "%d,%d" % [atom.x, atom.y]
				if cells.has(key):
					dup = true
				cells[key] = true
			_check(not dup, "1-5 has no duplicate cells")

	var custom := loader.load_pack_file("res://data/maps/custom")
	_check(custom.ok, "custom pack loads")
	_check(custom.errors.is_empty(), "custom pack has no errors")
	_check(FileAccess.file_exists("res://data/maps/custom/level_relay-race.json"), "level_relay-race.json exists")
	if custom.pack == null:
		_check(false, "custom pack is missing")
		return
	_check(custom.pack.maps.size() == 2, "custom has 2 maps")
	if custom.pack.maps.size() >= 1:
		_check(custom.pack.maps[0].id == "relay-race", "first custom id is relay-race")
		for atom in custom.pack.maps[0].atoms:
			_check(HexGrid.is_in_map(custom.pack.maps[0].width, custom.pack.maps[0].height, atom.x, atom.y), "relay-race atom (%d,%d) in map" % [atom.x, atom.y])
	if custom.pack.maps.size() >= 2:
		_check(custom.pack.maps[1].id == "one-stroke", "second custom id is one-stroke")
