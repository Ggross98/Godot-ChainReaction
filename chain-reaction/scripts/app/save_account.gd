class_name SaveAccount
extends RefCounted

const _GameLaunch := preload("res://scripts/app/game_launch.gd")

const DEFAULT_PATH := "user://account.cfg"
const SLOT := "Player"
const UNLOCK_BUDGET := 3
const STATE_CLEARED := "cleared"
const STATE_UNLOCKED := "unlocked"
const STATE_LOCKED := "locked"
const COLOR_CLEARED := Color(0.10, 0.63, 0.60)
const COLOR_UNLOCKED := Color(0.62, 0.90, 0.94)

static var path: String = DEFAULT_PATH
static var cleared: Array = []


static func reset_memory() -> void:
	cleared = []


static func load_from_disk() -> void:
	cleared = []
	if not FileAccess.file_exists(path):
		return
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var raw: Variant = cfg.get_value("account", "cleared", [])
	if typeof(raw) == TYPE_ARRAY or typeof(raw) == TYPE_PACKED_INT32_ARRAY:
		for v in raw:
			var n := int(v)
			if n >= 0 and not cleared.has(n):
				cleared.append(n)


static func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("account", "name", SLOT)
	cfg.set_value("account", "cleared", cleared.duplicate())
	cfg.save(path)


static func should_persist(pack_path: String) -> bool:
	return pack_path == _GameLaunch.CAMPAIGN


static func mark_cleared(index: int) -> void:
	if index < 0:
		return
	if not cleared.has(index):
		cleared.append(index)
		save_to_disk()


static func is_cleared(index: int) -> bool:
	return cleared.has(index)


static func campaign_cell_state(index: int, map_count: int, cleared_list = null, budget: int = UNLOCK_BUDGET) -> String:
	var list: Array = cleared if cleared_list == null else cleared_list
	if index < 0 or index >= map_count:
		return STATE_LOCKED
	var unlock := budget
	for i in range(map_count):
		if list.has(i):
			if i == index:
				return STATE_CLEARED
			continue
		if unlock > 0:
			if i == index:
				return STATE_UNLOCKED
			unlock -= 1
		elif i == index:
			return STATE_LOCKED
	return STATE_LOCKED


static func is_playable(is_campaign: bool, index: int, map_count: int, cleared_list = null) -> bool:
	if not is_campaign:
		return true
	return campaign_cell_state(index, map_count, cleared_list) != STATE_LOCKED


static func cell_color(state: String) -> Color:
	if state == STATE_CLEARED:
		return COLOR_CLEARED
	return COLOR_UNLOCKED
