class_name Simulation
extends RefCounted

const _HexGrid := preload("res://scripts/core/hex_grid.gd")
const _SimConstants := preload("res://scripts/core/sim_constants.gd")
const _AtomRuntime := preload("res://scripts/core/atom_runtime.gd")
const _NeutronRuntime := preload("res://scripts/core/neutron_runtime.gd")
const _BehaviorRegistry := preload("res://scripts/core/behaviors/behavior_registry.gd")
const _MapSchema := preload("res://scripts/core/map_schema.gd")

const STATE_WAITING := "waiting"
const STATE_DRAGGING := "dragging"
const STATE_REACTING := "reacting"
const STATE_WIN := "win"
const STATE_LOSE := "lose"

var state: String = STATE_WAITING
var steps: int = 0
var events: PackedStringArray = PackedStringArray()
var time: float = 0.0
var width: int = 1
var height: int = 1
var atoms: Array = []
var flying: Array = []
var _occupancy: Dictionary = {}
var _next_neutron_id: int = 0
var _drag_atom: _AtomRuntime
var _drag_origin: Vector2i = Vector2i.ZERO


func setup(map: Object) -> void:
	state = STATE_WAITING
	steps = map.steps
	events = PackedStringArray()
	time = 0.0
	width = map.width
	height = map.height
	atoms.clear()
	flying.clear()
	_occupancy.clear()
	_next_neutron_id = 0
	_drag_atom = null
	var i := 0
	for src in map.atoms:
		var atom := _AtomRuntime.new()
		atom.id = i
		atom.x = src.x
		atom.y = src.y
		atom.type = src.type
		atom.group = src.group
		atom.parked = []
		for layer in src.orbits:
			var copy: Array = []
			for dir in layer:
				copy.append(str(dir))
			atom.parked.append(copy)
		atom.current_layer = atom.parked.size() - 1
		atoms.append(atom)
		_occupancy[_cell_key(atom.x, atom.y)] = atom
		i += 1


func atom_at(x: int, y: int) -> _AtomRuntime:
	return _occupancy.get(_cell_key(x, y), null)


func get_drag_atom() -> _AtomRuntime:
	return _drag_atom


func press_cell(x: int, y: int) -> bool:
	if state != STATE_WAITING:
		return false
	var atom := atom_at(x, y)
	if atom == null or atom.collapsed:
		return false
	var action: String = _BehaviorRegistry.of(atom.type).press_action()
	if action != "release":
		return false
	steps -= 1
	state = STATE_REACTING
	_release_atom(atom, {})
	if flying.is_empty():
		_finish_reaction()
	return true


func begin_drag_cell(x: int, y: int) -> bool:
	if state != STATE_WAITING:
		return false
	var atom := atom_at(x, y)
	if atom == null or atom.collapsed:
		return false
	if not _BehaviorRegistry.of(atom.type).can_drag():
		return false
	state = STATE_DRAGGING
	_drag_atom = atom
	_drag_origin = Vector2i(atom.x, atom.y)
	return true


func end_drag_cell(x: int, y: int) -> bool:
	if state != STATE_DRAGGING or _drag_atom == null:
		return false
	var atom := _drag_atom
	var dest := Vector2i(x, y)
	var moved := false
	if dest != _drag_origin and _HexGrid.is_in_map(width, height, x, y) and atom_at(x, y) == null:
		_occupancy.erase(_cell_key(atom.x, atom.y))
		atom.x = x
		atom.y = y
		_occupancy[_cell_key(x, y)] = atom
		moved = true
	_drag_atom = null
	state = STATE_WAITING
	return moved or dest == _drag_origin


func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	if state == STATE_REACTING:
		var leftover := _advance_reaction(dt)
		if leftover > 0.0 and state != STATE_REACTING:
			_advance_windows(leftover)
	else:
		_advance_windows(dt)


func run_until_idle() -> void:
	var guard := 0
	while state == STATE_REACTING and guard < 10000:
		_advance_reaction(1e6)
		guard += 1


func _release_atom(atom: _AtomRuntime, released: Dictionary) -> void:
	if atom == null or atom.collapsed:
		return
	if released.has(atom.id):
		return
	released[atom.id] = true
	_emit_outer(atom)
	if _BehaviorRegistry.of(atom.type).is_entangled():
		for other in atoms:
			if other.id == atom.id or other.collapsed:
				continue
			if other.group == atom.group and _BehaviorRegistry.of(other.type).is_entangled():
				_release_atom(other, released)


func _emit_outer(atom: _AtomRuntime) -> void:
	if atom.collapsed:
		return
	events.append("release:%d" % atom.id)
	if atom.current_layer < 0 or atom.parked.is_empty():
		_collapse(atom)
		return
	var layer_i := atom.current_layer
	if layer_i >= atom.parked.size():
		layer_i = atom.parked.size() - 1
	var dirs: Array = atom.parked[layer_i]
	var radius := _spawn_radius(atom, layer_i)
	var origin := _atom_world(atom)
	for dir_id in dirs:
		_spawn_neutron(atom, origin, str(dir_id), radius)
	atom.parked[layer_i] = []
	atom.current_layer -= 1
	if atom.current_layer < 0:
		_collapse(atom)


