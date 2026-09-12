class_name HexGrid
extends RefCounted

## Odd-r hex occupancy and y-up world mapping (Unity-compatible).


static func is_in_map(width: int, height: int, x: int, y: int) -> bool:
	if x < 0 or y < 0:
		return false
	if y >= height:
		return false
	if y % 2 == 0:
		return x < width
	return x < width - 1


static func spacing(width: int, height: int) -> float:
	if width >= 6 or height >= 5:
		return 1.8
	return 3.0


static func origin_offset(width: int, height: int) -> Vector2:
	var s := spacing(width, height)
	return Vector2((width - 1) / 2.0 * s, (height - 1) / 2.0 / 2.0 * sqrt(3.0) * s)


static func cell_to_local(width: int, height: int, x: int, y: int) -> Vector2:
	var s := spacing(width, height)
	var lx := x * s
	if y % 2 != 0:
		lx += s / 2.0
	var ly := float(y) / 2.0 * sqrt(3.0) * s
	return Vector2(lx, ly)


static func cell_to_world(width: int, height: int, x: int, y: int) -> Vector2:
	return cell_to_local(width, height, x, y) - origin_offset(width, height)


static func world_to_cell(width: int, height: int, world: Vector2) -> Vector2i:
	var local := world + origin_offset(width, height)
	var s := spacing(width, height)
	var row_h := s / 2.0 * sqrt(3.0)
	var dx := s / 2.0
	var dy := row_h / 2.0
	var y := int(floor((local.y + dy) / row_h))
	var x: int
	if y % 2 == 0:
		x = int(floor((local.x + dx) / s))
	else:
		x = int(floor(local.x / s))
	return Vector2i(x, y)


static func direction_vector(id: String) -> Vector2:
	match id:
		"W":
			return Vector2(-1, 0)
		"NW":
			return Vector2(-1, sqrt(3.0))
		"NE":
			return Vector2(1, sqrt(3.0))
		"E":
			return Vector2(1, 0)
		"SE":
			return Vector2(1, -sqrt(3.0))
		"SW":
			return Vector2(-1, -sqrt(3.0))
		_:
			return Vector2.ZERO


static func bounce_dir(id: String) -> String:
	match id:
		"W":
			return "E"
		"E":
			return "W"
		"NW":
			return "SE"
		"SE":
			return "NW"
		"NE":
			return "SW"
		"SW":
			return "NE"
		_:
			return id
