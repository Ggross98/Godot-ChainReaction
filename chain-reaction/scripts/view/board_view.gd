class_name BoardView
extends Node2D

const _ViewTransform := preload("res://scripts/view/view_transform.gd")
const _HexGrid := preload("res://scripts/core/hex_grid.gd")
const _AtomView := preload("res://scripts/view/atom_view.gd")
const _NeutronView := preload("res://scripts/view/neutron_view.gd")
const TEX_MARK := preload("res://assets/sprites/position_mark.png")

const ORBIT_FADE_TIME := 0.1
const ORBIT_FADE_SCALE := 1.75
const MARK_COLOR := Color(0.726, 0.726, 0.726)

var _epoch: int = -1
var _event_i: int = 0
var _marks: Node2D
var _atoms_root: Node2D
var _neutrons_root: Node2D
var _vfx: Node2D
var _atom_views: Dictionary = {}
var _neutron_views: Dictionary = {}
var _fades: Array = []


func _ready() -> void:
	_ensure_layers()


func _ensure_layers() -> void:
	if _marks != null:
		return
	_marks = Node2D.new()
	_marks.name = "Marks"
	add_child(_marks)
	_atoms_root = Node2D.new()
	_atoms_root.name = "Atoms"
	_atoms_root.z_index = 1
	add_child(_atoms_root)
	_neutrons_root = Node2D.new()
	_neutrons_root.name = "Neutrons"
	_neutrons_root.z_index = 2
	add_child(_neutrons_root)
	_vfx = Node2D.new()
	_vfx.name = "Vfx"
	_vfx.z_index = 3
	add_child(_vfx)


func sync(session, dt: float) -> void:
	_ensure_layers()
	if session == null or session.sim == null:
		return
	if _epoch != session.board_epoch:
		_rebuild(session)
	var sim = session.sim
	_drain_events(sim)
	_sync_atoms(session, dt)
	_sync_neutrons(sim, dt)
	_tick_fades(dt)


func pointer_logic() -> Vector2:
	return _ViewTransform.view_to_logic(to_local(get_global_mouse_position()))


func _rebuild(session) -> void:
	_epoch = session.board_epoch
	_event_i = 0
	_clear_children(_marks)
	_clear_children(_atoms_root)
	_clear_children(_neutrons_root)
	_clear_children(_vfx)
	_atom_views.clear()
	_neutron_views.clear()
	_fades.clear()
	var sim = session.sim
	for y in range(sim.height):
		var row_w: int = sim.width if y % 2 == 0 else sim.width - 1
		for x in range(row_w):
			var mark := Sprite2D.new()
			mark.texture = TEX_MARK
			mark.modulate = MARK_COLOR
			var world: Vector2 = _HexGrid.cell_to_world(sim.width, sim.height, x, y)
			mark.position = _ViewTransform.logic_to_view(world)
			mark.scale = Vector2.ONE * (0.2 / 32.0)
			_marks.add_child(mark)


func _sync_atoms(session, dt: float) -> void:
	var sim = session.sim
	var hover = null
	if sim.state == "waiting":
		hover = session.pick_atom(session.pointer)
	var drag = sim.get_drag_atom()
	var seen: Dictionary = {}
	for atom in sim.atoms:
		seen[atom.id] = true
		var view: Node2D = _atom_views.get(atom.id)
		if view == null:
			view = _AtomView.new()
			_atoms_root.add_child(view)
			_atom_views[atom.id] = view
		view.set_board_size(sim.width, sim.height)
		var drag_logic = session.pointer if drag != null and drag.id == atom.id else null
		view.sync(atom, hover != null and hover.id == atom.id, drag_logic, dt)
	for id in _atom_views.keys():
		if not seen.has(id):
			_atom_views[id].queue_free()
			_atom_views.erase(id)


func _sync_neutrons(sim, dt: float) -> void:
	var seen: Dictionary = {}
	for n in sim.flying:
		if not n.alive:
			continue
		seen[n.id] = true
		var view = _neutron_views.get(n.id)
		if view == null:
			view = _NeutronView.new()
			view.neutron_id = n.id
			view.begin_trace()
			_neutrons_root.add_child(view)
			_neutron_views[n.id] = view
		view.sync(n.pos, dt)
	for id in _neutron_views.keys():
		if not seen.has(id):
			_neutron_views[id].queue_free()
			_neutron_views.erase(id)


func _drain_events(sim) -> void:
	while _event_i < sim.events.size():
		var ev: String = sim.events[_event_i]
		_event_i += 1
		if ev.begins_with("release:"):
			var id := int(ev.get_slice(":", 1))
			_spawn_orbit_fade(id)
		elif ev.begins_with("catch:"):
			var nid := int(ev.get_slice(":", 1))
			var nv = _neutron_views.get(nid)
			if nv != null:
				nv.hide_trace()


func _spawn_orbit_fade(atom_id: int) -> void:
	var view = _atom_views.get(atom_id)
	if view == null:
		return
	var src: Sprite2D = view.last_solid_orbit()
	if src == null or src.texture == null:
		return
	var fade := Sprite2D.new()
	fade.texture = src.texture
	fade.scale = src.scale * view.scale
	fade.position = view.position
	fade.modulate = src.modulate
	_vfx.add_child(fade)
	_fades.append({"node": fade, "t": 0.0, "base_scale": fade.scale, "base_a": fade.modulate.a})


func _tick_fades(dt: float) -> void:
	var kept: Array = []
	for fade in _fades:
		fade.t += dt
		var k: float = clampf(fade.t / ORBIT_FADE_TIME, 0.0, 1.0)
		var node: Sprite2D = fade.node
		node.scale = fade.base_scale * lerpf(1.0, ORBIT_FADE_SCALE, k)
		var c: Color = node.modulate
		c.a = fade.base_a * (1.0 - k)
		node.modulate = c
		if fade.t >= ORBIT_FADE_TIME:
			node.queue_free()
		else:
			kept.append(fade)
	_fades = kept


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
