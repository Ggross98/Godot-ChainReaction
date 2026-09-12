extends SceneTree

const _HexGrid := preload("res://scripts/core/hex_grid.gd")
const _MapLoader := preload("res://scripts/content/map_loader.gd")
const _Simulation := preload("res://scripts/core/simulation.gd")
const _SimConstants := preload("res://scripts/core/sim_constants.gd")
const _GameSession := preload("res://scripts/app/game_session.gd")
const _GameLaunch := preload("res://scripts/app/game_launch.gd")
const _BehaviorRegistry := preload("res://scripts/core/behaviors/behavior_registry.gd")
const _SaveAccount := preload("res://scripts/app/save_account.gd")

var _failures: int = 0


func _init() -> void:
	_SaveAccount.path = "user://phase_d_test.cfg"
	_SaveAccount.reset_memory()
	print("=== Phase D tests ===")
	_test_game_launch_defaults()
	_test_campaign_wrap()
	_test_custom_wrap()
	_test_load_all_maps()
	_test_one_five_smoke()
	_test_relay_race_smoke()
	print("=== %d failure(s) ===" % _failures)
	_cleanup_test_save()
	quit(1 if _failures > 0 else 0)


func _cleanup_test_save() -> void:
	if FileAccess.file_exists(_SaveAccount.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_SaveAccount.path))
	_SaveAccount.path = _SaveAccount.DEFAULT_PATH
	_SaveAccount.reset_memory()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)


func _expected_campaign_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for chapter in ["1", "2", "3", "4", "X"]:
		for n in range(1, 9):
			ids.append("%s-%d" % [chapter, n])
	return ids


func _test_game_launch_defaults() -> void:
	print("-- GameLaunch")
	_check(_GameLaunch.CAMPAIGN == "res://data/maps/campaign", "campaign path")
	_check(_GameLaunch.CUSTOM == "res://data/maps/custom", "custom path")


func _test_campaign_wrap() -> void:
	print("-- campaign nav bounds")
	_SaveAccount.reset_memory()
	var session = _GameSession.new()
	_check(session.start_pack(_GameLaunch.CAMPAIGN, "1-1"), "loads 1-1")
	_check(not session.can_goto_prev(), "first map has no prev")
	session.goto_prev()
	_check(session.map_id() == "1-1", "prev on first stays")
	_check(session.can_goto_next(), "1-2 is unlocked")
	session.goto_next()
	_check(session.map_id() == "1-2", "next to 1-2")
	_check(session.can_goto_prev(), "1-2 can go prev")
	_check(session.start_pack(_GameLaunch.CAMPAIGN, "1-3"), "loads 1-3")
	_check(not session.can_goto_next(), "locked 1-4 blocks next")
	session.goto_next()
	_check(session.map_id() == "1-3", "stays when next is locked")
	_check(session.start_pack(_GameLaunch.CAMPAIGN, "X-8"), "loads X-8")
	_check(not session.can_goto_next(), "last map has no next")
	session.goto_next()
	_check(session.map_id() == "X-8", "next on last stays")


func _test_custom_wrap() -> void:
	print("-- custom nav bounds")
	var session = _GameSession.new()
	_check(session.start_pack(_GameLaunch.CUSTOM, "relay-race"), "loads relay-race")
	_check(not session.can_goto_prev(), "first custom has no prev")
	session.goto_prev()
	_check(session.map_id() == "relay-race", "custom prev on first stays")
	_check(session.can_goto_next(), "second custom is playable")
	_check(session.start_pack(_GameLaunch.CUSTOM, "one-stroke"), "loads one-stroke")
	_check(session.hud_progress() == "2 / 2", "progress 2 / 2")
	_check(not session.can_goto_next(), "last custom has no next")
	session.goto_next()
	_check(session.map_id() == "one-stroke", "custom next on last stays")
	_check(session.can_goto_prev(), "last custom can go prev")


func _test_load_all_maps() -> void:
	print("-- load all maps")
	_check_pack(_GameLaunch.CAMPAIGN, 40, _expected_campaign_ids())
	_check_pack(_GameLaunch.CUSTOM, 2, PackedStringArray(["relay-race", "one-stroke"]))
	_check(FileAccess.file_exists("res://data/maps/campaign/level_1-1.json"), "campaign level_1-1.json")
	_check(FileAccess.file_exists("res://data/maps/custom/level_relay-race.json"), "custom level_relay-race.json")


