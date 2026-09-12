class_name NeutronView
extends Node2D

const _ViewTransform := preload("res://scripts/view/view_transform.gd")
const TEX_NEUTRON := preload("res://assets/sprites/Neutron0.png")
const NEUTRON_COLOR := Color(1.0, 0.733, 0.0)
const TRACE_COUNT := 10
const TRACE_INTERVAL := 0.02
const TRACE_ALPHA0 := 0.5
const TRACE_ALPHA1 := 0.1
const TRACE_SCALE0 := 0.8
const TRACE_SCALE1 := 0.2

var neutron_id: int = -1
var tracing: bool = false
var body: Sprite2D
var _ghosts: Array = []
var _history: Array = []
var _acc: float = 0.0


func _ready() -> void:
	_ensure_children()


func _ensure_children() -> void:
	if body != null:
		return
	body = Sprite2D.new()
	body.name = "Body"
	body.texture = TEX_NEUTRON
	body.scale = _ViewTransform.sprite_scale()
	body.modulate = NEUTRON_COLOR
	add_child(body)
	for i in range(TRACE_COUNT):
		var g := Sprite2D.new()
		g.texture = TEX_NEUTRON
		g.scale = _ViewTransform.sprite_scale()
		g.modulate = NEUTRON_COLOR
		g.visible = false
		g.z_index = -1
		add_child(g)
		_ghosts.append(g)


func begin_trace() -> void:
	tracing = true
	_history.clear()
	_acc = 0.0
	for g in _ghosts:
		g.visible = false


func hide_trace() -> void:
	tracing = false
	_history.clear()
	for g in _ghosts:
		g.visible = false


func sync(logic_pos: Vector2, dt: float) -> void:
	_ensure_children()
	position = _ViewTransform.logic_to_view(logic_pos)
	visible = true
	if not tracing:
		return
	_acc += dt
	while _acc >= TRACE_INTERVAL:
		_acc -= TRACE_INTERVAL
		_history.push_front(logic_pos)
		if _history.size() > TRACE_COUNT:
			_history.resize(TRACE_COUNT)
	_refresh_ghosts()


func _refresh_ghosts() -> void:
	for i in range(TRACE_COUNT):
		var g: Sprite2D = _ghosts[i]
		if i >= _history.size():
			g.visible = false
			continue
		var t: float = 0.0 if TRACE_COUNT <= 1 else float(i) / float(TRACE_COUNT - 1)
		var hist: Vector2 = _history[i]
		g.position = _ViewTransform.logic_to_view(hist) - position
		g.visible = true
		var alpha: float = lerpf(TRACE_ALPHA0, TRACE_ALPHA1, t)
		g.modulate = Color(NEUTRON_COLOR.r, NEUTRON_COLOR.g, NEUTRON_COLOR.b, alpha)
		var sc: float = lerpf(TRACE_SCALE0, TRACE_SCALE1, t)
		g.scale = _ViewTransform.sprite_scale() * sc
