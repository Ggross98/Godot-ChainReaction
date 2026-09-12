extends SceneTree

const _HexGrid := preload("res://scripts/core/hex_grid.gd")
const _BoardTransition := preload("res://scripts/view/board_transition.gd")
const _AtomView := preload("res://scripts/view/atom_view.gd")
const _GameSession := preload("res://scripts/app/game_session.gd")
const _GameLaunch := preload("res://scripts/app/game_launch.gd")
const _SaveAccount := preload("res://scripts/app/save_account.gd")
const _BoardView := preload("res://scripts/view/board_view.gd")
const ATOM_SCENE := preload("res://prefabs/atom_view.tscn")
const _SceneFadeScript := preload("res://scripts/view/scene_fade.gd")

const TEST_PATH := "user://phase_f_test.cfg"

var _failures: int = 0
var _saved_path: String = ""


func _init() -> void:
	print("=== Phase F tests ===")
	_saved_path = _SaveAccount.path
	_SaveAccount.path = TEST_PATH
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	_SaveAccount.reset_memory()
	_test_odd_r_distance()
	_test_transition_empty_not_active()
	_test_transition_enter_timing()
	_test_transition_stagger_cap()
	_test_transition_cut()
	_test_atom_assemble_pose()
	_test_board_view_transitions()
	_test_session_reload_does_not_wait()
	_test_scene_fade_busy()
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	_SaveAccount.path = _saved_path
	_SaveAccount.reset_memory()
	print("=== %d failure(s) ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)


func _cells(coords: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in coords:
		out.append(c)
	return out


func _test_odd_r_distance() -> void:
	print("-- HexGrid.odd_r_distance")
	_check(_HexGrid.odd_r_distance(0, 0, 0, 0) == 0, "identity is 0")
	_check(_HexGrid.odd_r_distance(0, 0, 1, 0) == 1, "even-row east neighbor is 1")
	_check(_HexGrid.odd_r_distance(0, 0, 0, 1) == 1, "even-row NE neighbor is 1")
	_check(_HexGrid.odd_r_distance(0, 0, 1, 1) == 2, "(0,0) to (1,1) is 2")


func _test_transition_empty_not_active() -> void:
	print("-- BoardTransition empty")
	var tr := _BoardTransition.new()
	tr.begin(_cells([]), _cells([]), Vector2i.ZERO)
	_check(not tr.is_active(), "empty begin is not active")


func _test_transition_enter_timing() -> void:
	print("-- BoardTransition enter timing")
	var origin := Vector2i(2, 2)
	var enter := _cells([
		origin,
		Vector2i(1, 2),
		Vector2i(3, 2),
		Vector2i(2, 1),
		Vector2i(2, 3),
		Vector2i(1, 1),
		Vector2i(3, 1),
	])
	var tr := _BoardTransition.new()
	tr.begin(enter, _cells([]), origin)
	_check(tr.is_active(), "seven-cell enter is active")
	for c in enter:
		_check(is_equal_approx(tr.enter_k(c), 0.0), "enter_k 0 at t=0 for %s" % str(c))
	tr.tick(1.0)
	for c in enter:
		_check(is_equal_approx(tr.enter_k(c), 1.0), "enter_k 1 at t=1 for %s" % str(c))
	_check(not tr.is_active(), "complete after 1s")


func _test_transition_stagger_cap() -> void:
	print("-- BoardTransition stagger cap")
	var far := Vector2i(20, 0)
	var tr := _BoardTransition.new()
	tr.begin(_cells([far]), _cells([]), Vector2i.ZERO)
	var max_t: float = _BoardTransition.STAGGER_CAP + _BoardTransition.ATOM_IN + 0.001
	tr.tick(max_t)
	_check(is_equal_approx(tr.enter_k(far), 1.0), "far cell finishes within cap")
	_check(not tr.is_active(), "far-cell duration respects stagger cap")
	var tr2 := _BoardTransition.new()
	tr2.begin(_cells([far]), _cells([Vector2i(0, 0)]), Vector2i.ZERO)
	var with_exit: float = _BoardTransition.STAGGER_CAP + _BoardTransition.ATOM_IN + _BoardTransition.ENTER_OVERLAP + 0.001
	tr2.tick(with_exit)
	_check(not tr2.is_active(), "exit+enter duration still capped")


func _test_transition_cut() -> void:
	print("-- BoardTransition cut")
	var tr := _BoardTransition.new()
	tr.begin(_cells([Vector2i(0, 0)]), _cells([]), Vector2i.ZERO)
	tr.tick(0.05)
	_check(tr.is_active(), "active before cut")
	tr.cut()
	_check(not tr.is_active(), "cut clears active")


func _dummy_atom() -> Object:
	var session = _GameSession.new()
	session.start_pack(_GameLaunch.CAMPAIGN, "1-1")
	return session.sim.atoms[0]


func _test_atom_assemble_pose() -> void:
	print("-- AtomView assemble")
	var view = ATOM_SCENE.instantiate()
	root.add_child(view)
	view.set_assemble(0.0)
	_check(is_equal_approx(view.assemble_k(), 0.0), "assemble_k stores 0")
	_check(is_equal_approx(view.modulate.a, 0.0), "assemble 0 is alpha 0")
	_check(is_equal_approx(view.scale.x, view.root_scale * 0.5), "assemble 0 starts at 50% scale")
	var atom = _dummy_atom()
	view.set_board_size(4, 3)
	view.set_assemble(1.0)
	view.sync(atom, false, null, 0.0)
	_check(is_equal_approx(view.modulate.a, 1.0), "assemble 1 after sync is alpha 1")
	view.set_assemble(0.3)
	view.sync(atom, true, null, 0.0)
	_check(is_equal_approx(view.assemble_k(), 0.3), "reset_collapse does not force assemble to 1")
	_check(is_equal_approx(view.modulate.a, 0.3), "assemble 0.3 keeps alpha")
	var ppu: float = 1.0 / view.ppu_default
	_check(is_equal_approx(view.nuclei.scale.x, ppu), "hover scale off while assembling")
	view.queue_free()


func _test_board_view_transitions() -> void:
	print("-- BoardView is_transitioning")
	var session = _GameSession.new()
	session.start_pack(_GameLaunch.CAMPAIGN, "1-1")
	var board = _BoardView.new()
	root.add_child(board)
	board.sync(session, 0.0)
	_check(board.is_transitioning(), "first epoch assemble is busy")
	var atoms_root: Node = board.get_node_or_null("Atoms")
	_check(atoms_root != null and atoms_root.get_child_count() == session.sim.atoms.size(), "atoms spawn during assemble")
	board.sync(session, 1.0)
	_check(not board.is_transitioning(), "assemble finishes after 1s")
	session.restart_immediate()
	board.sync(session, 0.0)
	_check(board.is_transitioning(), "reload with leftovers starts enter")
	_check(board.get_node_or_null("Ghosts") == null, "leftovers vanish with no ghost")
	board.sync(session, 1.0)
	_check(not board.is_transitioning(), "enter finishes after 1s")
	board.queue_free()


func _test_session_reload_does_not_wait() -> void:
	print("-- session reload ignores visuals")
	var session = _GameSession.new()
	_check(session.start_pack(_GameLaunch.CAMPAIGN, "1-1"), "loads 1-1")
	session.pointer_press(_HexGrid.cell_to_world(4, 3, 1, 1))
	var guard := 0
	while session.sim.state == "reacting" and guard < 600:
		session.advance(1.0 / 60.0)
		guard += 1
	_check(session.sim.state == "win", "won 1-1")
	session.advance(1.52)
	_check(session.map_id() == "1-2", "after 1.5s loads 1-2 with no BoardView")
	_check(session.sim.state == "waiting", "next map waiting")
	_check(session.hud_state() == "", "state copy cleared")


func _test_scene_fade_busy() -> void:
	print("-- SceneFade busy window")
	var fade = _SceneFadeScript.new()
	root.add_child(fade)
	fade._ready()
	_check(not fade.is_busy(), "idle is not busy")
	fade.go("res://scenes/main_menu.tscn")
	_check(fade.is_busy(), "go starts busy")
	fade._process(0.49)
	_check(fade.is_busy(), "still covering at 0.49s")
	var fade_rect := fade.get_node_or_null("Fade") as ColorRect
	_check(fade_rect != null and fade_rect.color.a < 1.0, "cover not finished at 0.49s")
	fade._process(0.02)
	_check(fade.is_busy(), "busy through swap into reveal")
	fade._process(0.50)
	_check(not fade.is_busy(), "idle after cover+reveal")
	fade.queue_free()