func _spawn_radius(atom: _AtomRuntime, layer_i: int) -> float:
	if atom.parked.size() <= 1:
		return _SimConstants.ORBIT_MID
	if layer_i <= 0:
		return _SimConstants.ORBIT_INNER
	return _SimConstants.ORBIT_OUTER


func _spawn_neutron(atom: _AtomRuntime, origin: Vector2, dir_id: String, radius: float) -> void:
	var raw := _HexGrid.direction_vector(dir_id)
	if raw == Vector2.ZERO:
		return
	var n := _NeutronRuntime.new()
	n.id = _next_neutron_id
	_next_neutron_id += 1
	n.dir_id = dir_id
	n.vel = raw.normalized() * _SimConstants.NEUTRON_SPEED
	n.pos = origin + raw.normalized() * radius
	n.ignore_atom_id = atom.id
	n.alive = true
	flying.append(n)
	events.append("spawn:%d:%s:%d" % [n.id, dir_id, atom.id])


func _collapse(atom: _AtomRuntime) -> void:
	if atom.collapsed:
		return
	atom.collapsed = true
	atom.current_layer = -1
	_occupancy.erase(_cell_key(atom.x, atom.y))
	events.append("collapse:%d" % atom.id)


func _advance_reaction(dt: float) -> float:
	var remaining := dt
	while remaining > 0.0 and state == STATE_REACTING:
		_refresh_ignore()
		var group := _next_event_group(remaining)
		if group.is_empty():
			_move_neutrons(remaining)
			time += remaining
			return 0.0
		var t: float = group[0].t
		_move_neutrons(t)
		time += t
		remaining -= t
		for ev in group:
			_apply_event(ev)
		_cull_flying()
		if flying.is_empty() and state == STATE_REACTING:
			_finish_reaction()
			return remaining
	return 0.0


func _refresh_ignore() -> void:
	for n in flying:
		if not n.alive or n.ignore_atom_id < 0:
			continue
		var src := _atom_by_id(n.ignore_atom_id)
		if src == null or src.collapsed:
			n.ignore_atom_id = -1
			continue
		var dist: float = n.pos.distance_to(_atom_world(src))
		if dist > _SimConstants.NUCLEI_RADIUS + _SimConstants.NEUTRON_RADIUS:
			n.ignore_atom_id = -1


func _next_event_group(horizon: float) -> Array:
	var candidates: Array = []
	for n in flying:
		if not n.alive:
			continue
		_push_candidate(candidates, _time_to_wall(n), horizon, {"kind": "wall", "neutron": n, "atom": null})
		for atom in atoms:
			if atom.collapsed or n.ignore_atom_id == atom.id:
				continue
			var p: Vector2 = n.pos - _atom_world(atom)
			if _is_catchable(atom):
				var tc := _time_to_circle(p, n.vel, _SimConstants.CATCH_ORBIT_RADIUS + _SimConstants.NEUTRON_RADIUS)
				_push_candidate(candidates, tc, horizon, {"kind": "catch", "neutron": n, "atom": atom})
			var tn := _time_to_circle(p, n.vel, _SimConstants.NUCLEI_RADIUS + _SimConstants.NEUTRON_RADIUS)
			_push_candidate(candidates, tn, horizon, {"kind": "nuclei", "neutron": n, "atom": atom})
	for atom in atoms:
		if atom.collapsed or atom.catch_window_end < 0.0:
			continue
		var tw: float = atom.catch_window_end - time
		_push_candidate(candidates, tw, horizon, {"kind": "catch_window", "neutron": null, "atom": atom})
	if candidates.is_empty():
		return []
	candidates.sort_custom(_event_less)
	var min_t: float = candidates[0].t
	var group: Array = []
	for ev in candidates:
		if ev.t <= min_t + 1e-9:
			group.append(ev)
		else:
			break
	return group


func _push_candidate(candidates: Array, t: float, horizon: float, ev: Dictionary) -> void:
	if t < 0.0 or t > horizon or t == INF:
		return
	ev.t = t
	candidates.append(ev)


func _event_less(a: Dictionary, b: Dictionary) -> bool:
	if a.t < b.t - 1e-9:
		return true
	if b.t < a.t - 1e-9:
		return false
	var aid := _event_neutron_id(a)
	var bid := _event_neutron_id(b)
	if aid != bid:
		return aid < bid
	var aa: _AtomRuntime = a.atom
	var ba: _AtomRuntime = b.atom
	if aa == null and ba == null:
		return false
	if aa == null:
		return false
	if ba == null:
		return true
	if aa.y != ba.y:
		return aa.y < ba.y
	return aa.x < ba.x


