extends Node2D

const _MapLoader := preload("res://scripts/content/map_loader.gd")
const _MapPack := preload("res://scripts/core/map_data.gd")
const _MapSchema := preload("res://scripts/core/map_schema.gd")
const _HexGrid := preload("res://scripts/core/hex_grid.gd")
const _GameSession := preload("res://scripts/app/game_session.gd")
const _ViewTransform := preload("res://scripts/view/view_transform.gd")
const _GameLaunch := preload("res://scripts/app/game_launch.gd")

const BOARD_SCREEN_NUDGE_PX := 20.0
const SIDEBAR_WIDTH_PX := 420.0
const CUSTOM_DIR := _GameLaunch.CUSTOM
const ID_PATTERN := "^[A-Za-z0-9][A-Za-z0-9_-]*$"

var session = _GameSession.new()
var draft = _MapPack.MapData.new()
var selected = null
var _loader := _MapLoader.new()
var _suppress: bool = false
var _orbit_boxes: Array = []

@onready var board: Node2D = $Board
@onready var side_panel: Control = $CanvasLayer/HUD/SidePanel
@onready var load_option: OptionButton = $CanvasLayer/HUD/SidePanel/VBox/LoadOption
@onready var id_edit: LineEdit = $CanvasLayer/HUD/SidePanel/VBox/IdEdit
@onready var name_edit: LineEdit = $CanvasLayer/HUD/SidePanel/VBox/NameEdit
@onready var width_spin: SpinBox = $CanvasLayer/HUD/SidePanel/VBox/SizeRow/WidthSpin
@onready var height_spin: SpinBox = $CanvasLayer/HUD/SidePanel/VBox/SizeRow/HeightSpin
@onready var steps_spin: SpinBox = $CanvasLayer/HUD/SidePanel/VBox/StepsSpin
@onready var type_option: OptionButton = $CanvasLayer/HUD/SidePanel/VBox/TypeOption
@onready var group_spin: SpinBox = $CanvasLayer/HUD/SidePanel/VBox/GroupSpin
@onready var orbit_row_0: HBoxContainer = $CanvasLayer/HUD/SidePanel/VBox/OrbitRow0
@onready var orbit_row_1: HBoxContainer = $CanvasLayer/HUD/SidePanel/VBox/OrbitRow1
@onready var status_label: Label = $CanvasLayer/HUD/SidePanel/VBox/Status
@onready var new_button: Button = $CanvasLayer/HUD/SidePanel/VBox/ButtonRow/NewButton
@onready var validate_button: Button = $CanvasLayer/HUD/SidePanel/VBox/ButtonRow/ValidateButton
@onready var save_button: Button = $CanvasLayer/HUD/SidePanel/VBox/ButtonRow/SaveButton


func _ready() -> void:
	RenderingServer.set_default_clear_color(_ViewTransform.CLEAR_COLOR)
	_nudge_board_for_sidebar()
	call_deferred("_nudge_board_for_sidebar")
	_fill_type_option()
	_build_orbit_toggles()
	new_button.pressed.connect(_on_new)
	validate_button.pressed.connect(_on_validate)
	save_button.pressed.connect(_on_save)
	load_option.item_selected.connect(_on_load_selected)
	id_edit.text_changed.connect(_on_id_changed)
	name_edit.text_changed.connect(_on_name_changed)
	width_spin.value_changed.connect(_on_width_changed)
	height_spin.value_changed.connect(_on_height_changed)
	steps_spin.value_changed.connect(_on_steps_changed)
	type_option.item_selected.connect(_on_type_selected)
	group_spin.value_changed.connect(_on_group_changed)
	_on_new()
	_refresh_load_option()


func _process(dt: float) -> void:
	session.pointer_move(board.pointer_logic())
	board.sync(session, dt)


func _unhandled_input(event: InputEvent) -> void:
	if _pointer_over_panel():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE:
		_delete_selected()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_board_left()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_on_board_right()
			get_viewport().set_input_as_handled()


func _nudge_board_for_sidebar() -> void:
	var sidebar_px: float = side_panel.size.x
	if sidebar_px <= 1.0:
		sidebar_px = SIDEBAR_WIDTH_PX
	board.position.x = -sidebar_px * 0.5 / _ViewTransform.CAMERA_ZOOM
	board.position.y = -BOARD_SCREEN_NUDGE_PX / _ViewTransform.CAMERA_ZOOM


func _pointer_over_panel() -> bool:
	return side_panel.get_global_rect().has_point(side_panel.get_global_mouse_position())


func _fill_type_option() -> void:
	type_option.clear()
	for type_id in _MapSchema.TYPES:
		type_option.add_item(type_id)


