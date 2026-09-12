extends Node

const BGM_DIR := "res://assets/audio/bgm"
const SE_PATH := "res://assets/audio/se/bop2.mp3"
const MAX_SE := 3
const MUTE_DB := -80.0

var muted: bool = false
var _bgm: AudioStreamPlayer
var _se_players: Array = []
var _playlist: Array = []
var _bgm_index: int = 0
var _unmuted_db: float = 0.0
var _se_stream: AudioStream
var _awaiting_bgm_end: bool = false


func _ready() -> void:
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "Bgm"
	add_child(_bgm)
	for i in range(MAX_SE):
		var p := AudioStreamPlayer.new()
		p.name = "Se%d" % i
		add_child(p)
		_se_players.append(p)
	_load_playlist()
	if FileAccess.file_exists(SE_PATH):
		_se_stream = load(SE_PATH)
	start_bgm()


func start_bgm() -> void:
	if _playlist.is_empty():
		return
	_play_index(_bgm_index)


func toggle_muted() -> bool:
	set_muted(not muted)
	return muted


func set_muted(on: bool) -> void:
	muted = on
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	if on:
		_unmuted_db = AudioServer.get_bus_volume_db(bus)
		if _unmuted_db <= MUTE_DB:
			_unmuted_db = 0.0
		AudioServer.set_bus_volume_db(bus, MUTE_DB)
	else:
		AudioServer.set_bus_volume_db(bus, _unmuted_db)


func play_collapse() -> void:
	if _se_stream == null or _se_players.is_empty():
		return
	var chosen: AudioStreamPlayer = _se_players[0]
	for p in _se_players:
		if not p.playing:
			chosen = p
			break
	chosen.stream = _se_stream
	chosen.play()


func _process(_dt: float) -> void:
	if _playlist.is_empty() or _bgm == null:
		return
	if _awaiting_bgm_end and not _bgm.playing:
		_bgm_index = (_bgm_index + 1) % _playlist.size()
		_play_index(_bgm_index)


func _play_index(i: int) -> void:
	if i < 0 or i >= _playlist.size():
		_awaiting_bgm_end = false
		return
	_bgm.stream = _playlist[i]
	_bgm.play()
	_awaiting_bgm_end = true


func _load_playlist() -> void:
	_playlist.clear()
	var dir := DirAccess.open(BGM_DIR)
	if dir == null:
		return
	var names: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if not dir.current_is_dir():
			var ext := n.get_extension().to_lower()
			if ext == "ogg" or ext == "mp3" or ext == "wav":
				names.append(n)
		n = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for file_name in names:
		var stream = load("%s/%s" % [BGM_DIR, file_name])
		if stream is AudioStream:
			_playlist.append(stream)
