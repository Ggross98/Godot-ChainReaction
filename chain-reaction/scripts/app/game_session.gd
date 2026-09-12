class_name GameSession
extends RefCounted

const _MapLoader := preload("res://scripts/content/map_loader.gd")
const _Simulation := preload("res://scripts/core/simulation.gd")
const _HexGrid := preload("res://scripts/core/hex_grid.gd")
const _SimConstants := preload("res://scripts/core/sim_constants.gd")
const _BehaviorRegistry := preload("res://scripts/core/behaviors/behavior_registry.gd")
const _HudStrings := preload("res://scripts/app/hud_strings.gd")

const OUTCOME_DELAY := 2.0

var sim = _Simulation.new()
var pack = null
var map_index: int = 0
var current_map = null
var outcome_delay: float = -1.0
var pointer: Vector2 = Vector2.ZERO
var board_epoch: int = 0

var _pack_path: String = ""
var _outcome_armed: bool = false


func start_pack(path: String, target_id: String) -> bool:
	var result = _MapLoader.new().load_pack_file(path)
	if not result.ok:
		push_error("GameSession: failed to load %s: %s" % [path, ",".join(result.errors)])
		return false
	pack = result.pack
	_pack_path = path
	var found := -1
	for i in range(pack.maps.size()):
		if pack.maps[i].id == target_id:
			found = i
			break
	if found < 0:
		push_error("GameSession: map not found: %s" % target_id)
		return false
	map_index = found
	_reload_current()
	return true


func map_id() -> String:
	if current_map == null:
		return ""
	return current_map.id


func pack_path() -> String:
	return _pack_path


func hud_progress() -> String:
	if pack == null or pack.maps.is_empty():
		return "0 / 0"
	return "%d / %d" % [map_index + 1, pack.maps.size()]


func hud_title() -> String:
	if current_map == null:
		return ""
	return current_map.name


func hud_steps() -> String:
	return _HudStrings.left_steps(sim.steps)


func hud_state() -> String:
	if sim.state == _Simulation.STATE_WIN:
		return _HudStrings.COMPLETED
	if sim.state == _Simulation.STATE_LOSE:
		return _HudStrings.FAILED
	return ""


func restart_immediate() -> void:
	_clear_outcome()
	_reload_current()


func goto_next() -> void:
	if pack == null or pack.maps.is_empty():
		return
	map_index = (map_index + 1) % pack.maps.size()
	_clear_outcome()
	_reload_current()


func goto_prev() -> void:
	if pack == null or pack.maps.is_empty():
		return
	map_index = (map_index - 1 + pack.maps.size()) % pack.maps.size()
	_clear_outcome()
	_reload_current()


func advance(dt: float) -> void:
	if dt <= 0.0:
		return
	if _outcome_armed:
		outcome_delay -= dt
		if outcome_delay <= 0.0:
			_resolve_outcome()
		return
	sim.tick(dt)
	if sim.state == _Simulation.STATE_WIN or sim.state == _Simulation.STATE_LOSE:
		_outcome_armed = true
		outcome_delay = OUTCOME_DELAY


func pointer_move(logic: Vector2) -> void:
	pointer = logic


func pointer_press(logic: Vector2) -> bool:
	pointer = logic
	if sim.state != _Simulation.STATE_WAITING:
		return false
	var atom = pick_atom(logic)
	if atom == null:
		return false
	var behavior = _BehaviorRegistry.of(atom.type)
	if behavior.press_action() == "release":
		return sim.press_cell(atom.x, atom.y)
	if behavior.can_drag():
		return sim.begin_drag_cell(atom.x, atom.y)
	return false


func pointer_release(logic: Vector2) -> bool:
	pointer = logic
	if sim.state != _Simulation.STATE_DRAGGING:
		return false
	var cell: Vector2i = _HexGrid.world_to_cell(sim.width, sim.height, logic)
	return sim.end_drag_cell(cell.x, cell.y)


func pick_atom(logic: Vector2):
	var best = null
	var best_d := INF
	var radius: float = _SimConstants.ATOM_ROOT_RADIUS
	for atom in sim.atoms:
		if atom.collapsed:
			continue
		var world: Vector2 = _HexGrid.cell_to_world(sim.width, sim.height, atom.x, atom.y)
		var d: float = world.distance_to(logic)
		if d <= radius and d < best_d:
			best = atom
			best_d = d
	return best


func _reload_current() -> void:
	if pack == null or map_index < 0 or map_index >= pack.maps.size():
		return
	current_map = pack.maps[map_index]
	sim.setup(current_map)
	board_epoch += 1


func _clear_outcome() -> void:
	_outcome_armed = false
	outcome_delay = -1.0


func _resolve_outcome() -> void:
	var kind: String = sim.state
	_clear_outcome()
	if kind == _Simulation.STATE_WIN:
		goto_next()
	else:
		_reload_current()
