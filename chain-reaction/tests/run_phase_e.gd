extends SceneTree

const _I18n := preload("res://scripts/app/i18n.gd")
const _HudStrings := preload("res://scripts/app/hud_strings.gd")
const _SaveAccount := preload("res://scripts/app/save_account.gd")
const _GameLaunch := preload("res://scripts/app/game_launch.gd")
const _GameSession := preload("res://scripts/app/game_session.gd")
const _Simulation := preload("res://scripts/core/simulation.gd")

const TEST_PATH := "user://phase_e_test.cfg"

var _failures: int = 0
var _saved_path: String = ""


func _init() -> void:
	print("=== Phase E tests ===")
	_saved_path = _SaveAccount.path
	_SaveAccount.path = TEST_PATH
	_delete_test_file()
	_SaveAccount.reset_memory()
	_test_i18n()
	_test_empty_unlock()
	_test_cleared_unlocks_next()
	_test_custom_playable()
	_test_save_roundtrip()
	_test_custom_win_does_not_persist()
	_test_campaign_win_persists()
	_test_mute()
	_test_bgm_playlists()
	_test_se_same_tick_coalesce()
	_test_ui_hover_styles()
	_test_debug_jump_off()
	_delete_test_file()
	_SaveAccount.path = _saved_path
	_SaveAccount.reset_memory()
	print("=== %d failure(s) ===" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  OK   %s" % msg)
	else:
		_failures += 1
		print("  FAIL %s" % msg)


func _delete_test_file() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _test_i18n() -> void:
	print("-- i18n")
	_check(_I18n.load_locale("en"), "loads en")
	_check(_I18n.t("hud.left_steps").contains("{n}"), "hud.left_steps template has {n}")
	_check(_I18n.t("hud.left_steps", {"n": 4}) == "Left Steps : 4", "left_steps substitutes n")
	_check(_I18n.t("hud.completed") == "Completed!", "hud.completed")
	_check(_I18n.t("hud.failed") == "Failed!", "hud.failed")
	_check(_I18n.t("mode.campaign") == "Campaign", "mode.campaign")
	_check(_I18n.t("mode.custom") == "Custom", "mode.custom")
	_check(_HudStrings.COMPLETED == _I18n.t("hud.completed"), "HudStrings.COMPLETED uses table")
	_check(_HudStrings.left_steps(2) == "Left Steps : 2", "HudStrings.left_steps")
	for key in ["mode.campaign", "mode.custom", "hud.left_steps", "hud.completed", "hud.failed", "menu.exit"]:
		_check(_I18n.t(key) != key, "key exists: %s" % key)


func _test_empty_unlock() -> void:
	print("-- empty unlock")
	var empty: Array = []
	_check(_SaveAccount.campaign_cell_state(0, 40, empty) == _SaveAccount.STATE_UNLOCKED, "index 0 unlocked")
	_check(_SaveAccount.campaign_cell_state(1, 40, empty) == _SaveAccount.STATE_UNLOCKED, "index 1 unlocked")
	_check(_SaveAccount.campaign_cell_state(2, 40, empty) == _SaveAccount.STATE_UNLOCKED, "index 2 unlocked")
	_check(_SaveAccount.campaign_cell_state(3, 40, empty) == _SaveAccount.STATE_LOCKED, "index 3 locked")
	_check(_SaveAccount.is_playable(true, 0, 40, empty), "0 playable")
	_check(_SaveAccount.is_playable(true, 2, 40, empty), "2 playable")
	_check(not _SaveAccount.is_playable(true, 3, 40, empty), "3 not playable")


func _test_cleared_unlocks_next() -> void:
	print("-- cleared unlocks next")
	_SaveAccount.reset_memory()
	_SaveAccount.mark_cleared(0)
	_check(_SaveAccount.campaign_cell_state(0, 40) == _SaveAccount.STATE_CLEARED, "0 cleared color state")
	_check(_SaveAccount.campaign_cell_state(3, 40) == _SaveAccount.STATE_UNLOCKED, "3 unlocked after clearing 0")
	_check(_SaveAccount.is_playable(true, 3, 40), "3 playable after clearing 0")
	_check(_SaveAccount.cell_color(_SaveAccount.STATE_CLEARED).is_equal_approx(Color(0.10, 0.63, 0.60)), "cleared color")
	_check(_SaveAccount.cell_color(_SaveAccount.STATE_UNLOCKED).is_equal_approx(Color(0.62, 0.90, 0.94)), "unlocked color")


func _test_custom_playable() -> void:
	print("-- custom playable")
	_check(_SaveAccount.is_playable(false, 0, 2, []), "custom 0 playable")
	_check(_SaveAccount.is_playable(false, 1, 2, []), "custom 1 playable")


func _test_save_roundtrip() -> void:
	print("-- save roundtrip")
	_delete_test_file()
	_SaveAccount.path = TEST_PATH
	_SaveAccount.reset_memory()
	_SaveAccount.mark_cleared(0)
	_SaveAccount.mark_cleared(5)
	_check(FileAccess.file_exists(TEST_PATH), "wrote test cfg")
	_SaveAccount.reset_memory()
	_check(_SaveAccount.cleared.is_empty(), "memory cleared")
	_SaveAccount.load_from_disk()
	_check(_SaveAccount.cleared.has(0) and _SaveAccount.cleared.has(5), "loaded cleared indices")


func _test_custom_win_does_not_persist() -> void:
	print("-- custom win does not persist")
	_delete_test_file()
	_SaveAccount.path = TEST_PATH
	_SaveAccount.reset_memory()
	var session = _GameSession.new()
	_check(session.start_pack(_GameLaunch.CUSTOM, "relay-race"), "loads custom")
	session.sim.state = _Simulation.STATE_WIN
	session._resolve_outcome()
	_check(not FileAccess.file_exists(TEST_PATH), "custom win did not write disk")
	_check(_SaveAccount.cleared.is_empty(), "custom win did not mark memory")


func _test_campaign_win_persists() -> void:
	print("-- campaign win persists")
	_delete_test_file()
	_SaveAccount.path = TEST_PATH
	_SaveAccount.reset_memory()
	var session = _GameSession.new()
	_check(session.start_pack(_GameLaunch.CAMPAIGN, "1-1"), "loads 1-1")
	session.sim.state = _Simulation.STATE_WIN
	session._resolve_outcome()
	_check(FileAccess.file_exists(TEST_PATH), "campaign win wrote disk")
	_SaveAccount.reset_memory()
	_SaveAccount.load_from_disk()
	_check(_SaveAccount.cleared.has(0), "campaign index 0 saved")


func _test_mute() -> void:
	print("-- mute")
	var project := FileAccess.get_file_as_string("res://project.godot")
	_check(project.contains("AudioService="), "AudioService registered as Autoload")
	var audio = preload("res://scripts/app/audio_service.gd").new()
	var bus := AudioServer.get_bus_index("Master")
	_check(bus >= 0, "master bus exists")
	var before := AudioServer.get_bus_volume_db(bus)
	audio.set_muted(true)
	_check(audio.muted, "muted flag")
	_check(AudioServer.get_bus_volume_db(bus) <= -79.0, "master bus near silent")
	audio.set_muted(false)
	_check(not audio.muted, "unmuted flag")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(bus), before) or AudioServer.get_bus_volume_db(bus) > -1.0, "master bus restored")
	audio.free()


