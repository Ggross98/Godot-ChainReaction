extends CanvasLayer

const _ViewTransform := preload("res://scripts/view/view_transform.gd")

const FADE_SECONDS := 0.15

enum Phase { IDLE, COVERING, SWAP, REVEALING }

var _phase: int = Phase.IDLE
var _t: float = 0.0
var _pending_path: String = ""
var _fade: ColorRect
var _swallow: Control


func _ready() -> void:
	layer = 128
	_ensure()
	_apply_busy()


func go(scene_path: String) -> void:
	_ensure()
	if scene_path.is_empty():
		return
	_pending_path = scene_path
	if _phase == Phase.IDLE:
		_phase = Phase.COVERING
		_t = 0.0
	elif _phase == Phase.REVEALING:
		var k: float = 0.0 if FADE_SECONDS <= 0.0 else clampf(_t / FADE_SECONDS, 0.0, 1.0)
		var alpha: float = 1.0 - k
		_phase = Phase.COVERING
		_t = alpha * FADE_SECONDS
	_apply_busy()


func is_busy() -> bool:
	return _phase != Phase.IDLE


func _process(dt: float) -> void:
	_ensure()
	if _phase == Phase.IDLE:
		return
	if _phase == Phase.COVERING:
		_t += dt
		var k: float = 1.0 if FADE_SECONDS <= 0.0 else clampf(_t / FADE_SECONDS, 0.0, 1.0)
		_set_alpha(k)
		if k >= 1.0:
			_swap()
	elif _phase == Phase.REVEALING:
		_t += dt
		var k: float = 1.0 if FADE_SECONDS <= 0.0 else clampf(_t / FADE_SECONDS, 0.0, 1.0)
		_set_alpha(1.0 - k)
		if k >= 1.0:
			_phase = Phase.IDLE
			_set_alpha(0.0)
			_apply_busy()


func _swap() -> void:
	var path := _pending_path
	_pending_path = ""
	if not path.is_empty() and is_inside_tree():
		get_tree().change_scene_to_file(path)
	_phase = Phase.REVEALING
	_t = 0.0
	_set_alpha(1.0)
	_apply_busy()


func _ensure() -> void:
	if _fade != null:
		return
	_swallow = Control.new()
	_swallow.name = "Swallow"
	_swallow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_swallow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_swallow)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	var fill := _ViewTransform.CLEAR_COLOR
	fill.a = 0.0
	_fade.color = fill
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _set_alpha(alpha: float) -> void:
	if _fade == null:
		return
	var fill: Color = _fade.color
	fill.a = clampf(alpha, 0.0, 1.0)
	_fade.color = fill


func _apply_busy() -> void:
	_ensure()
	var filter: Control.MouseFilter = Control.MOUSE_FILTER_STOP if is_busy() else Control.MOUSE_FILTER_IGNORE
	_swallow.mouse_filter = filter
	_fade.mouse_filter = filter
