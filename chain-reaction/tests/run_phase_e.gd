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


func _test_debug_jump_off() -> void:
	print("-- debug jump")
	_check(_GameLaunch.DEBUG_JUMP == false, "DEBUG_JUMP default false")