func _build_orbit_toggles() -> void:
	_orbit_boxes.clear()
	var rows: Array = [orbit_row_0, orbit_row_1]
	for layer in range(2):
		var row: HBoxContainer = rows[layer]
		for child in row.get_children():
			child.queue_free()
		var layer_boxes: Array = []
		for dir_id in _MapSchema.DIRECTIONS:
			var box := CheckBox.new()
			box.text = dir_id
			box.toggled.connect(_on_orbit_toggled)
			row.add_child(box)
			layer_boxes.append(box)
		_orbit_boxes.append(layer_boxes)


func _on_new() -> void:
	draft = _MapPack.MapData.new()
	draft.id = "untitled"
	draft.name = "Untitled"
	draft.width = 5
	draft.height = 4
	draft.steps = 1
	selected = null
	if load_option.item_count > 0:
		load_option.select(0)
	_sync_fields_from_draft("New map")
	_push_board()


func _on_validate() -> void:
	_apply_fields_to_draft()
	var result = _loader.validate_map(draft)
	if result.ok:
		_set_status("Valid")
	else:
		_set_status("\n".join(result.errors))


func _on_save() -> void:
	_apply_fields_to_draft()
	if not _id_ok(draft.id):
		_set_status("id must match %s" % ID_PATTERN)
		return
	var result = _loader.upsert_custom_map(draft, CUSTOM_DIR)
	if not result.ok:
		_set_status("\n".join(result.errors))
		return
	draft = result.map
	selected = null
	_refresh_load_option()
	_sync_fields_from_draft("Saved %s/%s" % [CUSTOM_DIR, _MapLoader.level_file_name(draft.id)])
	_push_board()


func _on_load_selected(index: int) -> void:
	if index <= 0:
		return
	var map_id := load_option.get_item_text(index)
	var path := "%s/%s" % [CUSTOM_DIR, _MapLoader.level_file_name(map_id)]
	var result = _loader.load_map_file(path)
	if not result.ok or result.map == null:
		_set_status("\n".join(result.errors))
		return
	draft = result.map
	selected = null
	_sync_fields_from_draft("Loaded %s" % map_id)
	_push_board()


func _on_id_changed(value: String) -> void:
	if _suppress:
		return
	draft.id = value.strip_edges()


func _on_name_changed(value: String) -> void:
	if _suppress:
		return
	draft.name = value.strip_edges()


func _on_width_changed(value: float) -> void:
	if _suppress:
		return
	draft.width = int(value)
	var dropped := _drop_out_of_bounds()
	_push_board()
	if dropped > 0:
		_set_status("Removed %d atoms outside the board" % dropped)


func _on_height_changed(value: float) -> void:
	if _suppress:
		return
	draft.height = int(value)
	var dropped := _drop_out_of_bounds()
	_push_board()
	if dropped > 0:
		_set_status("Removed %d atoms outside the board" % dropped)


func _on_steps_changed(value: float) -> void:
	if _suppress:
		return
	draft.steps = int(value)
	_push_board()


func _on_type_selected(_index: int) -> void:
	if _suppress:
		return
	if selected == null:
		_refresh_group_enabled()
		return
	selected.type = _current_type()
	_normalize_atom(selected)
	_sync_selection_widgets()
	_push_board()


func _on_group_changed(value: float) -> void:
	if _suppress or selected == null:
		return
	if _MapSchema.is_entangled_type(selected.type):
		selected.group = int(value)
		_push_board()


func _on_orbit_toggled(_pressed: bool) -> void:
	if _suppress or selected == null:
		return
	selected.orbits = _read_orbit_layers()
	_push_board()


func _on_board_left() -> void:
	var cell := _pointer_cell()
	if not _HexGrid.is_in_map(draft.width, draft.height, cell.x, cell.y):
		selected = null
		_sync_selection_widgets()
		return
	var existing = _atom_at(cell)
	if existing != null:
		selected = existing
		_sync_selection_widgets()
		return
	var atom := _MapPack.AtomData.new()
	atom.x = cell.x
	atom.y = cell.y
	atom.type = _current_type()
	_normalize_atom(atom)
	if not _MapSchema.is_catching_type(atom.type) and atom.neutron_count() == 0:
		atom.orbits = [PackedStringArray(["E"])]
	draft.atoms.append(atom)
	selected = atom
	_sync_selection_widgets()
	_push_board()
	_set_status("Placed %s at (%d,%d)" % [atom.type, atom.x, atom.y])


func _on_board_right() -> void:
	var cell := _pointer_cell()
	var existing = _atom_at(cell)
	if existing != null:
		selected = existing
	_delete_selected()


func _delete_selected() -> void:
	if selected == null:
		return
	draft.atoms.erase(selected)
	_set_status("Deleted atom at (%d,%d)" % [selected.x, selected.y])
	selected = null
	_sync_selection_widgets()
	_push_board()


