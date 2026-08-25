@tool
class_name BoxBuilder
extends RefCounted

enum Face { POS_Z = 1, NEG_Z = 2, POS_X = 4, NEG_X = 8, TOP = 16, BOTTOM = 32 }

static func face_toward(direction: Vector2) -> int:
	if absf(direction.x) >= absf(direction.y):
		return Face.POS_X if direction.x > 0.0 else Face.NEG_X
	return Face.POS_Z if direction.y > 0.0 else Face.NEG_Z

static func build(accumulator: SurfaceAccumulator, slot: String, material: Material, near: Vector2, far: Vector2, base_y: float, top_y: float, buried_faces: int = 0, interior_faces: int = 0) -> void:
	var x0: float = min(near.x, far.x)
	var x1: float = max(near.x, far.x)
	var z0: float = min(near.y, far.y)
	var z1: float = max(near.y, far.y)
	var width_x: float = x1 - x0
	var width_z: float = z1 - z0
	var height: float = top_y - base_y

	var v_pos_z: int = _face_visibility(Face.POS_Z, buried_faces, interior_faces)
	var v_neg_z: int = _face_visibility(Face.NEG_Z, buried_faces, interior_faces)
	var v_pos_x: int = _face_visibility(Face.POS_X, buried_faces, interior_faces)
	var v_neg_x: int = _face_visibility(Face.NEG_X, buried_faces, interior_faces)
	var v_top: int = _face_visibility(Face.TOP, buried_faces, interior_faces)
	var v_bottom: int = _face_visibility(Face.BOTTOM, buried_faces, interior_faces)

	accumulator.add_quad(slot, material, Vector3(x0, base_y, z1), Vector3(x1, base_y, z1), Vector3(x1, top_y, z1), Vector3(x0, top_y, z1), Vector3(0, 0, 1), Vector2(0, height), Vector2(width_x, height), Vector2(width_x, 0), Vector2(0, 0), v_pos_z)
	accumulator.add_quad(slot, material, Vector3(x1, base_y, z0), Vector3(x0, base_y, z0), Vector3(x0, top_y, z0), Vector3(x1, top_y, z0), Vector3(0, 0, -1), Vector2(0, height), Vector2(width_x, height), Vector2(width_x, 0), Vector2(0, 0), v_neg_z)
	accumulator.add_quad(slot, material, Vector3(x1, base_y, z1), Vector3(x1, base_y, z0), Vector3(x1, top_y, z0), Vector3(x1, top_y, z1), Vector3(1, 0, 0), Vector2(0, height), Vector2(width_z, height), Vector2(width_z, 0), Vector2(0, 0), v_pos_x)
	accumulator.add_quad(slot, material, Vector3(x0, base_y, z0), Vector3(x0, base_y, z1), Vector3(x0, top_y, z1), Vector3(x0, top_y, z0), Vector3(-1, 0, 0), Vector2(0, height), Vector2(width_z, height), Vector2(width_z, 0), Vector2(0, 0), v_neg_x)
	accumulator.add_quad(slot, material, Vector3(x0, top_y, z1), Vector3(x1, top_y, z1), Vector3(x1, top_y, z0), Vector3(x0, top_y, z0), Vector3(0, 1, 0), Vector2(0, 0), Vector2(width_x, 0), Vector2(width_x, width_z), Vector2(0, width_z), v_top)
	accumulator.add_quad(slot, material, Vector3(x0, base_y, z0), Vector3(x1, base_y, z0), Vector3(x1, base_y, z1), Vector3(x0, base_y, z1), Vector3(0, -1, 0), Vector2(0, 0), Vector2(width_x, 0), Vector2(width_x, width_z), Vector2(0, width_z), v_bottom)


static func _face_visibility(face: int, buried_faces: int, interior_faces: int) -> int:
	if interior_faces & face:
		return SurfaceAccumulator.Visibility.INTERIOR
	if buried_faces & face:
		return SurfaceAccumulator.Visibility.BURIED
	return SurfaceAccumulator.Visibility.EXTERIOR
