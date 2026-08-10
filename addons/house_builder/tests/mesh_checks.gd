class_name MeshChecks
extends RefCounted


static func check_windings(name: String, mesh: ArrayMesh, check: Callable) -> void:
	check.call(name, "mesh has surfaces", mesh.get_surface_count() > 0)
	var expected_sign: float = 0.0
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		check.call(name, "surface %d has triangles" % s, indices.size() >= 3)
		for t in range(0, indices.size(), 3):
			var a: Vector3 = verts[indices[t]]
			var b: Vector3 = verts[indices[t + 1]]
			var c: Vector3 = verts[indices[t + 2]]
			var geometric: Vector3 = (b - a).cross(c - a)
			if geometric.length() < 1e-9:
				continue
			var stored: Vector3 = norms[indices[t]] + norms[indices[t + 1]] + norms[indices[t + 2]]
			var sign_here: float = signf(geometric.dot(stored))
			check.call(name, "triangle winding is not degenerate", sign_here != 0.0)
			if expected_sign == 0.0:
				expected_sign = sign_here
			else:
				check.call(name, "surface %d triangle winding consistent" % s, sign_here == expected_sign)


static func find_surface(mesh: ArrayMesh, slot: String) -> int:
	for s in range(mesh.get_surface_count()):
		if mesh.surface_get_name(s) == slot:
			return s
	return -1


static func surface_arrays(mesh: ArrayMesh, slot: String) -> Array:
	var index: int = find_surface(mesh, slot)
	if index < 0:
		return []
	return mesh.surface_get_arrays(index)


static func facing_area(mesh: ArrayMesh, slot: String, normal: Vector3, filter: Callable = Callable()) -> float:
	var arrays: Array = surface_arrays(mesh, slot)
	if arrays.is_empty():
		return 0.0
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var area: float = 0.0
	for t in range(0, indices.size(), 3):
		if norms[indices[t]].dot(normal) < 0.99:
			continue
		var a: Vector3 = verts[indices[t]]
		var b: Vector3 = verts[indices[t + 1]]
		var c: Vector3 = verts[indices[t + 2]]
		if filter.is_valid() and not filter.call(a, b, c):
			continue
		area += (b - a).cross(c - a).length() * 0.5
	return area


static func surface_height_at(mesh: ArrayMesh, slot: String, plan: Vector2, normal_sign: float) -> float:
	var arrays: Array = surface_arrays(mesh, slot)
	if arrays.is_empty():
		return -INF
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var best: float = -INF
	for t in range(0, indices.size(), 3):
		if norms[indices[t]].y * normal_sign <= 0.0:
			continue
		var a: Vector3 = verts[indices[t]]
		var b: Vector3 = verts[indices[t + 1]]
		var c: Vector3 = verts[indices[t + 2]]
		var d0 := Vector2(b.x - a.x, b.z - a.z)
		var d1 := Vector2(c.x - a.x, c.z - a.z)
		var dp := Vector2(plan.x - a.x, plan.y - a.z)
		var denom: float = d0.cross(d1)
		if absf(denom) < 1e-9:
			continue
		var u: float = dp.cross(d1) / denom
		var v: float = d0.cross(dp) / denom
		if u < -1e-4 or v < -1e-4 or u + v > 1.0 + 1e-4:
			continue
		best = maxf(best, a.y + (b.y - a.y) * u + (c.y - a.y) * v)
	return best


static func facing_triangle_count(mesh: ArrayMesh, slot: String, normal: Vector3) -> int:
	var arrays: Array = surface_arrays(mesh, slot)
	if arrays.is_empty():
		return 0
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count: int = 0
	for t in range(0, indices.size(), 3):
		if norms[indices[t]].dot(normal) > 0.99:
			count += 1
	return count
