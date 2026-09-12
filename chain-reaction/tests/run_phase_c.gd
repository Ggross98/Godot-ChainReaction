extends SceneTree

const _HexGrid := preload("res://scripts/core/hex_grid.gd")
const _MapLoader := preload("res://scripts/content/map_loader.gd")
const _Simulation := preload("res://scripts/core/simulation.gd")
const _ViewTransform := preload("res://scripts/view/view_transform.gd")
const _GameSession := preload("res://scripts/app/game_session.gd")
const _GameLaunch := preload("res://scripts/app/game_launch.gd")
const _HudStrings := preload("res://scripts/app/hud_strings.gd")
const _BoardView := preload("res://scripts/view/board_view.gd")
const _AtomView := preload("res://scripts/view/atom_view.gd")
const _SaveAccount := preload("res://scripts/app/save_account.gd")

var _failures: int = 0


func _init() -> void:
	_SaveAccount.path = "user://phase_c_test.cfg"
	_SaveAccount.reset_memory()
	print("=== Phase C tests ===")
	_test_view_transform_roundtrip()
	_test_cell_roundtrip_through_view()
	_test_map_by_id()
	_test_get_drag_atom()
	_test_session_press_1_1()
	_test_reacting_ignores_press_and_drag()
	_test_session_movable_snap()
	_test_win_delay_advances_to_next()
	_test_restart_cancels_delay()
	_test_session_catch_3_1()
	_test_session_entangle_4_1()
	_test_board_view_sync_smoke()
	_test_atom_view_nuclei_keeps_ppu_scale()
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


func _campaign() -> Object:
	var result = _MapLoader.new().load_pack_file(_GameLaunch.CAMPAIGN)
	if not result.ok:
		print("  FAIL campaign load: %s" % ",".join(result.errors))
		_failures += 1
		return null
	return result.pack


func _mini_map(width: int, height: int, steps: int, atoms: Array) -> Object:
	var pack := {
		"schema_version": 1,
		"id": "t",
		"maps": [{
			"id": "m",
			"name": "m",
			"width": width,
			"height": height,
			"steps": steps,
			"atoms": atoms,
		}],
	}
	var result = _MapLoader.new().load_pack(pack)
	if not result.ok:
		print("  FAIL map load: %s" % ",".join(result.errors))
		_failures += 1
		return null
	return result.pack.maps[0]


func _test_view_transform_roundtrip() -> void:
	print("-- ViewTransform")
	var p := Vector2(1.5, 2.25)
	var view: Vector2 = _ViewTransform.logic_to_view(p)
	_check(is_equal_approx(view.x, 1.5) and is_equal_approx(view.y, -2.25), "logic y up becomes view y down")
	var back: Vector2 = _ViewTransform.view_to_logic(view)
	_check(back.is_equal_approx(p), "view to logic roundtrip")
	var nw: Vector2 = _HexGrid.direction_vector("NW")
	var nw_view: Vector2 = _ViewTransform.logic_to_view(nw)
	_check(nw.y > 0.0 and nw_view.y < 0.0, "NW logic y>0 maps to view y<0")


func _test_cell_roundtrip_through_view() -> void:
	print("-- cell through view")
	for cell in [Vector2i(1, 0), Vector2i(1, 1)]:
		var world: Vector2 = _HexGrid.cell_to_world(4, 3, cell.x, cell.y)
		var view: Vector2 = _ViewTransform.logic_to_view(world)
		var logic: Vector2 = _ViewTransform.view_to_logic(view)
		var back: Vector2i = _HexGrid.world_to_cell(4, 3, logic)
		_check(back == cell, "cell %s survives view flip" % str(cell))


func _test_map_by_id() -> void:
	print("-- MapPack.map_by_id")
	var pack = _campaign()
	if pack == null:
		return
	var m = pack.map_by_id("1-1")
	_check(m != null and m.id == "1-1", "finds 1-1")
	_check(m != null and m.name == "1-1 Click to Release", "1-1 display name")
	_check(pack.map_by_id("no-such") == null, "missing id is null")


