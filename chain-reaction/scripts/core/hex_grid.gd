class_name HexGrid
extends RefCounted

## Odd-r hex occupancy. World mapping is added in phase B.


static func is_in_map(width: int, height: int, x: int, y: int) -> bool:
	if x < 0 or y < 0:
		return false
	if y >= height:
		return false
	if y % 2 == 0:
		return x < width
	return x < width - 1
