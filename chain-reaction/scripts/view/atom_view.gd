@tool
class_name AtomView
extends Node2D

const _ViewTransform := preload("res://scripts/view/view_transform.gd")
const _HexGrid := preload("res://scripts/core/hex_grid.gd")
const _SimConstants := preload("res://scripts/core/sim_constants.gd")
const _BehaviorRegistry := preload("res://scripts/core/behaviors/behavior_registry.gd")

const TEX_NUCLEI := preload("res://assets/sprites/Nuclei.png")
const TEX_ORBIT0 := preload("res://assets/sprites/Orbit0.png")
const TEX_ORBIT1 := preload("res://assets/sprites/Orbit1.png")
const TEX_ORBIT2 := preload("res://assets/sprites/Orbit2.png")
const TEX_ORBIT_DOTTED := preload("res://assets/sprites/Orbit1_Dotted.png")
const TEX_ARROW := preload("res://assets/sprites/Arrow.png")
const TEX_NEUTRON := preload("res://assets/sprites/Neutron0.png")

const EDITOR_PREVIEW_ZOOM := 108.0
const PREVIEW_DIRS: PackedStringArray = ["W", "NE", "E", "SW"]

enum PreviewPose { IDLE, CATCHING, MOVABLE, ENTANGLED }

@export_group("Preview")
@export var preview_pose: PreviewPose = PreviewPose.IDLE:
	set(value):
		preview_pose = value
		_on_look_changed()

@export_group("Nuclei")
@export var nuclei_default := Color8(33, 33, 33):
	set(value):
		nuclei_default = value
		_on_look_changed()
@export var nuclei_hover := Color8(77, 77, 77):
	set(value):
		nuclei_hover = value
		_on_look_changed()

@export_group("Entangle")
@export var group_1 := Color8(83, 33, 180):
	set(value):
		group_1 = value
		_on_look_changed()
@export var group_1_hover := Color8(130, 130, 180):
	set(value):
		group_1_hover = value
		_on_look_changed()
@export var group_2 := Color8(180, 83, 33):
	set(value):
		group_2 = value
		_on_look_changed()
@export var group_2_hover := Color8(180, 130, 130):
	set(value):
		group_2_hover = value
		_on_look_changed()
@export var group_3 := Color8(33, 180, 83):
	set(value):
		group_3 = value
		_on_look_changed()
@export var group_3_hover := Color8(130, 180, 130):
	set(value):
		group_3_hover = value
		_on_look_changed()

@export_group("Neutron / Arrow")
@export var neutron_color := Color(1.0, 0.733, 0.0):
	set(value):
		neutron_color = value
		_on_look_changed()
@export var arrow_color := Color(0.467, 0.482, 0.498):
	set(value):
		arrow_color = value
		_on_look_changed()

@export_group("Animation")
@export var hover_scale: float = 1.1:
	set(value):
		hover_scale = value
		_on_look_changed()
@export var collapse_time: float = 0.2:
	set(value):
		collapse_time = maxf(value, 0.001)
		_on_look_changed()

@export_group("Pixels")
@export var ppu_default: float = 128.0:
	set(value):
		ppu_default = maxf(value, 1.0)
		_on_look_changed()
@export var ppu_orbit0: float = 120.0:
	set(value):
		ppu_orbit0 = maxf(value, 1.0)
		_on_look_changed()
@export var ppu_arrow: float = 256.0:
	set(value):
		ppu_arrow = maxf(value, 1.0)
		_on_look_changed()
@export var root_scale: float = 0.9:
	set(value):
		root_scale = value
		_on_look_changed()

var atom_id: int = -1
var nuclei: Sprite2D
var orbit0: Sprite2D
var orbit1: Sprite2D
var orbit2: Sprite2D
var orbit_dotted: Sprite2D
var arrows: Node2D
var parked_root: Node2D

var _collapse_t: float = -1.0
var _parked_pool: Array = []
var _look_ready: bool = false
var _board_w: int = 1
var _board_h: int = 1


func _ready() -> void:
	_ensure_children()
	_look_ready = true
	_apply_root_scale()
	if Engine.is_editor_hint():
		_apply_preview_pose()
	else:
		_apply_look()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		scale = Vector2.ONE * root_scale
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_apply_root_scale()


func _ensure_children() -> void:
	if nuclei != null:
		return
	nuclei = get_node_or_null("Nuclei") as Sprite2D
	if nuclei != null:
		orbit0 = get_node("Orbit0") as Sprite2D
		orbit1 = get_node("Orbit1") as Sprite2D
		orbit2 = get_node("Orbit2") as Sprite2D
		orbit_dotted = get_node("OrbitDotted") as Sprite2D
		parked_root = get_node("Parked") as Node2D
		arrows = get_node("Arrows") as Node2D
		_collect_parked_pool()
		return
	_create_fallback_children()


