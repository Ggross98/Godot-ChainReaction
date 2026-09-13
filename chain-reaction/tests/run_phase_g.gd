extends SceneTree

const _MapLoader := preload("res://scripts/content/map_loader.gd")
const _MapPack := preload("res://scripts/core/map_data.gd")
const _GameSession := preload("res://scripts/app/game_session.gd")
const _GameLaunch := preload("res://scripts/app/game_launch.gd")

const RELAY_PATH := "res://data/maps/custom/level_relay-race.json"
const TEST_DIR := "user://phase_g_custom"
const ROUNDTRIP_PATH := "user://phase_g_roundtrip.json"

var _failures: int = 0
var _loader := _MapLoader.new()


func _init() -> void:
	print("=== Phase G tests ===")
	_cleanup()
	_test_map_roundtrip()
	_test_upsert_custom_map()
	_test_illegal_cell_rejected()
	_test_duplicate_cell_rejected()
	_test_start_map_does_not_persist()
	_test_dev_scenes()
	_test_player_shell_has_no_editor()
	_cleanup()
	print("=== %d failure(s) ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)


func _cleanup() -> void:
	_remove_file(ROUNDTRIP_PATH)
	_remove_dir(TEST_DIR)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name != "." and name != "..":
				if dir.current_is_dir():
					_remove_dir("%s/%s" % [path, name])
				else:
					dir.remove(name)
			name = dir.get_next()
		dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _load_relay():
	var result = _loader.load_map_file(RELAY_PATH)
	_check(result.ok, "relay-race loads")
	return result.map


func _maps_match(a, b) -> bool:
	if a == null or b == null:
		return false
	if a.id != b.id or a.name != b.name:
		return false
	if a.width != b.width or a.height != b.height or a.steps != b.steps:
		return false
	if a.atoms.size() != b.atoms.size():
		return false
	for i in range(a.atoms.size()):
		if _atom_key(a.atoms[i]) != _atom_key(b.atoms[i]):
			return false
	return true


func _atom_key(atom) -> String:
	var layers: PackedStringArray = PackedStringArray()
	for layer in atom.orbits:
		var dirs: PackedStringArray = PackedStringArray()
		for dir_id in layer:
			dirs.append(str(dir_id))
		layers.append(",".join(dirs))
	return "%d,%d,%s,%d,%s" % [atom.x, atom.y, atom.type, atom.group, "|".join(layers)]


func _test_map_roundtrip() -> void:
	print("-- load_map_file / save_map_file roundtrip")
	var original = _load_relay()
	if original == null:
		return
	_check(_loader.save_map_file(ROUNDTRIP_PATH, original), "wrote roundtrip JSON")
	var again = _loader.load_map_file(ROUNDTRIP_PATH)
	_check(again.ok, "roundtrip JSON loads")
	_check(_maps_match(original, again.map), "roundtrip fields match relay-race")
	var dict: Dictionary = _loader.map_to_dict(original)
	_check(dict.get("id", "") == "relay-race", "map_to_dict keeps id")
	_check(dict.get("width", 0) == original.width, "map_to_dict keeps width")
	_check(dict.get("atoms", []).size() == original.atoms.size(), "map_to_dict keeps atoms")


func _test_upsert_custom_map() -> void:
	print("-- upsert_custom_map into user://")
	var map = _load_relay()
	if map == null:
		return
	map.id = "phase-g-tmp"
	map.name = "Phase G Tmp"
	var result = _loader.upsert_custom_map(map, TEST_DIR)
	_check(result.ok, "upsert new custom map")
	var map_path := "%s/%s" % [TEST_DIR, _MapLoader.level_file_name("phase-g-tmp")]
	_check(FileAccess.file_exists(map_path), "wrote level_phase-g-tmp.json")
	var ids: PackedStringArray = _loader.list_custom_ids(TEST_DIR)
	_check(ids.has("phase-g-tmp"), "pack.json lists new id")
	var pack_result = _loader.load_pack_file(TEST_DIR)
	_check(pack_result.ok, "load_pack_file reads user:// custom dir")
	_check(pack_result.pack != null and pack_result.pack.map_by_id("phase-g-tmp") != null, "pack contains phase-g-tmp")
	_check(not FileAccess.file_exists("res://data/maps/custom/level_phase-g-tmp.json"), "did not pollute res custom dir")


func _test_illegal_cell_rejected() -> void:
	print("-- illegal cell save rejected")
	var map = _load_relay()
	if map == null:
		return
	map.id = "phase-g-oob"
	map.name = "OOB"
	map.atoms[0].x = 99
	map.atoms[0].y = 99
	var result = _loader.upsert_custom_map(map, TEST_DIR)
	_check(not result.ok, "oob upsert fails")
	_check(result.errors.size() > 0, "oob upsert reports errors")
	var map_path := "%s/%s" % [TEST_DIR, _MapLoader.level_file_name("phase-g-oob")]
	_check(not FileAccess.file_exists(map_path), "oob map file not written")
	var ids: PackedStringArray = _loader.list_custom_ids(TEST_DIR)
	_check(not ids.has("phase-g-oob"), "oob id not appended to pack.json")


func _test_duplicate_cell_rejected() -> void:
	print("-- duplicate cell save rejected")
	var map = _load_relay()
	if map == null:
		return
	map.id = "phase-g-dup"
	map.name = "Dup"
	var copy := _MapPack.AtomData.new()
	copy.x = map.atoms[0].x
	copy.y = map.atoms[0].y
	copy.type = "catching"
	map.atoms.append(copy)
	var result = _loader.upsert_custom_map(map, TEST_DIR)
	_check(not result.ok, "duplicate-cell upsert fails")
	var map_path := "%s/%s" % [TEST_DIR, _MapLoader.level_file_name("phase-g-dup")]
	_check(not FileAccess.file_exists(map_path), "duplicate map file not written")


func _test_start_map_does_not_persist() -> void:
	print("-- start_map should_persist")
	var map = _load_relay()
	if map == null:
		return
	var session := _GameSession.new()
	_check(session.start_map(map), "start_map accepts MapData")
	_check(session.current_map != null, "start_map sets current_map")
	_check(session.pack_path() != _GameLaunch.CAMPAIGN, "draft pack is not campaign")
	_check(not session.should_persist(), "start_map should_persist is false")


func _test_dev_scenes() -> void:
	print("-- editor/tester scenes")
	var editor_ps = load("res://scenes/level_editor.tscn")
	_check(editor_ps != null, "level_editor.tscn loads")
	var editor = editor_ps.instantiate()
	_check(editor != null and editor.get_script() != null, "level_editor script attached")
	_check(editor.has_node("Board"), "level_editor has Board")
	_check(editor.has_node("CanvasLayer/HUD/SidePanel"), "level_editor has side panel")
	editor.free()
	var tester_ps = load("res://scenes/level_tester.tscn")
	_check(tester_ps != null, "level_tester.tscn loads")
	var tester = tester_ps.instantiate()
	_check(tester != null and tester.get_script() != null, "level_tester script attached")
	_check(tester.has_node("CanvasLayer/HUD/Buttons/Restart"), "level_tester has Restart")
	_check(str(tester.get("level_json")) == "", "level_tester JSON starts empty")
	tester.free()


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _test_player_shell_has_no_editor() -> void:
	print("-- player shell has no editor entry")
	var menu := _read("res://scripts/main_menu.gd")
	_check(menu != "", "main_menu.gd readable")
	_check(not menu.contains("level_editor"), "main_menu.gd has no level_editor")
	_check(not menu.contains("level_tester"), "main_menu.gd has no level_tester")
	var menu_scene := _read("res://scenes/main_menu.tscn")
	_check(not menu_scene.contains("level_editor"), "main_menu.tscn has no level_editor")
	_check(not menu_scene.contains("level_tester"), "main_menu.tscn has no level_tester")
	var tester := _read("res://scripts/dev/level_tester.gd")
	_check(tester.contains("@export_file"), "level_tester.gd exports JSON path")
	_check(not tester.contains("SaveAccount"), "level_tester.gd does not write save")
	_check(not tester.contains("Prev"), "level_tester.gd has no Prev")
	_check(not tester.contains("Next"), "level_tester.gd has no Next")
	var project := _read("res://project.godot")
	_check(project.contains("run/main_scene=\"uid://v1fjjg7kupvx\""), "run/main_scene stays main menu")
	_check(not project.contains("level_editor.tscn"), "project.godot does not launch editor")
	var presets := _read("res://export_presets.cfg")
	_check(presets.contains("scenes/level_editor.tscn"), "export excludes level_editor.tscn")
	_check(presets.contains("scenes/level_tester.tscn"), "export excludes level_tester.tscn")
	_check(presets.contains("scripts/dev/*"), "export excludes scripts/dev/*")
