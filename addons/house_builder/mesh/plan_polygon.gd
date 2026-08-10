@tool
class_name PlanPolygon
extends RefCounted


static func emit(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	points: PackedVector3Array, uvs: PackedVector2Array, normal: Vector3,
	convex: bool = false
) -> void:
	if points.size() < 3:
		return

	if convex or points.size() == 3:
		accumulator.add_polygon(slot, material, points, normal, uvs)
		return

	var plan := PackedVector2Array()
	for p in points:
		plan.append(Vector2(p.x, p.z))
	var area: float = 0.0
	for i in range(plan.size()):
		var j: int = (i + 1) % plan.size()
		area += plan[i].x * plan[j].y - plan[j].x * plan[i].y
	if area < 0.0:
		plan.reverse()
		points = points.duplicate()
		points.reverse()
		uvs = uvs.duplicate()
		uvs.reverse()
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(plan)
	if indices.is_empty():
		accumulator.add_polygon(slot, material, points, normal, uvs)
		return

	var desired: float = signf(normal.y)
	if desired == 0.0:
		desired = 1.0
	for t in range(0, indices.size(), 3):
		var ia: int = indices[t]
		var ib: int = indices[t + 1]
		var ic: int = indices[t + 2]
		var tri_area: float = (plan[ib] - plan[ia]).cross(plan[ic] - plan[ia])
		if tri_area * desired > 0.0:
			var tmp: int = ib
			ib = ic
			ic = tmp
		accumulator.add_polygon(
			slot, material,
			PackedVector3Array([points[ia], points[ib], points[ic]]),
			normal,
			PackedVector2Array([uvs[ia], uvs[ib], uvs[ic]])
		)


static func oriented_quad(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2
) -> void:
	if (c - a).cross(b - a).dot(normal) <= 0.0:
		accumulator.add_quad(slot, material, a, b, c, d, normal, uv_a, uv_b, uv_c, uv_d)
	else:
		accumulator.add_quad(slot, material, a, d, c, b, normal, uv_a, uv_d, uv_c, uv_b)


static func emit_horizontal(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	polygon: PackedVector2Array, y: float, facing_up: bool, uv_scale: float = 1.0
) -> void:
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	for p in polygon:
		points.append(Vector3(p.x, y, p.y))
		uvs.append(p * uv_scale)
	emit(accumulator, slot, material, points, uvs, Vector3.UP if facing_up else Vector3.DOWN)