func _create_fallback_children() -> void:
	orbit_dotted = _make_sprite("OrbitDotted", TEX_ORBIT_DOTTED, ppu_default)
	orbit0 = _make_sprite("Orbit0", TEX_ORBIT0, ppu_orbit0)
	orbit1 = _make_sprite("Orbit1", TEX_ORBIT1, ppu_default)
	orbit2 = _make_sprite("Orbit2", TEX_ORBIT2, ppu_default)
	parked_root = Node2D.new()
	parked_root.name = "Parked"
	add_child(parked_root)
	arrows = Node2D.new()
	arrows.name = "Arrows"
	add_child(arrows)
	for i in range(6):
		var arrow := _make_sprite("Arrow%d" % i, TEX_ARROW, ppu_arrow, arrows)
		arrow.rotation = float(i) * TAU / 6.0
		arrow.flip_h = true
		arrow.modulate = arrow_color
	nuclei = _make_sprite("Nuclei", TEX_NUCLEI, ppu_default)
	_collect_parked_pool()


func _collect_parked_pool() -> void:
	_parked_pool.clear()
	if parked_root == null:
		return
	for child in parked_root.get_children():
		if child is Sprite2D:
			_parked_pool.append(child)


func _make_sprite(node_name: String, tex: Texture2D, ppu: float, parent: Node = self) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = node_name
	s.texture = tex
	s.scale = _ViewTransform.sprite_scale(ppu)
	parent.add_child(s)
	return s


func reset_collapse() -> void:
	_collapse_t = -1.0
	visible = true
	modulate.a = 1.0
	if nuclei:
		nuclei.scale = _nuclei_ppu_scale()


func sync(atom, hovering: bool, drag_logic, dt: float) -> void:
	if Engine.is_editor_hint():
		return
	_ensure_children()
	atom_id = atom.id
	if atom.collapsed:
		_run_collapse(dt)
		return
	reset_collapse()
	var world: Vector2 = _HexGrid.cell_to_world(atom_width(atom), atom_height(atom), atom.x, atom.y)
	if drag_logic != null:
		world = drag_logic
	position = _ViewTransform.logic_to_view(world)
	var behavior = _BehaviorRegistry.of(atom.type)
	var group: int = atom.group if behavior.is_entangled() else 0
	var base := _group_color(group, false)
	var hi := _group_color(group, true)
	if hovering and behavior.press_action() == "release":
		nuclei.modulate = hi
	else:
		nuclei.modulate = base
	nuclei.scale = _nuclei_ppu_scale(hover_scale if hovering else 1.0)
	_refresh_orbits(atom, behavior)
	_refresh_parked(atom)
	arrows.visible = behavior.can_drag()


func last_solid_orbit() -> Sprite2D:
	if orbit2 != null and orbit2.visible:
		return orbit2
	if orbit0 != null and orbit0.visible:
		return orbit0
	return orbit1


func atom_width(_atom) -> int:
	return _board_w


func atom_height(_atom) -> int:
	return _board_h


func set_board_size(width: int, height: int) -> void:
	_board_w = width
	_board_h = height


func _run_collapse(dt: float) -> void:
	if _collapse_t < 0.0:
		_collapse_t = 0.0
		orbit0.visible = false
		orbit1.visible = false
		orbit2.visible = false
		orbit_dotted.visible = false
		arrows.visible = false
		parked_root.visible = false
	_collapse_t += dt
	var k: float = clampf(1.0 - _collapse_t / collapse_time, 0.0, 1.0)
	nuclei.scale = _nuclei_ppu_scale(k)
	if _collapse_t >= collapse_time:
		visible = false


func _refresh_orbits(atom, behavior) -> void:
	var catching: bool = behavior.can_catch()
	var remaining := 0
	if atom.current_layer >= 0:
		remaining = atom.current_layer + 1
	orbit_dotted.visible = catching
	orbit0.visible = false
	orbit1.visible = false
	orbit2.visible = false
	if catching:
		return
	if remaining >= 2:
		orbit0.visible = true
		orbit2.visible = true
	elif remaining == 1:
		if atom.parked.size() > 1:
			orbit0.visible = true
		else:
			orbit1.visible = true


