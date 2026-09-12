extends Node2D

const _GameSession := preload("res://scripts/app/game_session.gd")
const _GameLaunch := preload("res://scripts/app/game_launch.gd")
const _ViewTransform := preload("res://scripts/view/view_transform.gd")
const FONT := preload("res://assets/fonts/spagi.ttf")

const FONT_SIZE := 60
const FONT_COLOR := Color(0.123, 0.123, 0.123)

var session = _GameSession.new()

@onready var board: Node2D = $Board
@onready var title_label: Label = $CanvasLayer/HUD/Title
@onready var state_label: Label = $CanvasLayer/HUD/StateInfo
@onready var steps_label: Label = $CanvasLayer/HUD/LeftSteps
@onready var map_id_label: Label = $CanvasLayer/HUD/DebugBar/MapId
@onready var pack_button: Button = $CanvasLayer/HUD/DebugBar/Pack
@onready var restart_button: TextureButton = $CanvasLayer/HUD/Buttons/Restart
@onready var home_button: TextureButton = $CanvasLayer/HUD/Buttons/Home
@onready var prev_button: Button = $CanvasLayer/HUD/DebugBar/Prev
@onready var next_button: Button = $CanvasLayer/HUD/DebugBar/Next


func _ready() -> void:
	RenderingServer.set_default_clear_color(_ViewTransform.CLEAR_COLOR)
	_style_label(title_label)
	_style_label(state_label)
	_style_label(steps_label)
	_style_label(map_id_label, 28)
	restart_button.pressed.connect(_on_restart)
	home_button.pressed.connect(_on_home)
	prev_button.pressed.connect(_on_prev)
	next_button.pressed.connect(_on_next)
	pack_button.pressed.connect(_on_pack)
	session.start_pack(_GameLaunch.pack_path, _GameLaunch.map_id)
	_sync_launch()
	_refresh_hud()


func _process(dt: float) -> void:
	session.pointer_move(board.pointer_logic())
	session.advance(dt)
	board.sync(session, dt)
	_sync_launch()
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
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
	steps_label.text = session.hud_steps()
	var pack_name := "custom" if session.pack_path() == _GameLaunch.CUSTOM else "campaign"
	map_id_label.text = "%s  %s  %s" % [pack_name, session.map_id(), session.hud_progress()]
	pack_button.text = "Pack"


func _sync_launch() -> void:
	_GameLaunch.pack_path = session.pack_path()
	_GameLaunch.map_id = session.map_id()


func _style_label(label: Label, size: int = FONT_SIZE) -> void:
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", FONT_COLOR)


func _on_restart() -> void:
	session.restart_immediate()


func _on_home() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_prev() -> void:
	session.goto_prev()
	_sync_launch()


func _on_next() -> void:
	session.goto_next()
	_sync_launch()


func _on_pack() -> void:
	if session.pack_path() == _GameLaunch.CAMPAIGN:
		_GameLaunch.pack_path = _GameLaunch.CUSTOM
		_GameLaunch.map_id = "relay-race"
	else:
		_GameLaunch.pack_path = _GameLaunch.CAMPAIGN
		_GameLaunch.map_id = "1-1"
	session.start_pack(_GameLaunch.pack_path, _GameLaunch.map_id)
	_sync_launch()
