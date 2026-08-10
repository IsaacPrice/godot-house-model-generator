@tool
class_name BoxBuilder
extends RefCounted

static func build(accumulator: SurfaceAccumulator, slot: String, material: Material, near: Vector2, far: Vector2, base_y: float, top_y: float) -> void:
	var x0: float = min(near.x, far.x)
	var x1: float = max(near.x, far.x)
	var z0: float = min(near.y, far.y)
	var z1: float = max(near.y, far.y)
	var width_x: float = x1 - x0
	var width_z: float = z1 - z0
	var height: float = top_y - base_y

	accumulator.add_quad(slot, material, Vector3(x0, base_y, z1), Vector3(x1, base_y, z1), Vector3(x1, top_y, z1), Vector3(x0, top_y, z1), Vector3(0, 0, 1), Vector2(0, height), Vector2(width_x, height), Vector2(width_x, 0), Vector2(0, 0))
	accumulator.add_quad(slot, material, Vector3(x1, base_y, z0), Vector3(x0, base_y, z0), Vector3(x0, top_y, z0), Vector3(x1, top_y, z0), Vector3(0, 0, -1), Vector2(0, height), Vector2(width_x, height), Vector2(width_x, 0), Vector2(0, 0))
	accumulator.add_quad(slot, material, Vector3(x1, base_y, z1), Vector3(x1, base_y, z0), Vector3(x1, top_y, z0), Vector3(x1, top_y, z1), Vector3(1, 0, 0), Vector2(0, height), Vector2(width_z, height), Vector2(width_z, 0), Vector2(0, 0))
	accumulator.add_quad(slot, material, Vector3(x0, base_y, z0), Vector3(x0, base_y, z1), Vector3(x0, top_y, z1), Vector3(x0, top_y, z0), Vector3(-1, 0, 0), Vector2(0, height), Vector2(width_z, height), Vector2(width_z, 0), Vector2(0, 0))
	accumulator.add_quad(slot, material, Vector3(x0, top_y, z1), Vector3(x1, top_y, z1), Vector3(x1, top_y, z0), Vector3(x0, top_y, z0), Vector3(0, 1, 0), Vector2(0, 0), Vector2(width_x, 0), Vector2(width_x, width_z), Vector2(0, width_z))
	accumulator.add_quad(slot, material, Vector3(x0, base_y, z0), Vector3(x1, base_y, z0), Vector3(x1, base_y, z1), Vector3(x0, base_y, z1), Vector3(0, -1, 0), Vector2(0, 0), Vector2(width_x, 0), Vector2(width_x, width_z), Vector2(0, width_z))