func _test_get_drag_atom() -> void:
	print("-- Simulation.get_drag_atom")
	var map = _mini_map(3, 1, 1, [
		{"x": 0, "y": 0, "type": "movable", "orbits": [["E"]]},
	])
	if map == null:
		return
	var sim = _Simulation.new()
	sim.setup(map)
	_check(sim.get_drag_atom() == null, "no drag yet")
	_check(sim.begin_drag_cell(0, 0), "begin drag")
	var dragged = sim.get_drag_atom()
	_check(dragged != null and dragged.x == 0 and dragged.y == 0, "drag atom exposed")
	sim.end_drag_cell(1, 0)
	_check(sim.get_drag_atom() == null, "drag atom cleared")


func _test_session_press_1_1() -> void:
	print("-- session press 1-1")
	var session = _GameSession.new()
	_check(session.start_pack(_GameLaunch.CAMPAIGN, "1-1"), "loads 1-1")
	_check(session.map_id() == "1-1", "current id is 1-1")
	_check(session.hud_title() == "1-1 Click to Release", "title from map name")
	_check(session.hud_steps() == _HudStrings.left_steps(1), "steps string")
	var world: Vector2 = _HexGrid.cell_to_world(4, 3, 1, 1)
	_check(session.pointer_press(world), "press on 1-1 nucleus")
	_check(session.sim.state == "reacting", "enters reacting")
	var guard := 0
	while session.sim.state == "reacting" and guard < 600:
		session.advance(1.0 / 60.0)
		guard += 1
	_check(session.sim.state == "win", "1-1 resolves to win")
	_check(session.hud_state() == _HudStrings.COMPLETED, "completed copy")


func _test_reacting_ignores_press_and_drag() -> void:
	print("-- reacting ignores input")
	var session = _GameSession.new()
	session.start_pack(_GameLaunch.CAMPAIGN, "1-1")
	var world: Vector2 = _HexGrid.cell_to_world(4, 3, 1, 1)
	session.pointer_press(world)
	_check(session.sim.state == "reacting", "now reacting")
	_check(not session.pointer_press(world), "press ignored while reacting")
	_check(not session.pointer_press(_HexGrid.cell_to_world(4, 3, 1, 0)), "other nucleus ignored")
	session.pointer_release(world)
	_check(session.sim.get_drag_atom() == null, "no drag started in reacting")


func _test_session_movable_snap() -> void:
	print("-- session movable snap")
	var session = _GameSession.new()
	_check(session.start_pack(_GameLaunch.CAMPAIGN, "2-1"), "loads 2-1")
	var origin: Vector2 = _HexGrid.cell_to_world(3, 3, 2, 0)
	_check(session.pointer_press(origin), "begin drag movable")
	_check(session.sim.state == "dragging", "state dragging")
	var empty: Vector2 = _HexGrid.cell_to_world(3, 3, 1, 0)
	session.pointer_move(empty)
	_check(session.pointer_release(empty), "drop on empty")
	_check(session.sim.atom_at(1, 0) != null, "moved to empty cell")
	_check(session.sim.atom_at(2, 0) == null, "left origin")
	var moved_pos: Vector2 = _HexGrid.cell_to_world(3, 3, 1, 0)
	session.pointer_press(moved_pos)
	var occupied: Vector2 = _HexGrid.cell_to_world(3, 3, 0, 0)
	session.pointer_release(occupied)
	_check(session.sim.atom_at(1, 0) != null, "occupied drop reverts")
	_check(session.sim.atom_at(0, 0) != null and session.sim.atom_at(0, 0).type == "normal", "occupant unchanged")


func _test_win_delay_advances_to_next() -> void:
	print("-- win delay")
	var session = _GameSession.new()
	session.start_pack(_GameLaunch.CAMPAIGN, "1-1")
	session.pointer_press(_HexGrid.cell_to_world(4, 3, 1, 1))
	var guard := 0
	while session.sim.state == "reacting" and guard < 600:
		session.advance(1.0 / 60.0)
		guard += 1
	_check(session.sim.state == "win", "won 1-1")
	_check(session.map_id() == "1-1", "still on 1-1 during delay")
	session.advance(1.99)
	_check(session.map_id() == "1-1", "not yet 2s")
	session.advance(0.02)
	_check(session.map_id() == "1-2", "after 2s loads 1-2")
	_check(session.hud_state() == "", "state copy cleared")
	_check(session.sim.state == "waiting", "next map waiting")


