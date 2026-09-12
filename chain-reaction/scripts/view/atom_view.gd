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

const COLLAPSE_TIME := 0.2
const HOVER_SCALE := 1.1
const NEUTRON_COLOR := Color(1.0, 0.733, 0.0)

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


func _ready() -> void:
	_ensure_children()


func _ensure_children() -> void:
	if nuclei != null:
		return
	scale = Vector2.ONE * _ViewTransform.ATOM_ROOT_SCALE
	nuclei = _make_sprite("Nuclei", TEX_NUCLEI, _ViewTransform.PPU_DEFAULT)
	orbit0 = _make_sprite("Orbit0", TEX_ORBIT0, _ViewTransform.PPU_ORBIT0)
	orbit1 = _make_sprite("Orbit1", TEX_ORBIT1, _ViewTransform.PPU_DEFAULT)
	orbit2 = _make_sprite("Orbit2", TEX_ORBIT2, _ViewTransform.PPU_DEFAULT)
	orbit_dotted = _make_sprite("OrbitDotted", TEX_ORBIT_DOTTED, _ViewTransform.PPU_DEFAULT)
	parked_root = Node2D.new()
	parked_root.name = "Parked"
	add_child(parked_root)
	arrows = Node2D.new()
	arrows.name = "Arrows"
	add_child(arrows)
	for i in range(6):
		var arrow := _make_sprite("Arrow%d" % i, TEX_ARROW, _ViewTransform.PPU_ARROW, arrows)
		arrow.rotation = float(i) * TAU / 6.0
		arrow.flip_h = true
		arrow.modulate = Color(0.467, 0.482, 0.498)
	move_child(nuclei, get_child_count() - 1)


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
	nuclei.scale = _nuclei_ppu_scale(HOVER_SCALE if hovering else 1.0)
	_refresh_orbits(atom, behavior)
	_refresh_parked(atom)
	arrows.visible = behavior.can_drag()


func last_solid_orbit() -> Sprite2D:
	if orbit2.visible:
		return orbit2
	if orbit0.visible:
		return orbit0
	return orbit1


func atom_width(_atom) -> int:
	return _board_w


func atom_height(_atom) -> int:
	return _board_h


var _board_w: int = 1
var _board_h: int = 1


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
	var k: float = clampf(1.0 - _collapse_t / COLLAPSE_TIME, 0.0, 1.0)
	nuclei.scale = _nuclei_ppu_scale(k)
	if _collapse_t >= COLLAPSE_TIME:
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
		s.scale = _ViewTransform.sprite_scale(_ViewTransform.PPU_DEFAULT)
		s.modulate = NEUTRON_COLOR
		parked_root.add_child(s)
		_parked_pool.append(s)
	for s in _parked_pool:
		s.visible = false
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
	return _ViewTransform.sprite_scale(_ViewTransform.PPU_DEFAULT) * mult


func _group_color(group: int, highlight: bool) -> Color:
	match group:
		1:
			return Color8(130, 130, 180) if highlight else Color8(83, 33, 180)
		2:
			return Color8(180, 130, 130) if highlight else Color8(180, 83, 33)
		3:
			return Color8(130, 180, 130) if highlight else Color8(33, 180, 83)
		_:
			return Color8(77, 77, 77) if highlight else Color8(33, 33, 33)
