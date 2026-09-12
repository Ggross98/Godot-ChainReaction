extends Node2D

const _I18n := preload("res://scripts/app/i18n.gd")
const _SaveAccount := preload("res://scripts/app/save_account.gd")
const _GameLaunch := preload("res://scripts/app/game_launch.gd")
const _MapLoader := preload("res://scripts/content/map_loader.gd")
const _ViewTransform := preload("res://scripts/view/view_transform.gd")
const FONT := preload("res://assets/fonts/spagi.ttf")
const TEX_SOUND_ON := preload("res://assets/sprites/ui/sound_on.png")
const TEX_SOUND_OFF := preload("res://assets/sprites/ui/sound_off.png")

const FONT_SIZE := 60
const FONT_COLOR := Color(0.123, 0.123, 0.123)
const GRID_COLUMNS := 8
const CELL_SIZE := Vector2(88, 88)

var _campaign_mode: bool = true
var _campaign_pack = null
var _custom_pack = null

@onready var title_label: Label = $CanvasLayer/HUD/Title
@onready var mode_button: Button = $CanvasLayer/HUD/Mode
@onready var mute_button: TextureButton = $CanvasLayer/HUD/Buttons/Mute
@onready var exit_button: TextureButton = $CanvasLayer/HUD/Buttons/Exit
@onready var campaign_grid: GridContainer = $CanvasLayer/HUD/CampaignGrid
@onready var custom_grid: GridContainer = $CanvasLayer/HUD/CustomGrid


func _ready() -> void:
	RenderingServer.set_default_clear_color(_ViewTransform.CLEAR_COLOR)
	_I18n.load_locale("en")
	_SaveAccount.path = _SaveAccount.DEFAULT_PATH
	_SaveAccount.load_from_disk()
	_style_label(title_label)
	title_label.text = _I18n.t("menu.title")
	mode_button.add_theme_font_override("font", FONT)
	mode_button.add_theme_font_size_override("font_size", 40)
	mode_button.add_theme_color_override("font_color", FONT_COLOR)
	mode_button.pressed.connect(_on_mode)
	mute_button.pressed.connect(_on_mute)
	exit_button.pressed.connect(_on_exit)
	_load_packs()
	_rebuild_grids()
	_refresh_mode()
	_sync_mute_icon()


func _load_packs() -> void:
	var campaign = _MapLoader.new().load_pack_file(_GameLaunch.CAMPAIGN)
	if campaign.ok:
		_campaign_pack = campaign.pack
	var custom = _MapLoader.new().load_pack_file(_GameLaunch.CUSTOM)
	if custom.ok:
		_custom_pack = custom.pack


func _rebuild_grids() -> void:
	_fill_grid(campaign_grid, _campaign_pack, true)
	_fill_grid(custom_grid, _custom_pack, false)


func _fill_grid(grid: GridContainer, pack, is_campaign: bool) -> void:
	for child in grid.get_children():
		child.queue_free()
	if pack == null:
		return
	var count: int = pack.maps.size()
	for i in range(count):
		var state := _SaveAccount.STATE_CLEARED
		if is_campaign:
			state = _SaveAccount.campaign_cell_state(i, count)
		var btn := Button.new()
		btn.custom_minimum_size = CELL_SIZE
		btn.text = str(i + 1)
		btn.add_theme_font_override("font", FONT)
		btn.add_theme_font_size_override("font_size", 32)
		btn.add_theme_color_override("font_color", FONT_COLOR)
		var playable := _SaveAccount.is_playable(is_campaign, i, count)
		btn.disabled = not playable
		_paint_cell(btn, state, playable)
		var map_id: String = pack.maps[i].id
		var pack_path: String = _GameLaunch.CAMPAIGN if is_campaign else _GameLaunch.CUSTOM
		btn.pressed.connect(_on_cell.bind(pack_path, map_id))
		grid.add_child(btn)


func _paint_cell(btn: Button, state: String, playable: bool) -> void:
	var color := Color(0.78, 0.78, 0.82)
	if playable:
		color = _SaveAccount.cell_color(state)
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(10)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", box)
	btn.add_theme_stylebox_override("hover", box)
	btn.add_theme_stylebox_override("pressed", box)
	btn.add_theme_stylebox_override("disabled", box)


func _refresh_mode() -> void:
	if _campaign_mode:
		mode_button.text = _I18n.t("mode.campaign")
		campaign_grid.visible = true
		custom_grid.visible = false
	else:
		mode_button.text = _I18n.t("mode.custom")
		campaign_grid.visible = false
		custom_grid.visible = true


func _sync_mute_icon() -> void:
	mute_button.texture_normal = TEX_SOUND_OFF if AudioService.muted else TEX_SOUND_ON


func _style_label(label: Label, size: int = FONT_SIZE) -> void:
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", FONT_COLOR)


func _on_mode() -> void:
	_campaign_mode = not _campaign_mode
	_refresh_mode()


func _on_mute() -> void:
	AudioService.toggle_muted()
	_sync_mute_icon()


func _on_exit() -> void:
	get_tree().quit()


func _on_cell(pack_path: String, map_id: String) -> void:
	_GameLaunch.pack_path = pack_path
	_GameLaunch.map_id = map_id
	get_tree().change_scene_to_file("res://scenes/game.tscn")
