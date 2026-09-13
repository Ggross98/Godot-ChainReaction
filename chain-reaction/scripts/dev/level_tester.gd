extends Node2D

const _MapLoader := preload("res://scripts/content/map_loader.gd")
const _GameSession := preload("res://scripts/app/game_session.gd")
const _ViewTransform := preload("res://scripts/view/view_transform.gd")
const _UiButtonStyle := preload("res://scripts/app/ui_button_style.gd")
const _UiStepBalls := preload("res://scripts/app/ui_step_balls.gd")

const FONT_SIZE := 60
const FONT_COLOR := Color(0.123, 0.123, 0.123)
const BOARD_SCREEN_NUDGE_PX := 20.0

@export_file("*.json") var level_json: String = ""

var session = _GameSession.new()
var _collapse_epoch: int = -1
var _collapse_i: int = 0
var _step_ball_template: Control

@onready var board: Node2D = $Board
@onready var title_label: Label = $CanvasLayer/HUD/Title
@onready var steps_parent: HBoxContainer = $CanvasLayer/HUD/LeftStepsParent
@onready var restart_button: TextureButton = $CanvasLayer/HUD/Buttons/Restart


func _ready() -> void:
	RenderingServer.set_default_clear_color(_ViewTransform.CLEAR_COLOR)
	_style_label(title_label)
	_cache_step_ball_template()
	restart_button.pressed.connect(_on_restart)
	_UiButtonStyle.bind_icon(restart_button)
	board.position.y = -BOARD_SCREEN_NUDGE_PX / _ViewTransform.CAMERA_ZOOM
	_load_exported_map()
	_refresh_hud()


func _process(dt: float) -> void:
	if session.current_map == null:
		return
	session.pointer_move(board.pointer_logic())
	session.advance(dt)
	board.sync(session, dt)
	_drain_collapse()
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if session.current_map == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var logic: Vector2 = board.pointer_logic()
		if event.pressed:
			session.pointer_press(logic)
		else:
			session.pointer_release(logic)
		get_viewport().set_input_as_handled()


func _load_exported_map() -> void:
	if level_json.strip_edges() == "":
		push_error("LevelTester: no JSON selected")
		title_label.text = "No JSON selected"
		return
	var result = _MapLoader.new().load_map_file(level_json)
	if not result.ok or result.map == null:
		push_error("LevelTester: invalid JSON %s: %s" % [level_json, ",".join(result.errors)])
		title_label.text = "Invalid JSON"
		return
	session.start_map(result.map)


func _refresh_hud() -> void:
	if session.current_map == null:
		return
	title_label.text = session.hud_title()
	_sync_step_balls()


func _drain_collapse() -> void:
	if session == null or session.sim == null:
		return
	if _collapse_epoch != session.board_epoch:
		_collapse_epoch = session.board_epoch
		_collapse_i = 0
	var events: Array = session.sim.events
	while _collapse_i < events.size():
		var ev: String = str(events[_collapse_i])
		_collapse_i += 1
		if ev.begins_with("collapse:"):
			_play_collapse()


func _cache_step_ball_template() -> void:
	if steps_parent.get_child_count() == 0:
		return
	_step_ball_template = steps_parent.get_child(0).duplicate()
	var inner: CanvasItem = _step_ball_template.get_node_or_null("Inner") as CanvasItem
	if inner:
		inner.visible = true


func _sync_step_balls() -> void:
	var initial := 0
	if session.current_map != null:
		initial = session.current_map.steps
	var remaining := 0
	if session.sim != null:
		remaining = session.sim.steps
	_UiStepBalls.sync(steps_parent, _step_ball_template, initial, remaining)


func _style_label(label: Label, size: int = FONT_SIZE) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", FONT_COLOR)


func _on_restart() -> void:
	if session.current_map == null:
		return
	session.restart_immediate()


func _play_collapse() -> void:
	var audio := get_node_or_null("/root/AudioService")
	if audio:
		audio.play_collapse()