func _test_restart_cancels_delay() -> void:
	print("-- restart cancels delay")
	var session = _GameSession.new()
	session.start_pack(_GameLaunch.CAMPAIGN, "1-1")
	session.pointer_press(_HexGrid.cell_to_world(4, 3, 1, 1))
	var guard := 0
	while session.sim.state == "reacting" and guard < 600:
		session.advance(1.0 / 60.0)
		guard += 1
	_check(session.sim.state == "win", "won before restart")
	session.restart_immediate()
	_check(session.map_id() == "1-1", "still 1-1")
	_check(session.sim.state == "waiting", "waiting after restart")
	_check(session.hud_state() == "", "cleared completed copy")
	_check(session.sim.atom_at(1, 1) != null, "atoms restored")
	session.advance(2.0)
	_check(session.map_id() == "1-1", "delay did not fire after restart")


func _tick_idle(session, max_frames: int = 600) -> void:
	var guard := 0
	while session.sim.state == "reacting" and guard < max_frames:
		session.advance(1.0 / 60.0)
		guard += 1


func _test_session_catch_3_1() -> void:
	print("-- session 3-1 catch")
	var session = _GameSession.new()
	_check(session.start_pack(_GameLaunch.CAMPAIGN, "3-1"), "loads 3-1")
	_check(session.pointer_press(_HexGrid.cell_to_world(3, 1, 1, 0)), "press shooter")
	_tick_idle(session)
	var catcher = session.sim.atom_at(2, 0)
	_check(catcher != null, "catcher remains")
	if catcher != null:
		_check(catcher.type == "catching", "still catching after hits")
		_check(catcher.parked_count() > 0, "caught at least one neutron")
	session.advance(0.1)
	catcher = session.sim.atom_at(2, 0)
	_check(catcher != null and catcher.type == "normal", "catching becomes normal after window")


func _test_session_entangle_4_1() -> void:
	print("-- session 4-1 entangle")
	var session = _GameSession.new()
	_check(session.start_pack(_GameLaunch.CAMPAIGN, "4-1"), "loads 4-1")
	_check(session.pointer_press(_HexGrid.cell_to_world(3, 3, 0, 0)), "press entangled member")
	_check(session.sim.steps == 0, "one step spent")
	_tick_idle(session)
	_check(session.sim.atom_at(0, 0) == null, "clicked member collapsed")
	_check(session.sim.atom_at(2, 2) == null, "partner collapsed too")


func _test_board_view_sync_smoke() -> void:
	print("-- BoardView sync")
	var session = _GameSession.new()
	session.start_pack(_GameLaunch.CAMPAIGN, "1-1")
	var board = _BoardView.new()
	root.add_child(board)
	board.sync(session, 1.0 / 60.0)
	var marks: Node = board.get_node_or_null("Marks")
	var atoms_root: Node = board.get_node_or_null("Atoms")
	_check(marks != null and marks.get_child_count() > 0, "drew position marks")
	_check(atoms_root != null and atoms_root.get_child_count() == session.sim.atoms.size(), "drew atoms")
	session.pointer_press(_HexGrid.cell_to_world(4, 3, 1, 1))
	session.advance(1.0 / 60.0)
	board.sync(session, 1.0 / 60.0)
	_check(board.get_node_or_null("Neutrons") != null, "neutron layer present")
	board.queue_free()


func _test_atom_view_nuclei_keeps_ppu_scale() -> void:
	print("-- atom view nuclei PPU scale")
	var session = _GameSession.new()
	_check(session.start_pack(_GameLaunch.CAMPAIGN, "1-1"), "loads 1-1 for atom view")
	var view = _AtomView.new()
	root.add_child(view)
	var atom = session.sim.atoms[0]
	view.set_board_size(session.sim.width, session.sim.height)
	view.sync(atom, false, null, 0.0)
	var ppu: float = 1.0 / _ViewTransform.PPU_DEFAULT
	_check(view.nuclei != null, "nuclei sprite exists")
	if view.nuclei != null:
		_check(is_equal_approx(view.nuclei.scale.x, ppu), "idle nuclei uses 1/PPU (got %s)" % str(view.nuclei.scale.x))
		_check(not is_equal_approx(view.nuclei.scale.x, 1.0), "idle nuclei is not world-scale 1")
	view.sync(atom, true, null, 0.0)
	if view.nuclei != null:
		_check(is_equal_approx(view.nuclei.scale.x, ppu * 1.1), "hover nuclei keeps PPU and 1.1")
	view.queue_free()
