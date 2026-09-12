@tool
class_name NeutronView
extends Node2D

const _ViewTransform := preload("res://scripts/view/view_transform.gd")
const EDITOR_PREVIEW_ZOOM := 108.0

enum PreviewPose { IDLE, CATCHING, MOVABLE, ENTANGLED }

@export_group("Preview")
@export var preview_pose: PreviewPose = PreviewPose.IDLE:
	set(value):
		preview_pose = value
		_on_look_changed()

@export_group("Textures")
@export var tex_neutron: Texture2D

@export_group("Look")
@export var neutron_color := Color(1.0, 0.733, 0.0):
	set(value):
		neutron_color = value
		_on_look_changed()
@export var ppu_default: float = 128.0:
	set(value):
		ppu_default = maxf(value, 1.0)
		_on_look_changed()
@export var root_scale: float = 1.0:
	set(value):
		root_scale = value
		_on_look_changed()

@export_group("Trail")
@export var trace_count: int = 10:
	set(value):
		trace_count = maxi(value, 1)
		_on_look_changed()
@export var trace_interval: float = 0.02:
	set(value):
		trace_interval = maxf(value, 0.001)
@export var trace_alpha0: float = 0.5:
	set(value):
		trace_alpha0 = value
		_on_look_changed()
@export var trace_alpha1: float = 0.1:
	set(value):
		trace_alpha1 = value
		_on_look_changed()
@export var trace_scale0: float = 0.8:
	set(value):
		trace_scale0 = value
		_on_look_changed()
@export var trace_scale1: float = 0.2:
	set(value):
		trace_scale1 = value
		_on_look_changed()

var neutron_id: int = -1
var tracing: bool = false
var body: Sprite2D
var _ghosts: Array = []
var _history: Array = []
var _acc: float = 0.0
var _look_ready: bool = false


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
	if body != null:
		_ensure_ghost_count()
		return
	body = get_node_or_null("Body") as Sprite2D
	if body != null:
		_ghosts.clear()
		var i := 0
		while true:
			var g: Sprite2D = get_node_or_null("Ghost%d" % i) as Sprite2D
			if g == null:
				break
			_ghosts.append(g)
			i += 1
		_ensure_ghost_count()
		return
	_create_fallback_children()


func _create_fallback_children() -> void:
	body = Sprite2D.new()
	body.name = "Body"
	body.texture = tex_neutron
	body.scale = _ViewTransform.sprite_scale(ppu_default)
	body.modulate = neutron_color
	add_child(body)
	_ghosts.clear()
	_ensure_ghost_count()


func _ensure_ghost_count() -> void:
	while _ghosts.size() < trace_count:
		var g := Sprite2D.new()
		g.name = "Ghost%d" % _ghosts.size()
		g.texture = _neutron_texture()
		g.scale = _ViewTransform.sprite_scale(ppu_default)
		g.modulate = neutron_color
		g.visible = false
		g.z_index = -1
		add_child(g)
		_ghosts.append(g)


func begin_trace() -> void:
	tracing = true
	_history.clear()
	_acc = 0.0
	_ensure_children()
	for g in _ghosts:
		g.visible = false


func hide_trace() -> void:
	tracing = false
	_history.clear()
	for g in _ghosts:
		g.visible = false


func sync(logic_pos: Vector2, dt: float) -> void:
	if Engine.is_editor_hint():
		return
	_ensure_children()
	position = _ViewTransform.logic_to_view(logic_pos)
	visible = true
	body.modulate = neutron_color
	body.scale = _ViewTransform.sprite_scale(ppu_default)
	if not tracing:
		return
	_acc += dt
	while _acc >= trace_interval:
		_acc -= trace_interval
		_history.push_front(logic_pos)
		if _history.size() > trace_count:
			_history.resize(trace_count)
	_refresh_ghosts()


func _refresh_ghosts() -> void:
	var n: int = mini(trace_count, _ghosts.size())
	for i in range(_ghosts.size()):
		var g: Sprite2D = _ghosts[i]
		if i >= n or i >= _history.size():
			g.visible = false
			continue
		var t: float = 0.0 if n <= 1 else float(i) / float(n - 1)
		var hist: Vector2 = _history[i]
		g.position = _ViewTransform.logic_to_view(hist) - position
		g.visible = true
		var alpha: float = lerpf(trace_alpha0, trace_alpha1, t)
		g.modulate = Color(neutron_color.r, neutron_color.g, neutron_color.b, alpha)
		var sc: float = lerpf(trace_scale0, trace_scale1, t)
		g.scale = _ViewTransform.sprite_scale(ppu_default) * sc


func _neutron_texture() -> Texture2D:
	if tex_neutron:
		return tex_neutron
	if body:
		return body.texture
	return null


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
	if body:
		body.modulate = neutron_color
		body.scale = _ViewTransform.sprite_scale(ppu_default)
	for g in _ghosts:
		g.texture = _neutron_texture()
		g.scale = _ViewTransform.sprite_scale(ppu_default)
		if not tracing:
			g.visible = false
			g.modulate = neutron_color


func _apply_preview_pose() -> void:
	if not Engine.is_editor_hint():
		return
	_apply_look()
	for g in _ghosts:
		g.visible = false
	var show_trail: bool = preview_pose == PreviewPose.MOVABLE or preview_pose == PreviewPose.ENTANGLED
	if not show_trail:
		return
	var n: int = mini(3, _ghosts.size())
	for i in range(n):
		var t: float = 0.0 if n <= 1 else float(i) / float(n - 1)
		var g: Sprite2D = _ghosts[i]
		g.visible = true
		g.position = Vector2(-(i + 1) * 0.15, 0.0)
		var alpha: float = lerpf(trace_alpha0, trace_alpha1, t)
		g.modulate = Color(neutron_color.r, neutron_color.g, neutron_color.b, alpha)
		g.scale = _ViewTransform.sprite_scale(ppu_default) * lerpf(trace_scale0, trace_scale1, t)
