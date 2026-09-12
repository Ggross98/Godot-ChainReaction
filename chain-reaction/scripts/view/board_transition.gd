class_name BoardTransition
extends RefCounted

const _HexGrid := preload("res://scripts/core/hex_grid.gd")

const ATOM_IN := 0.5
const ATOM_OUT := 0.18
const STAGGER := 0.03
const STAGGER_CAP := 0.25
const ENTER_OVERLAP := 0.08

var _t: float = 0.0
var _active: bool = false
var _enter_delay: Dictionary = {}
var _exit_delay: Dictionary = {}
var _enter_offset: float = 0.0
var _end_t: float = 0.0


func begin(enter_cells: Array[Vector2i], exit_cells: Array[Vector2i], origin: Vector2i) -> void:
	_t = 0.0
	_enter_delay.clear()
	_exit_delay.clear()
	_enter_offset = ENTER_OVERLAP if not exit_cells.is_empty() else 0.0
	var max_end := 0.0
	for cell in enter_cells:
		var delay := _delay(origin, cell)
		_enter_delay[cell] = delay
		max_end = maxf(max_end, _enter_offset + delay + ATOM_IN)
	for cell in exit_cells:
		var delay := _delay(origin, cell)
		_exit_delay[cell] = delay
		max_end = maxf(max_end, delay + ATOM_OUT)
	_end_t = max_end
	_active = max_end > 0.0


func tick(dt: float) -> void:
	if not _active:
		return
	_t += dt
	if _t >= _end_t:
		_t = _end_t
		_active = false


func is_active() -> bool:
	return _active


func enter_k(cell: Vector2i) -> float:
	if not _enter_delay.has(cell):
		return 1.0
	var start: float = _enter_offset + float(_enter_delay[cell])
	if ATOM_IN <= 0.0:
		return 1.0
	return clampf((_t - start) / ATOM_IN, 0.0, 1.0)


func exit_k(cell: Vector2i) -> float:
	if not _exit_delay.has(cell):
		return 0.0
	var start: float = float(_exit_delay[cell])
	if ATOM_OUT <= 0.0:
		return 0.0
	return 1.0 - clampf((_t - start) / ATOM_OUT, 0.0, 1.0)


func cut() -> void:
	_active = false
	_t = _end_t
	_enter_delay.clear()
	_exit_delay.clear()


func _delay(origin: Vector2i, cell: Vector2i) -> float:
	var dist: int = _HexGrid.odd_r_distance(origin.x, origin.y, cell.x, cell.y)
	return minf(float(dist) * STAGGER, STAGGER_CAP)
