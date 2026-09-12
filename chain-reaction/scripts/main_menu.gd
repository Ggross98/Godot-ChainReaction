extends Node2D

const _I18n := preload("res://scripts/app/i18n.gd")
const _SaveAccount := preload("res://scripts/app/save_account.gd")
const _GameLaunch := preload("res://scripts/app/game_launch.gd")
const _MapLoader := preload("res://scripts/content/map_loader.gd")
const _ViewTransform := preload("res://scripts/view/view_transform.gd")
const _UiButtonStyle := preload("res://scripts/app/ui_button_style.gd")
const FONT_SIZE := 60
const FONT_COLOR := Color(0.123, 0.123, 0.123)
const CELL_SIZE := Vector2(88, 88)

@export var tex_sound_on: Texture2D
@export var tex_sound_off: Texture2D
@export var bgm_tracks: Array[AudioStream] = []

var _campaign_pack = null

@onready var title_label: Label = $CanvasLayer/HUD/Title
@onready var mute_button: TextureButton = $CanvasLayer/HUD/Buttons/Mute
@onready var exit_button: TextureButton = $CanvasLayer/HUD/Buttons/Exit
@onready var campaign_grid: GridContainer = $CanvasLayer/HUD/CampaignGrid


func _ready() -> void:
	RenderingServer.set_default_clear_color(_ViewTransform.CLEAR_COLOR)
	_I18n.load_locale("en")
	_SaveAccount.path = _SaveAccount.DEFAULT_PATH
	_SaveAccount.load_from_disk()
	_style_label(title_label)
	title_label.text = _I18n.t("menu.title")
	mute_button.pressed.connect(_on_mute)
	exit_button.pressed.connect(_on_exit)
	_UiButtonStyle.bind_icon(mute_button)
	_UiButtonStyle.bind_icon(exit_button)
	_load_packs()
	_rebuild_grid()
	_sync_mute_icon()
	AudioService.play_playlist(bgm_tracks, false)


func _load_packs() -> void:
	var campaign = _MapLoader.new().load_pack_file(_GameLaunch.CAMPAIGN)
	if campaign.ok:
		_campaign_pack = campaign.pack


func _rebuild_grid() -> void:
	for child in campaign_grid.get_children():
		child.queue_free()
	if _campaign_pack == null:
		return
	var count: int = _campaign_pack.maps.size()
	for i in range(count):
		var state := _SaveAccount.campaign_cell_state(i, count)
		var btn := Button.new()
		btn.custom_minimum_size = CELL_SIZE
		btn.text = str(i + 1)
		btn.add_theme_font_size_override("font_size", 32)
		btn.add_theme_color_override("font_color", FONT_COLOR)
		var playable := _SaveAccount.is_playable(true, i, count)
		btn.disabled = not playable
		_UiButtonStyle.apply_cell(btn, _SaveAccount.cell_color(state), playable)
		var map_id: String = _campaign_pack.maps[i].id
		btn.pressed.connect(_on_cell.bind(map_id))
		campaign_grid.add_child(btn)


func _sync_mute_icon() -> void:
	mute_button.texture_normal = tex_sound_off if AudioService.muted else tex_sound_on


func _style_label(label: Label, size: int = FONT_SIZE) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", FONT_COLOR)


func _on_mute() -> void:
	AudioService.toggle_muted()
	_sync_mute_icon()


func _on_exit() -> void:
	get_tree().quit()


func _on_cell(map_id: String) -> void:
	_GameLaunch.pack_path = _GameLaunch.CAMPAIGN
	_GameLaunch.map_id = map_id
	get_tree().change_scene_to_file("res://scenes/game.tscn")