func _event_neutron_id(ev: Dictionary) -> int:
	var n = ev.neutron
	if n == null:
		return 1 << 30
	return n.id


func _apply_event(ev: Dictionary) -> void:
	var kind: String = ev.kind
	if kind == "catch_window":
		_end_catch_window(ev.atom)
		return
	var n: _NeutronRuntime = ev.neutron
	if n == null or not n.alive:
		return
	if kind == "wall":
		n.alive = false
		events.append("wall:%d" % n.id)
		return
	var atom: _AtomRuntime = ev.atom
	if atom == null or atom.collapsed:
		return
	if kind == "catch":
		if not _is_catchable(atom):
			return
		_catch(n, atom)
		return
	if kind == "nuclei":
		n.alive = false
		events.append("nuclei:%d:%d" % [n.id, atom.id])
		_release_atom(atom, {})


func _catch(n: _NeutronRuntime, atom: _AtomRuntime) -> void:
	n.alive = false
	events.append("catch:%d:%d" % [n.id, atom.id])
	var bounced := _HexGrid.bounce_dir(n.dir_id)
	if atom.parked.is_empty():
		atom.parked.append([])
		atom.current_layer = 0
	var layer: Array = atom.parked[0]
	layer.append(bounced)
	atom.parked[0] = layer
	if atom.catch_window_end < 0.0:
		atom.catch_window_end = time + _SimConstants.CATCH_WINDOW


func _end_catch_window(atom: _AtomRuntime) -> void:
	if atom == null or atom.collapsed or atom.catch_window_end < 0.0:
		return
	if time + 1e-9 < atom.catch_window_end:
		return
	var next_type: String = str(_BehaviorRegistry.of(atom.type).type_after_catch())
	atom.catch_window_end = -1.0
	if next_type != "":
		atom.type = next_type
	events.append("catch_end:%d:%s" % [atom.id, atom.type])


func _is_catchable(atom: _AtomRuntime) -> bool:
	if atom.collapsed:
		return false
	if atom.catch_window_end >= 0.0 and time >= atom.catch_window_end:
		return false
	if _MapSchema.is_catching_type(atom.type):
		return true
	return _BehaviorRegistry.of(atom.type).can_catch()


func _advance_windows(dt: float) -> void:
	time += dt
	for atom in atoms:
		if atom.catch_window_end >= 0.0 and time + 1e-9 >= atom.catch_window_end:
			_end_catch_window(atom)


func _move_neutrons(dt: float) -> void:
	for n in flying:
		if n.alive:
			n.pos += n.vel * dt


func _cull_flying() -> void:
	var kept: Array = []
	for n in flying:
		if n.alive:
			kept.append(n)
	flying = kept


func _finish_reaction() -> void:
	if _uncollapsed_count() == 0:
		state = STATE_WIN
		events.append("win")
	elif steps > 0:
		state = STATE_WAITING
	else:
		state = STATE_LOSE
		events.append("lose")


func _uncollapsed_count() -> int:
	var n := 0
	for atom in atoms:
		if not atom.collapsed:
			n += 1
	return n


func _atom_world(atom: _AtomRuntime) -> Vector2:
	return _HexGrid.cell_to_world(width, height, atom.x, atom.y)


func _atom_by_id(id: int) -> _AtomRuntime:
	for atom in atoms:
		if atom.id == id:
			return atom
	return null


func _cell_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func _time_to_circle(p: Vector2, v: Vector2, radius: float) -> float:
	var c := p.dot(p) - radius * radius
	if c <= 0.0:
		return 0.0
	var a := v.dot(v)
	if a < 1e-12:
		return INF
	var b := 2.0 * p.dot(v)
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return INF
	var root := sqrt(disc)
	var t1 := (-b - root) / (2.0 * a)
	var t2 := (-b + root) / (2.0 * a)
	if t1 > _SimConstants.TOI_EPS:
		return t1
	if t2 > _SimConstants.TOI_EPS:
		return t2
	return INF


func _time_to_wall(n: _NeutronRuntime) -> float:
	var r := _SimConstants.NEUTRON_RADIUS
	var pos := n.pos
	var vel := n.vel
	if pos.x <= _SimConstants.WALL_MIN.x + r or pos.x >= _SimConstants.WALL_MAX.x - r or pos.y <= _SimConstants.WALL_MIN.y + r or pos.y >= _SimConstants.WALL_MAX.y - r:
		return 0.0
	var t := INF
	if vel.x > 1e-12:
		t = minf(t, (_SimConstants.WALL_MAX.x - r - pos.x) / vel.x)
	elif vel.x < -1e-12:
		t = minf(t, (_SimConstants.WALL_MIN.x + r - pos.x) / vel.x)
	if vel.y > 1e-12:
		t = minf(t, (_SimConstants.WALL_MAX.y - r - pos.y) / vel.y)
	elif vel.y < -1e-12:
		t = minf(t, (_SimConstants.WALL_MIN.y + r - pos.y) / vel.y)
	if t < 0.0:
		return 0.0
	return t