func _test_bgm_playlists() -> void:
	print("-- bgm playlists")
	var project := FileAccess.get_file_as_string("res://project.godot")
	_check(project.contains("AudioService=\"*res://scenes/audio_service.tscn\""), "autoload is audio_service scene")
	var src := FileAccess.get_file_as_string("res://scripts/app/audio_service.gd")
	_check(src.find("BGM_DIR") == -1, "does not scan BGM folder")
	_check(FileAccess.get_file_as_string("res://scripts/main_menu.gd").contains("play_playlist(bgm_tracks, false)"), "menu requests unshuffled playlist")
	_check(FileAccess.get_file_as_string("res://scripts/game.gd").contains("play_playlist(bgm_tracks, true)"), "game requests shuffled playlist")
	_test_bgm_empty()
	_test_bgm_loop_first()
	_test_bgm_shuffle_cycle()
	_test_bgm_first_play_skips_gap()
	_test_bgm_fade_then_gap()


func _make_wav() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(160)
	stream.data = data
	return stream


func _make_audio() -> Node:
	var audio = preload("res://scripts/app/audio_service.gd").new()
	root.add_child(audio)
	if audio.get_node_or_null("Bgm") == null:
		audio._ready()
	return audio


func _bgm_player(audio: Node) -> AudioStreamPlayer:
	return audio.get_node("Bgm") as AudioStreamPlayer


func _test_bgm_empty() -> void:
	var audio := _make_audio()
	var bgm := _bgm_player(audio)
	audio.play_playlist([], false)
	_check(bgm.stream == null or not bgm.playing, "empty playlist does not play")
	audio.queue_free()


func _test_bgm_loop_first() -> void:
	var audio := _make_audio()
	var bgm := _bgm_player(audio)
	var a := _make_wav()
	var b := _make_wav()
	audio.play_playlist([a, b], false)
	_check(bgm.stream == a, "unshuffled plays first stream only")
	bgm.finished.emit()
	_check(bgm.stream == a, "unshuffled loops the first stream")
	audio.queue_free()


func _test_bgm_shuffle_cycle() -> void:
	var audio := _make_audio()
	var bgm := _bgm_player(audio)
	var a := _make_wav()
	var b := _make_wav()
	var c := _make_wav()
	audio.rng.seed = 7
	audio.play_playlist([a, b, c], true)
	var order: Array = []
	order.append(bgm.stream)
	bgm.finished.emit()
	order.append(bgm.stream)
	bgm.finished.emit()
	order.append(bgm.stream)
	_check(order.size() == 3, "shuffle yields three plays")
	_check(order[0] != order[1] or order[1] != order[2] or order[0] != order[2], "shuffle is a permutation (not all identical)")
	_check(order.has(a) and order.has(b) and order.has(c), "shuffle keeps every stream")
	bgm.finished.emit()
	_check(bgm.stream == order[0], "wrap repeats the shuffled order")
	audio.queue_free()


