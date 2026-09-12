class_name UiButtonStyle
extends RefCounted

const ICON_REST := Color.WHITE
const ICON_HOVER := Color(1.22, 1.22, 1.22)
const ICON_PRESSED := Color(0.86, 0.86, 0.86)
const ICON_DISABLED := Color(1, 1, 1, 0.35)
const NAV_DISABLED := Color(0.80, 0.80, 0.80)
const NAV_REST := Color(0.48, 0.48, 0.48)
const NAV_HOVER := Color(0.70, 0.70, 0.70)
const NAV_PRESSED := Color(0.24, 0.24, 0.24)
const META_PALETTE := "ui_icon_palette"
const META_DOWN := "ui_icon_down"
const META_HOVER := "ui_icon_hover"
const HOVER_LIGHTEN := 0.18
const PRESS_DARKEN := 0.1
const CELL_RADIUS := 10
const CELL_MARGIN := 8
const CELL_DISABLED := Color(0.78, 0.78, 0.82)


static func hover_color(base: Color) -> Color:
	return base.lightened(HOVER_LIGHTEN)


static func pressed_color(base: Color) -> Color:
	return base.darkened(PRESS_DARKEN)


static func cell_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(CELL_RADIUS)
	box.content_margin_left = CELL_MARGIN
	box.content_margin_right = CELL_MARGIN
	box.content_margin_top = CELL_MARGIN
	box.content_margin_bottom = CELL_MARGIN
	return box


static func apply_cell(btn: Button, color: Color, playable: bool) -> void:
	var base: Color = color if playable else CELL_DISABLED
	btn.add_theme_stylebox_override("normal", cell_box(base))
	btn.add_theme_stylebox_override("hover", cell_box(hover_color(base)))
	btn.add_theme_stylebox_override("pressed", cell_box(pressed_color(base)))
	btn.add_theme_stylebox_override("disabled", cell_box(CELL_DISABLED))
	btn.add_theme_stylebox_override("focus", cell_box(base))
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func default_icon_palette() -> Dictionary:
	return {
		"rest": ICON_REST,
		"hover": ICON_HOVER,
		"pressed": ICON_PRESSED,
		"disabled": ICON_DISABLED,
	}


static func nav_gray_palette() -> Dictionary:
	return {
		"rest": NAV_REST,
		"hover": NAV_HOVER,
		"pressed": NAV_PRESSED,
		"disabled": NAV_DISABLED,
	}


static func bind_icon(btn: BaseButton, palette: Dictionary = {}) -> void:
	btn.set_meta(META_PALETTE, default_icon_palette() if palette.is_empty() else palette)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var entered := _on_icon_entered.bind(btn)
	var exited := _on_icon_exited.bind(btn)
	var down := _on_icon_down.bind(btn)
	var up := _on_icon_up.bind(btn)
	if not btn.mouse_entered.is_connected(entered):
		btn.mouse_entered.connect(entered)
	if not btn.mouse_exited.is_connected(exited):
		btn.mouse_exited.connect(exited)
	if not btn.button_down.is_connected(down):
		btn.button_down.connect(down)
	if not btn.button_up.is_connected(up):
		btn.button_up.connect(up)
	_apply_icon_modulate(btn)


static func set_icon_enabled(btn: BaseButton, on: bool) -> void:
	btn.disabled = not on
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	if not on:
		btn.set_meta(META_HOVER, false)
		btn.set_meta(META_DOWN, false)
	elif btn.is_hovered():
		btn.set_meta(META_HOVER, true)
	_apply_icon_modulate(btn)


static func _palette(btn: BaseButton) -> Dictionary:
	if btn.has_meta(META_PALETTE):
		return btn.get_meta(META_PALETTE)
	return default_icon_palette()


static func _apply_icon_modulate(btn: BaseButton) -> void:
	var pal: Dictionary = _palette(btn)
	if btn.disabled:
		btn.self_modulate = pal.disabled
	elif bool(btn.get_meta(META_DOWN, false)):
		btn.self_modulate = pal.pressed
	elif bool(btn.get_meta(META_HOVER, false)):
		btn.self_modulate = pal.hover
	else:
		btn.self_modulate = pal.rest


static func _on_icon_entered(btn: BaseButton) -> void:
	if not btn.disabled:
		btn.set_meta(META_HOVER, true)
	_apply_icon_modulate(btn)


static func _on_icon_exited(btn: BaseButton) -> void:
	btn.set_meta(META_HOVER, false)
	btn.set_meta(META_DOWN, false)
	_apply_icon_modulate(btn)


static func _on_icon_down(btn: BaseButton) -> void:
	if btn.disabled:
		return
	btn.set_meta(META_DOWN, true)
	_apply_icon_modulate(btn)


static func _on_icon_up(btn: BaseButton) -> void:
	btn.set_meta(META_DOWN, false)
	_apply_icon_modulate(btn)