func _check_pack(path: String, expected_count: int, expected_ids: PackedStringArray) -> void:
	var loader := _MapLoader.new()
	var result = loader.load_pack_file(path)
	_check(result.ok, "%s loads" % path)
	_check(result.errors.is_empty(), "%s has no errors" % path)
	if result.pack == null:
		_check(false, "%s pack missing" % path)
		return
	_check(result.pack.maps.size() == expected_count, "%s has %d maps" % [path, expected_count])
	var actual := PackedStringArray()
	for m in result.pack.maps:
		actual.append(m.id)
	_check(actual == expected_ids, "%s map order" % path)
	var inner := _WALL_INNER()
	for m in result.pack.maps:
		_check_map(m, inner)


func _WALL_INNER() -> Rect2:
	var r: float = _SimConstants.NUCLEI_RADIUS
	var mn: Vector2 = _SimConstants.WALL_MIN + Vector2(r, r)
	var mx: Vector2 = _SimConstants.WALL_MAX - Vector2(r, r)
	return Rect2(mn, mx - mn)


func _check_map(m, inner: Rect2) -> void:
	var sim = _Simulation.new()
	sim.setup(m)
	var problems: PackedStringArray = PackedStringArray()
	if sim.width != m.width or sim.height != m.height or sim.steps != m.steps:
		problems.append("setup mismatch")
	if sim.state != "waiting":
		problems.append("not waiting after setup")
	var cells := {}
	for atom in m.atoms:
		var key := "%d,%d" % [atom.x, atom.y]
		if cells.has(key):
			problems.append("duplicate %s" % key)
		cells[key] = true
		if not _HexGrid.is_in_map(m.width, m.height, atom.x, atom.y):
			problems.append("oob %s" % key)
		var world: Vector2 = _HexGrid.cell_to_world(m.width, m.height, atom.x, atom.y)
		if not inner.has_point(world):
			problems.append("wall %s at %s" % [key, str(world)])
	sim.tick(1.0 / 60.0)
	if sim.state != "waiting":
		problems.append("not waiting after tick")
	_check(problems.is_empty(), "%s loads (%s)" % [m.id, ",".join(problems) if not problems.is_empty() else "ok"])


func _test_one_five_smoke() -> void:
	print("-- 1-5 smoke")
	var result = _MapLoader.new().load_pack_file(_GameLaunch.CAMPAIGN)
	if not result.ok:
		_check(false, "campaign load")
		return
	var m = result.pack.map_by_id("1-5")
	_check(m != null, "1-5 exists")
	if m == null:
		return
	var sim = _Simulation.new()
	sim.setup(m)
	var pressed := false
	for atom in sim.atoms:
		if atom.collapsed:
			continue
		if _BehaviorRegistry.of(atom.type).press_action() == "release":
			pressed = sim.press_cell(atom.x, atom.y)
			break
	_check(pressed, "1-5 pressed a releasable atom")
	sim.run_until_idle()
	_check(sim.state == "waiting" or sim.state == "win" or sim.state == "lose", "1-5 idle after press")


func _test_relay_race_smoke() -> void:
	print("-- relay-race smoke")
	var session = _GameSession.new()
	_check(session.start_pack(_GameLaunch.CUSTOM, "relay-race"), "loads relay-race")
	var catching := 0
	var movable := 0
	for atom in session.sim.atoms:
		if atom.type == "catching":
			catching += 1
		if _BehaviorRegistry.of(atom.type).can_drag():
			movable += 1
	_check(catching == 1, "relay-race has catching")
	_check(movable >= 1, "relay-race has movable")
	var dragged := false
	for atom in session.sim.atoms:
		if _BehaviorRegistry.of(atom.type).can_drag():
			var world: Vector2 = _HexGrid.cell_to_world(session.sim.width, session.sim.height, atom.x, atom.y)
			dragged = session.pointer_press(world)
			if dragged:
				session.pointer_release(world)
			break
	_check(dragged, "can drag a movable")
	_check(session.sim.width == 5, "relay-race width 5")
	_check(session.sim.height == 4, "relay-race height 4")
	_check(session.sim.steps == 2, "relay-race steps 2")
	_check(session.sim.atoms.size() == 9, "relay-race has 9 atoms")
	var cells := {}
	for atom in session.sim.atoms:
		cells["%d,%d" % [atom.x, atom.y]] = true
		_check(_HexGrid.is_in_map(session.sim.width, session.sim.height, atom.x, atom.y), "relay-race (%d,%d) in map" % [atom.x, atom.y])
	for key in ["0,1", "3,0", "3,2", "3,1", "1,0", "1,1", "1,2", "2,0", "2,3"]:
		_check(cells.has(key), "relay-race has cell %s" % key)
