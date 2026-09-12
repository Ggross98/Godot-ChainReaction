extends Node

const SE_PATH := "res://assets/audio/se/bop2.mp3"
const MAX_SE := 3
const MUTE_DB := -80.0
const PLAY_DB := 0.0

enum Phase { IDLE, PLAYING, FADING, WAITING }

@export var fade_seconds: float = 1.0
@export var gap_seconds: float = 2.0

var muted: bool = false
var rng := RandomNumberGenerator.new()
var se_starts: int = 0

var _bgm: AudioStreamPlayer
var _se_players: Array = []
var _unmuted_db: float = 0.0
var _se_stream: AudioStream
var _phase: int = Phase.IDLE
var _queue: Array = []
var _index: int = 0
var _pending_tracks: Array = []
var _pending_shuffle: bool = false
var _has_pending: bool = false
var _pending_skip_gap: bool = false
var _fade_t: float = 0.0
var _fade_from_db: float = PLAY_DB
var _wait_t: float = 0.0
var _se_started_this_tick: bool = false


func _ready() -> void:
	var first: bool = _bgm == null
	_ensure_players()
	if first:
		rng.randomize()


func play_playlist(tracks: Array, shuffle: bool) -> void:
	_ensure_players()
	var clean: Array = _normalize(tracks)
	if _phase == Phase.IDLE:
		_apply_and_start(clean, shuffle)
		return
	_pending_tracks = clean
	_pending_shuffle = shuffle
	_has_pending = true
	_pending_skip_gap = clean.is_empty()
	if _phase == Phase.PLAYING:
		_begin_fade()


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
			_unmuted_db = PLAY_DB
		AudioServer.set_bus_volume_db(bus, MUTE_DB)
	else:
		AudioServer.set_bus_volume_db(bus, _unmuted_db)


func play_collapse() -> void:
	_ensure_players()
	if _se_stream == null or _se_players.is_empty():
		return
	if _se_started_this_tick:
		return
	_se_started_this_tick = true
	se_starts += 1
	var chosen: AudioStreamPlayer = _se_players[0]
	for p in _se_players:
		if not p.playing:
			chosen = p
			break
	chosen.stream = _se_stream
	if chosen.is_inside_tree():
		chosen.play()


func _process(dt: float) -> void:
	_se_started_this_tick = false
	if _bgm == null:
		return
	if _phase == Phase.FADING:
		_fade_t += dt
		var k: float = 1.0 if fade_seconds <= 0.0 else clampf(_fade_t / fade_seconds, 0.0, 1.0)
		_bgm.volume_db = lerpf(_fade_from_db, MUTE_DB, k)
		if k >= 1.0:
			_finish_fade()
	elif _phase == Phase.WAITING:
		_wait_t += dt
		if _wait_t >= gap_seconds:
			_start_pending()


func _ensure_players() -> void:
	if _bgm != null:
		return
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "Bgm"
	add_child(_bgm)
	_bgm.finished.connect(_on_bgm_finished)
	for i in range(MAX_SE):
		var p := AudioStreamPlayer.new()
		p.name = "Se%d" % i
		add_child(p)
		_se_players.append(p)
	if FileAccess.file_exists(SE_PATH):
		_se_stream = load(SE_PATH)


func _normalize(tracks: Array) -> Array:
	var clean: Array = []
	for item in tracks:
		if item is AudioStream:
			clean.append(item)
	return clean


func _apply_and_start(tracks: Array, shuffle: bool) -> void:
	if shuffle:
		_queue = _shuffled(tracks)
	elif tracks.is_empty():
		_queue = []
	else:
		_queue = [tracks[0]]
	_index = 0
	if _queue.is_empty():
		_phase = Phase.IDLE
		_bgm.stop()
		_bgm.stream = null
		_bgm.volume_db = PLAY_DB
		return
	_play_current()


func _shuffled(tracks: Array) -> Array:
	var out: Array = tracks.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


func _play_current() -> void:
	_bgm.volume_db = PLAY_DB
	_bgm.stream = _queue[_index]
	_phase = Phase.PLAYING
	if _bgm.is_inside_tree():
		_bgm.play()


func _begin_fade() -> void:
	if fade_seconds <= 0.0:
		_finish_fade()
		return
	_phase = Phase.FADING
	_fade_t = 0.0
	_fade_from_db = _bgm.volume_db


func _finish_fade() -> void:
	_bgm.stop()
	_bgm.volume_db = PLAY_DB
	if _pending_skip_gap or not _has_pending or _pending_tracks.is_empty():
		_queue.clear()
		_index = 0
		_has_pending = false
		_phase = Phase.IDLE
		_bgm.stream = null
		return
	if gap_seconds <= 0.0:
		_start_pending()
		return
	_phase = Phase.WAITING
	_wait_t = 0.0


func _start_pending() -> void:
	var tracks: Array = _pending_tracks
	var shuffle: bool = _pending_shuffle
	_has_pending = false
	_pending_tracks = []
	_apply_and_start(tracks, shuffle)


func _on_bgm_finished() -> void:
	if _phase != Phase.PLAYING:
		return
	if _queue.is_empty():
		_phase = Phase.IDLE
		return
	_index = (_index + 1) % _queue.size()
	_play_current()