func _pointer_cell() -> Vector2i:
	return _HexGrid.world_to_cell(draft.width, draft.height, board.pointer_logic())


func _atom_at(cell: Vector2i):
	for atom in draft.atoms:
		if atom.x == cell.x and atom.y == cell.y:
			return atom
	return null


func _current_type() -> String:
	var index: int = type_option.selected
	if index < 0 or index >= _MapSchema.TYPES.size():
		return _MapSchema.TYPE_NORMAL
	return _MapSchema.TYPES[index]


func _normalize_atom(atom) -> void:
	if _MapSchema.is_entangled_type(atom.type):
		if atom.group < 1:
			atom.group = maxi(int(group_spin.value), 1)
	else:
		atom.group = 0
	if _MapSchema.is_catching_type(atom.type):
		return
	if atom.neutron_count() == 0:
		atom.orbits = [PackedStringArray(["E"])]


func _drop_out_of_bounds() -> int:
	var kept: Array = []
	var dropped := 0
	for atom in draft.atoms:
		if _HexGrid.is_in_map(draft.width, draft.height, atom.x, atom.y):
			kept.append(atom)
		else:
			dropped += 1
			if atom == selected:
				selected = null
	draft.atoms = kept
	_sync_selection_widgets()
	return dropped


func _read_orbit_layers() -> Array:
	var layers: Array = []
	for layer in range(_orbit_boxes.size()):
		var dirs := PackedStringArray()
		var boxes: Array = _orbit_boxes[layer]
		for i in range(boxes.size()):
			if boxes[i].button_pressed:
				dirs.append(_MapSchema.DIRECTIONS[i])
		layers.append(dirs)
	while layers.size() > 0 and layers[layers.size() - 1].is_empty():
		layers.pop_back()
	return layers


func _apply_fields_to_draft() -> void:
	draft.id = id_edit.text.strip_edges()
	draft.name = name_edit.text.strip_edges()
	draft.width = int(width_spin.value)
	draft.height = int(height_spin.value)
	draft.steps = int(steps_spin.value)
	_drop_out_of_bounds()
	if selected != null:
		selected.type = _current_type()
		_normalize_atom(selected)
		selected.orbits = _read_orbit_layers()
		if _MapSchema.is_entangled_type(selected.type):
			selected.group = int(group_spin.value)


func _sync_fields_from_draft(message: String) -> void:
	_suppress = true
	id_edit.text = draft.id
	name_edit.text = draft.name
	width_spin.value = draft.width
	height_spin.value = draft.height
	steps_spin.value = draft.steps
	_sync_selection_widgets()
	_suppress = false
	_set_status(message)


func _sync_selection_widgets() -> void:
	var was := _suppress
	_suppress = true
	if selected != null:
		var type_i: int = _MapSchema.TYPES.find(selected.type)
		if type_i >= 0:
			type_option.select(type_i)
		group_spin.value = maxi(selected.group, 1)
		_write_orbit_boxes(selected.orbits)
	else:
		_write_orbit_boxes([])
	_refresh_group_enabled()
	var orbit_enabled := selected != null
	for layer_boxes in _orbit_boxes:
		for box in layer_boxes:
			box.disabled = not orbit_enabled
	_suppress = was


func _write_orbit_boxes(orbits: Array) -> void:
	for layer in range(_orbit_boxes.size()):
		var boxes: Array = _orbit_boxes[layer]
		var dirs := PackedStringArray()
		if layer < orbits.size():
			for dir_id in orbits[layer]:
				dirs.append(str(dir_id))
		for i in range(boxes.size()):
			boxes[i].set_pressed_no_signal(_MapSchema.DIRECTIONS[i] in dirs)


func _refresh_group_enabled() -> void:
	var type_id := _current_type() if selected == null else str(selected.type)
	group_spin.editable = _MapSchema.is_entangled_type(type_id)


func _refresh_load_option() -> void:
	var keep := ""
	if load_option.item_count > 0 and load_option.selected > 0:
		keep = load_option.get_item_text(load_option.selected)
	load_option.clear()
	load_option.add_item("Load custom…")
	var ids: PackedStringArray = _loader.list_custom_ids(CUSTOM_DIR)
	var select_i := 0
	for i in range(ids.size()):
		load_option.add_item(ids[i])
		if ids[i] == keep or ids[i] == draft.id:
			select_i = i + 1
	load_option.select(select_i)


func _push_board() -> void:
	session.start_map(draft)
	board.sync(session, 10.0)


func _set_status(text: String) -> void:
	status_label.text = text


func _id_ok(map_id: String) -> bool:
	var regex := RegEx.new()
	regex.compile(ID_PATTERN)
	return regex.search(map_id) != null
