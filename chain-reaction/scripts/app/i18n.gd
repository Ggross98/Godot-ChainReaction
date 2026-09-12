class_name I18n
extends RefCounted

const DEFAULT_PATH := "res://data/i18n/en.json"

static var _table: Dictionary = {}
static var _loaded: bool = false


static func load_locale(_id: String = "en", path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		_table = {}
		_loaded = true
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_table = {}
		_loaded = true
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_table = {}
		_loaded = true
		return false
	_table = parsed
	_loaded = true
	return true


static func t(key: String, args: Dictionary = {}) -> String:
	if not _loaded:
		load_locale()
	var text := str(_table.get(key, key))
	for k in args.keys():
		text = text.replace("{%s}" % str(k), str(args[k]))
	return text