func _test_bgm_first_play_skips_gap() -> void:
	var audio := _make_audio()
	var bgm := _bgm_player(audio)
	audio.fade_seconds = 1.0
	audio.gap_seconds = 2.0
	audio.play_playlist([_make_wav()], false)
	_check(bgm.playing or bgm.stream != null, "first play starts without waiting")
	audio.queue_free()


func _test_bgm_fade_then_gap() -> void:
	var audio := _make_audio()
	var bgm := _bgm_player(audio)
	audio.fade_seconds = 1.0
	audio.gap_seconds = 2.0
	var a := _make_wav()
	var b := _make_wav()
	audio.play_playlist([a], false)
	audio.play_playlist([b], false)
	audio._process(0.5)
	_check(bgm.volume_db < -1.0, "volume falls during fade")
	audio._process(0.5)
	_check(not bgm.playing, "player stops after fade")
	_check(bgm.stream != b or not bgm.playing, "new track not started during gap")
	audio._process(1.9)
	_check(not bgm.playing, "still silent before gap ends")
	audio._process(0.2)
	_check(bgm.stream == b, "new track starts after gap")
	audio.queue_free()


func _test_se_same_tick_coalesce() -> void:
	print("-- se same-tick coalesce")
	var audio := _make_audio()
	audio._se_stream = _make_wav()
	var before: int = audio.se_starts
	audio.play_collapse()
	audio.play_collapse()
	audio.play_collapse()
	_check(audio.se_starts == before + 1, "same-tick identical SE starts once (got %d)" % (audio.se_starts - before))
	audio._process(0.016)
	audio.play_collapse()
	_check(audio.se_starts == before + 2, "later tick can start the same SE again")
	audio.play_collapse()
	_check(audio.se_starts == before + 2, "second later-tick burst still coalesces")
	audio.queue_free()


func _test_ui_hover_styles() -> void:
	print("-- ui hover")
	var style = preload("res://scripts/app/ui_button_style.gd")
	var base := Color(0.62, 0.90, 0.94)
	var hover: Color = style.hover_color(base)
	_check(hover.get_luminance() > base.get_luminance(), "cell hover is lighter")
	var btn := Button.new()
	style.apply_cell(btn, base, true)
	var normal := btn.get_theme_stylebox("normal") as StyleBoxFlat
	var hover_box := btn.get_theme_stylebox("hover") as StyleBoxFlat
	_check(normal != null and hover_box != null, "cell has normal and hover boxes")
	_check(not normal.bg_color.is_equal_approx(hover_box.bg_color), "cell hover box is distinct")
	btn.queue_free()
	var icon := TextureButton.new()
	root.add_child(icon)
	style.bind_icon(icon)
	icon.mouse_entered.emit()
	_check(icon.self_modulate.is_equal_approx(style.ICON_HOVER), "icon brightens on hover")
	icon.mouse_exited.emit()
	_check(icon.self_modulate.is_equal_approx(style.ICON_REST), "icon restores when pointer leaves")
	style.set_icon_enabled(icon, false)
	_check(icon.disabled, "disabled icon is not interactive")
	icon.mouse_entered.emit()
	_check(icon.self_modulate.is_equal_approx(style.ICON_DISABLED), "disabled icon does not highlight")
	style.set_icon_enabled(icon, true)
	var nav := TextureButton.new()
	root.add_child(nav)
	style.bind_icon(nav, style.nav_gray_palette())
	_check(nav.self_modulate.is_equal_approx(style.NAV_REST), "nav rest is medium gray")
	nav.mouse_entered.emit()
	_check(nav.self_modulate.is_equal_approx(style.NAV_HOVER), "nav hover is lighter gray")
	nav.button_down.emit()
	_check(nav.self_modulate.is_equal_approx(style.NAV_PRESSED), "nav pressed is darker gray")
	nav.button_up.emit()
	nav.mouse_exited.emit()
	style.set_icon_enabled(nav, false)
	_check(nav.self_modulate.is_equal_approx(style.NAV_DISABLED), "nav disabled is pale gray")
	_check(
		style.NAV_PRESSED.get_luminance() < style.NAV_REST.get_luminance()
		and style.NAV_REST.get_luminance() < style.NAV_HOVER.get_luminance()
		and style.NAV_HOVER.get_luminance() < style.NAV_DISABLED.get_luminance(),
		"nav grays are four distinct depths"
	)
	icon.queue_free()
	nav.queue_free()


func _test_debug_jump_off() -> void:
	print("-- debug jump")
	_check(_GameLaunch.DEBUG_JUMP == false, "DEBUG_JUMP default false")