func _refresh_parked(atom) -> void:
	parked_root.visible = true
	var needed: int = atom.parked_count()
	while _parked_pool.size() < needed:
		var s := Sprite2D.new()
		s.texture = TEX_NEUTRON
		s.scale = _ViewTransform.sprite_scale(ppu_default)
		s.modulate = neutron_color
		parked_root.add_child(s)
		_parked_pool.append(s)
	for s in _parked_pool:
		s.visible = false
		s.modulate = neutron_color
		s.scale = _ViewTransform.sprite_scale(ppu_default)
	var i := 0
	for layer_i in range(atom.parked.size()):
		var layer: Array = atom.parked[layer_i]
		var radius := _layer_radius(atom, layer_i)
		for dir_id in layer:
			var raw: Vector2 = _HexGrid.direction_vector(str(dir_id))
			if raw == Vector2.ZERO:
				continue
			var local: Vector2 = _ViewTransform.logic_to_view(raw.normalized() * radius)
			var sprite: Sprite2D = _parked_pool[i]
			sprite.position = local
			sprite.visible = true
			i += 1


func _layer_radius(atom, layer_i: int) -> float:
	if atom.parked.size() <= 1:
		return _SimConstants.ORBIT_MID
	if layer_i <= 0:
		return _SimConstants.ORBIT_INNER
	return _SimConstants.ORBIT_OUTER


func _nuclei_ppu_scale(mult: float = 1.0) -> Vector2:
	return _ViewTransform.sprite_scale(ppu_default) * mult


func _group_color(group: int, highlight: bool) -> Color:
	match group:
		1:
			return group_1_hover if highlight else group_1
		2:
			return group_2_hover if highlight else group_2
		3:
			return group_3_hover if highlight else group_3
		_:
			return nuclei_hover if highlight else nuclei_default


func _on_look_changed() -> void:
	if not _look_ready:
		return
	if Engine.is_editor_hint():
		_apply_preview_pose()
	else:
		_apply_look()


func _apply_root_scale() -> void:
	var s: float = root_scale
	if Engine.is_editor_hint():
		s *= EDITOR_PREVIEW_ZOOM
	scale = Vector2.ONE * s


func _apply_look() -> void:
	_ensure_children()
	_apply_root_scale()
	if nuclei:
		nuclei.scale = _nuclei_ppu_scale()
	if orbit0:
		orbit0.scale = _ViewTransform.sprite_scale(ppu_orbit0)
	if orbit1:
		orbit1.scale = _ViewTransform.sprite_scale(ppu_default)
	if orbit2:
		orbit2.scale = _ViewTransform.sprite_scale(ppu_default)
	if orbit_dotted:
		orbit_dotted.scale = _ViewTransform.sprite_scale(ppu_default)
	if arrows:
		for i in range(6):
			var arrow: Sprite2D = arrows.get_node_or_null("Arrow%d" % i) as Sprite2D
			if arrow == null:
				continue
			arrow.modulate = arrow_color
			arrow.scale = _ViewTransform.sprite_scale(ppu_arrow)
	for s in _parked_pool:
		if s is Sprite2D:
			s.modulate = neutron_color
			s.scale = _ViewTransform.sprite_scale(ppu_default)


func _apply_preview_pose() -> void:
	if not Engine.is_editor_hint():
		return
	_apply_look()
	orbit0.visible = false
	orbit1.visible = false
	orbit2.visible = false
	orbit_dotted.visible = false
	arrows.visible = false
	if parked_root:
		parked_root.visible = true
	match preview_pose:
		PreviewPose.CATCHING:
			orbit_dotted.visible = true
			nuclei.modulate = nuclei_default
			_hide_all_parked()
		PreviewPose.MOVABLE:
			_pose_idle_orbits()
			arrows.visible = true
			nuclei.modulate = nuclei_default
			_pose_idle_parked()
		PreviewPose.ENTANGLED:
			_pose_idle_orbits()
			nuclei.modulate = group_1
			_pose_idle_parked()
		_:
			_pose_idle_orbits()
			nuclei.modulate = nuclei_default
			_pose_idle_parked()


func _pose_idle_orbits() -> void:
	orbit1.visible = true


func _hide_all_parked() -> void:
	for s in _parked_pool:
		s.visible = false


func _pose_idle_parked() -> void:
	var radius: float = _SimConstants.ORBIT_MID
	while _parked_pool.size() < PREVIEW_DIRS.size():
		var s := Sprite2D.new()
		s.texture = TEX_NEUTRON
		parked_root.add_child(s)
		_parked_pool.append(s)
	for s in _parked_pool:
		s.visible = false
		s.modulate = neutron_color
		s.scale = _ViewTransform.sprite_scale(ppu_default)
	for i in range(PREVIEW_DIRS.size()):
		var raw: Vector2 = _HexGrid.direction_vector(PREVIEW_DIRS[i])
		var sprite: Sprite2D = _parked_pool[i]
		sprite.position = _ViewTransform.logic_to_view(raw.normalized() * radius)
		sprite.visible = true
