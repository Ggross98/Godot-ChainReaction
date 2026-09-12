extends SceneTree

const _HexGrid := preload("res://scripts/core/hex_grid.gd")
const _MapLoader := preload("res://scripts/content/map_loader.gd")
const _Simulation := preload("res://scripts/core/simulation.gd")

var _failures: int = 0


func _init() -> void:
	print("=== Phase B tests ===")
	_test_hex_spacing_and_roundtrip()
	_test_press_normal_costs_step()
	_test_chain_hit_does_not_cost_step()
	_test_single_layer_collapses()
	_test_double_layer_outer_then_inner()
	_test_movable_drag()
	_test_catch_and_window()
	_test_catching_movable_becomes_movable()
	_test_entangle()
	_test_self_release_does_not_instantly_finish()
	_test_event_order_stable()
	_test_win_and_lose()
	print("=== %d failure(s) ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)


func _map(width: int, height: int, steps: int, atoms: Array) -> Object:
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


func _sim(width: int, height: int, steps: int, atoms: Array) -> Object:
	var map = _map(width, height, steps, atoms)
	if map == null:
		return null
	var sim = _Simulation.new()
	sim.setup(map)
	return sim


func _test_hex_spacing_and_roundtrip() -> void:
	print("-- HexGrid world")
	_check(is_equal_approx(_HexGrid.spacing(4, 3), 3.0), "small map spacing 3")
	_check(is_equal_approx(_HexGrid.spacing(6, 3), 1.8), "wide map spacing 1.8")
	_check(is_equal_approx(_HexGrid.spacing(4, 5), 1.8), "tall map spacing 1.8")
	var w := _HexGrid.cell_to_world(4, 3, 1, 0)
	var back := _HexGrid.world_to_cell(4, 3, w)
	_check(back == Vector2i(1, 0), "even-row roundtrip")
	var w_odd := _HexGrid.cell_to_world(4, 3, 1, 1)
	var even := _HexGrid.cell_to_world(4, 3, 1, 0)
	_check(w_odd.x > even.x, "odd row is shifted right")
	_check(_HexGrid.world_to_cell(4, 3, w_odd) == Vector2i(1, 1), "odd-row roundtrip")
	var e := _HexGrid.direction_vector("E")
	_check(is_equal_approx(e.x, 1.0) and is_equal_approx(e.y, 0.0), "E is +x")
	var nw := _HexGrid.direction_vector("NW")
	_check(nw.x < 0.0 and nw.y > 0.0, "NW is -x +y (y up)")


func _test_press_normal_costs_step() -> void:
	print("-- press normal costs a step")
	var sim = _sim(3, 1, 2, [
		{"x": 0, "y": 0, "type": "normal", "orbits": [["W"]]},
	])
	if sim == null:
		return
	_check(sim.steps == 2, "starts with 2 steps")
	_check(sim.press_cell(0, 0), "press succeeds")
	_check(sim.steps == 1, "press costs 1 step")
	_check(sim.state == "reacting", "enters reacting")


func _test_chain_hit_does_not_cost_step() -> void:
	print("-- chain hit does not cost a step")
	var sim = _sim(3, 1, 1, [
		{"x": 0, "y": 0, "type": "normal", "orbits": [["E"]]},
		{"x": 1, "y": 0, "type": "normal", "orbits": [["E"]]},
	])
	if sim == null:
		return
	sim.press_cell(0, 0)
	sim.run_until_idle()
	_check(sim.steps == 0, "chain did not spend extra steps")
	_check(sim.atom_at(0, 0) == null, "first atom collapsed")
	_check(sim.atom_at(1, 0) == null, "second atom collapsed from hit")


func _test_single_layer_collapses() -> void:
	print("-- single layer collapses")
	var sim = _sim(3, 1, 1, [
		{"x": 0, "y": 0, "type": "normal", "orbits": [["W"]]},
	])
	if sim == null:
		return
	sim.press_cell(0, 0)
	sim.run_until_idle()
	_check(sim.atom_at(0, 0) == null, "single-layer atom is gone")
	_check(sim.state == "win", "board clear is win")


func _test_double_layer_outer_then_inner() -> void:
	print("-- double layer outer then inner")
	var sim = _sim(3, 1, 2, [
		{"x": 1, "y": 0, "type": "normal", "orbits": [["W"], ["E"]]},
	])
	if sim == null:
		return
	sim.press_cell(1, 0)
	sim.run_until_idle()
	var atom = sim.atom_at(1, 0)
	_check(atom != null, "still on board after outer release")
	if atom != null:
		_check(atom.parked_count() == 1, "inner neutrons remain")
	sim.press_cell(1, 0)
	sim.run_until_idle()
	_check(sim.atom_at(1, 0) == null, "collapses after inner release")


func _test_movable_drag() -> void:
	print("-- movable drag")
	var sim = _sim(3, 1, 1, [
		{"x": 0, "y": 0, "type": "movable", "orbits": [["E"]]},
		{"x": 2, "y": 0, "type": "normal", "orbits": [["W"]]},
	])
	if sim == null:
		return
	_check(not sim.press_cell(0, 0), "movable click does not release")
	_check(sim.steps == 1, "movable press does not cost a step")
	_check(sim.state == "waiting", "still waiting after movable click")
	_check(sim.begin_drag_cell(0, 0), "begin drag")
	_check(sim.state == "dragging", "state dragging")
	_check(sim.end_drag_cell(1, 0), "drop on empty cell")
	_check(sim.atom_at(0, 0) == null, "left origin")
	_check(sim.atom_at(1, 0) != null, "now at empty cell")
	_check(sim.begin_drag_cell(1, 0), "drag again")
	sim.end_drag_cell(2, 0)
	_check(sim.atom_at(1, 0) != null, "occupied drop reverts")
	_check(sim.atom_at(2, 0) != null and sim.atom_at(2, 0).type == "normal", "occupant unchanged")


func _test_catch_and_window() -> void:
	print("-- catch window")
	var sim = _sim(3, 1, 2, [
		{"x": 0, "y": 0, "type": "normal", "orbits": [["E", "E"]]},
		{"x": 1, "y": 0, "type": "catching"},
	])
	if sim == null:
		return
	sim.press_cell(0, 0)
	sim.run_until_idle()
	var catcher = sim.atom_at(1, 0)
	_check(catcher != null, "catcher remains")
	if catcher != null:
		_check(catcher.type == "catching", "still catching right after hits")
		_check(catcher.parked_count() == 2, "caught both neutrons in the window")
	sim.tick(0.1)
	catcher = sim.atom_at(1, 0)
	if catcher != null:
		_check(catcher.type == "normal", "catching becomes normal after 0.1s")


func _test_catching_movable_becomes_movable() -> void:
	print("-- catching_movable after window")
	var sim = _sim(3, 1, 2, [
		{"x": 0, "y": 0, "type": "normal", "orbits": [["E"]]},
		{"x": 1, "y": 0, "type": "catching_movable"},
	])
	if sim == null:
		return
	sim.press_cell(0, 0)
	sim.run_until_idle()
	sim.tick(0.1)
	var atom = sim.atom_at(1, 0)
	_check(atom != null and atom.type == "movable", "becomes movable")
	if atom != null:
		_check(sim.begin_drag_cell(1, 0), "can drag after catch")
		sim.end_drag_cell(2, 0)
		_check(sim.atom_at(2, 0) != null, "moved as movable")
		_check(sim.atom_at(2, 0).type == "movable", "still movable")
		_check(not sim.press_cell(2, 0), "still cannot click-release")
		_check(sim.state != "reacting", "press did not start a reaction")


func _test_entangle() -> void:
	print("-- entangle")
	var sim = _sim(3, 1, 1, [
		{"x": 0, "y": 0, "type": "entangled", "group": 1, "orbits": [["W"]]},
		{"x": 2, "y": 0, "type": "entangled", "group": 1, "orbits": [["E"]]},
	])
	if sim == null:
		return
	sim.press_cell(0, 0)
	_check(sim.steps == 0, "entangle cascade costs 1 step total")
	sim.run_until_idle()
	_check(sim.atom_at(0, 0) == null, "clicked member collapsed")
	_check(sim.atom_at(2, 0) == null, "partner released too")
	_check(sim.state == "win", "both gone is win")


func _test_self_release_does_not_instantly_finish() -> void:
	print("-- self release ignore")
	var sim = _sim(3, 1, 2, [
		{"x": 1, "y": 0, "type": "normal", "orbits": [["W"], ["E"]]},
	])
	if sim == null:
		return
	sim.press_cell(1, 0)
	_check(sim.atom_at(1, 0) != null, "does not instantly collapse from own neutron")
	sim.run_until_idle()
	_check(sim.atom_at(1, 0) != null, "still present after outer neutron leaves")


func _test_event_order_stable() -> void:
	print("-- event order stable")
	var atoms := [
		{"x": 1, "y": 0, "type": "normal", "orbits": [["W", "E"]]},
		{"x": 0, "y": 0, "type": "normal", "orbits": [["W"]]},
		{"x": 2, "y": 0, "type": "normal", "orbits": [["E"]]},
	]
	var a = _sim(3, 1, 1, atoms)
	var b = _sim(3, 1, 1, atoms)
	if a == null or b == null:
		return
	a.press_cell(1, 0)
	a.run_until_idle()
	b.press_cell(1, 0)
	b.run_until_idle()
	_check(a.events == b.events, "two identical runs match")
	_check(a.events.size() > 0, "events were recorded")


func _test_win_and_lose() -> void:
	print("-- win and lose")
	var win_sim = _sim(3, 1, 1, [
		{"x": 0, "y": 0, "type": "normal", "orbits": [["W"]]},
	])
	if win_sim != null:
		win_sim.press_cell(0, 0)
		win_sim.run_until_idle()
		_check(win_sim.state == "win", "clearing the board wins")
	var lose_sim = _sim(3, 1, 1, [
		{"x": 0, "y": 0, "type": "normal", "orbits": [["W"]]},
		{"x": 2, "y": 0, "type": "normal", "orbits": [["E"]]},
	])
	if lose_sim != null:
		lose_sim.press_cell(0, 0)
		lose_sim.run_until_idle()
		_check(lose_sim.state == "lose", "steps gone with atoms left loses")
		_check(lose_sim.atom_at(2, 0) != null, "unrelated atom remains")
