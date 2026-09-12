class_name HudStrings
extends RefCounted

const _I18n := preload("res://scripts/app/i18n.gd")


static var COMPLETED: String:
	get:
		return _I18n.t("hud.completed")


static var FAILED: String:
	get:
		return _I18n.t("hud.failed")


static func left_steps(n: int) -> String:
	return _I18n.t("hud.left_steps", {"n": n})
