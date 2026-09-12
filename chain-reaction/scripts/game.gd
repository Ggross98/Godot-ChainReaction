extends Node2D

const _GameSession := preload("res://scripts/app/game_session.gd")
const _GameLaunch := preload("res://scripts/app/game_launch.gd")
const _ViewTransform := preload("res://scripts/view/view_transform.gd")
const _I18n := preload("res://scripts/app/i18n.gd")
const _UiButtonStyle := preload("res://scripts/app/ui_button_style.gd")
const _UiStepBalls := preload("res://scripts/app/ui_step_balls.gd")
const FONT_SIZE := 60
const FONT_COLOR := Color(0.123, 0.123, 0.123)
const BOARD_SCREEN_NUDGE_PX := 20.0

@export var tex_sound_on: Texture2D
@export var tex_sound_off: Texture2D
@export var bgm_tracks: Array[AudioStream] = []

var session = _GameSession.new()
var _collapse_epoch: int = -1
var _collapse_i: int = 0
var _step_ball_template: Control

@onready var board: Node2D = $Board
@onready var title_label: Label = $CanvasLayer/HUD/Title
@onready var state_label: Label = $CanvasLayer/HUD/StateInfo
@onready var steps_parent: HBoxContainer = $CanvasLayer/HUD/LeftStepsParent
@onready var map_id_label: Label = $CanvasLayer/HUD/DebugBar/MapId
@onready var pack_button: Button = $CanvasLayer/HUD/DebugBar/Pack
@onready var restart_button: TextureButton = $CanvasLayer/HUD/Buttons/Restart
@onready var home_button: TextureButton = $CanvasLayer/HUD/Buttons/Home
@onready var mute_button: TextureButton = $CanvasLayer/HUD/Buttons/Mute
@onready var prev_button: Button = $CanvasLayer/HUD/DebugBar/Prev
@onready var next_button: Button = $CanvasLayer/HUD/DebugBar/Next
@onready var debug_bar: HBoxContainer = $CanvasLayer/HUD/DebugBar
@onready var map_prev_button: TextureButton = $CanvasLayer/HUD/PrevButton
@onready var map_next_button: TextureButton = $CanvasLayer/HUD/NextButton
@onready var input_shield: Control = $InputShieldLayer/InputShield


func _ready() -> void:
	RenderingServer.set_default_clear_color(_ViewTransform.CLEAR_COLOR)
	_I18n.load_locale("en")
	_style_label(title_label)
	_style_label(state_label)
	_style_label(map_id_label, 28)
	_cache_step_ball_template()
	restart_button.pressed.connect(_on_restart)
	home_button.pressed.connect(_on_home)
	mute_button.pressed.connect(_on_mute)
	_UiButtonStyle.bind_icon(restart_button)
	_UiButtonStyle.bind_icon(mute_button)
	_UiButtonStyle.bind_icon(home_button)
	_UiButtonStyle.bind_icon(map_prev_button, _UiButtonStyle.nav_gray_palette())
	_UiButtonStyle.bind_icon(map_next_button, _UiButtonStyle.nav_gray_palette())
	map_prev_button.pressed.connect(_on_prev)
	map_next_button.pressed.connect(_on_next)
	prev_button.pressed.connect(_on_prev)
	next_button.pressed.connect(_on_next)
	pack_button.visible = false
	debug_bar.visible = _GameLaunch.DEBUG_JUMP
	board.position.y = -BOARD_SCREEN_NUDGE_PX / _ViewTransform.CAMERA_ZOOM
	session.start_pack(_GameLaunch.pack_path, _GameLaunch.map_id)
	_sync_launch()
	_sync_mute_icon()
	_refresh_hud()
	AudioService.play_playlist(bgm_tracks, true)


func _process(dt: float) -> void:
	session.pointer_move(board.pointer_logic())
	session.advance(dt)
	board.sync(session, dt)
	input_shield.visible = board.is_transitioning()
	_drain_collapse()
	_sync_launch()
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if input_shield.visible:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var logic: Vector2 = board.pointer_logic()
		if event.pressed:
			session.pointer_press(logic)
		else:
			session.pointer_release(logic)
		get_viewport().set_input_as_handled()


func _refresh_hud() -> void:
	title_label.text = session.hud_title()
	state_label.text = session.hud_state()
	_sync_step_balls()
	var pack_name := _I18n.t("mode.custom") if session.pack_path() == _GameLaunch.CUSTOM else _I18n.t("mode.campaign")
	map_id_label.text = "%s  %s  %s" % [pack_name, session.map_id(), session.hud_progress()]
	pack_button.text = "Pack"
	_UiButtonStyle.set_icon_enabled(map_prev_button, session.can_goto_prev())
	_UiButtonStyle.set_icon_enabled(map_next_button, session.can_goto_next())


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
			AudioService.play_collapse()


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


func _sync_launch() -> void:
	_GameLaunch.pack_path = session.pack_path()
	_GameLaunch.map_id = session.map_id()


func _sync_mute_icon() -> void:
	mute_button.texture_normal = tex_sound_off if AudioService.muted else tex_sound_on


func _style_label(label: Label, size: int = FONT_SIZE) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", FONT_COLOR)


func _on_restart() -> void:
	session.restart_immediate()


func _on_home() -> void:
	SceneFade.go("res://scenes/main_menu.tscn")


func _on_mute() -> void:
	AudioService.toggle_muted()
	_sync_mute_icon()


func _on_prev() -> void:
	session.goto_prev()
	_sync_launch()


func _on_next() -> void:
	session.goto_next()
	_sync_launch()
