class_name ViewTransform
extends RefCounted

const CAMERA_ZOOM := 108.0
const PPU_DEFAULT := 128.0
const PPU_ORBIT0 := 120.0
const PPU_ARROW := 256.0
const ATOM_ROOT_SCALE := 0.9
const CLEAR_COLOR := Color(0.88, 0.882, 0.933)


static func logic_to_view(p: Vector2) -> Vector2:
	return Vector2(p.x, -p.y)


static func view_to_logic(p: Vector2) -> Vector2:
	return Vector2(p.x, -p.y)


static func sprite_scale(ppu: float = PPU_DEFAULT) -> Vector2:
	return Vector2.ONE / ppu
