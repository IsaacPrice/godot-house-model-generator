extends SceneTree


const EXAMPLES: Array[String] = [
	"res://examples/LargerHouse.tscn",
	"res://examples/SmallHouse.tscn",
]

const SURFACE_OFFSET := 2e-3

const MIN_INCIDENCE := 0.2

const QUANTIZE := 1000.0

var failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for path in EXAMPLES:
		await _test_house(path)

	if failures == 0:
		print("ALL MESH OPTIMIZATION TESTS PASSED")
		quit(0)
	else:
		print("%d MESH OPTIMIZATION TEST FAILURE(S)" % failures)
		quit(1)


func _test_house(path: String) -> void:
	var house: HouseData = HouseFile.load_any(path)
	if house == null:
		_check(path, "example loads", false)
		return

	var label: String = path.get_file()

	house.mesh_optimization = HouseData.MeshOptimization.NONE
	var full: ArrayMesh = HouseMeshBuilder.build(house)

	house.mesh_optimization = HouseData.MeshOptimization.DROP_BURIED
	var reachable: ArrayMesh = HouseMeshBuilder.build(house)

	house.mesh_optimization = HouseData.MeshOptimization.EXTERIOR_ONLY
	var lean: ArrayMesh = HouseMeshBuilder.build(house)

	MeshChecks.check_windings(label, lean, _check)

	var full_keys: Dictionary = _triangle_keys(full)
	var reachable_keys: Dictionary = _triangle_keys(reachable)
	var lean_keys: Dictionary = _triangle_keys(lean)

	_check(label, "each mode is a subset of the looser one (%d >= %d >= %d)" % [
		full_keys.size(), reachable_keys.size(), lean_keys.size(),
	], _is_subset(reachable_keys, full_keys) and _is_subset(lean_keys, reachable_keys))
	_check(label, "dropping buried faces empties no surface", _surface_names(reachable) == _surface_names(full))

	var visible: Dictionary = {}
	for key in await _classify(full, house.grade_y(), true):
		visible[key] = true

	var lean_names: Dictionary = _surface_names(lean)
	var lost_exterior: Array = []
	for key in visible:
		var slot: String = key.split("|")[0]
		if not lean_names.has(slot) and not lost_exterior.has(slot):
			lost_exterior.append(slot)
	_check(label, "no surface with exterior geometry is dropped (%s)" % str(lost_exterior), lost_exterior.is_empty())

	var exposed_buried: Array = []
	for key in full_keys:
		if not reachable_keys.has(key) and visible.has(key):
			exposed_buried.append(key)
	_check(label, "no buried face is reachable from outside (%d exposed)" % exposed_buried.size(), exposed_buried.is_empty())
	for key in exposed_buried.slice(0, 5):
		printerr("      wrongly buried: %s" % key)

	var dropped_visible: Array = []
	for key in visible:
		if not lean_keys.has(key):
			dropped_visible.append(key)

	var lean_unreachable: int = (await _classify(lean, house.grade_y(), false)).size()
	var full_unreachable: int = (await _classify(full, house.grade_y(), false)).size()
	print("      %s: %d -> %d tris; unreachable %d -> %d; interior faces given up: %d" % [
		label, full_keys.size(), lean_keys.size(), full_unreachable, lean_unreachable,
		dropped_visible.size(),
	])
	_check(label, "optimizing leaves less unreachable geometry", lean_unreachable < full_unreachable)


func _surface_names(mesh: ArrayMesh) -> Dictionary:
	var names: Dictionary = {}
	for s in range(mesh.get_surface_count()):
		names[mesh.surface_get_name(s)] = true
	return names


func _is_subset(inner: Dictionary, outer: Dictionary) -> bool:
	for key in inner:
		if not outer.has(key):
			return false
	return true


func _triangle_count(mesh: ArrayMesh) -> int:
	var total: int = 0
	for s in range(mesh.get_surface_count()):
		total += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


func _triangle_key(slot: String, a: Vector3, b: Vector3, c: Vector3) -> String:
	var corners: Array = [_quantize(a), _quantize(b), _quantize(c)]
	corners.sort()
	return "%s|%s|%s|%s" % [slot, corners[0], corners[1], corners[2]]


func _quantize(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x * QUANTIZE), roundi(v.y * QUANTIZE), roundi(v.z * QUANTIZE)]


func _triangle_keys(mesh: ArrayMesh) -> Dictionary:
	var keys: Dictionary = {}
	for s in range(mesh.get_surface_count()):
		var slot: String = mesh.surface_get_name(s)
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3):
			keys[_triangle_key(slot, verts[indices[t]], verts[indices[t + 1]], verts[indices[t + 2]])] = true
	return keys


func _eye_points(mesh: ArrayMesh, grade: float) -> Array[Vector3]:
	var aabb: AABB = mesh.get_aabb()
	var center: Vector3 = aabb.get_center()
	var radius: float = aabb.size.length() * 2.5
	var points: Array[Vector3] = []
	for elevation in [0.0, 0.2, 0.45, 0.75]:
		var y: float = sin(elevation * PI * 0.5)
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		for i in range(12):
			var a: float = TAU * i / 12.0
			var p: Vector3 = center + Vector3(cos(a) * r, y, sin(a) * r) * radius
			if p.y >= grade:
				points.append(p)
	points.append(center + Vector3.UP * radius)
	return points


func _classify(mesh: ArrayMesh, grade: float, want_visible: bool) -> Array:
	var holder := Node3D.new()
	root.add_child(holder)
	var body := StaticBody3D.new()
	holder.add_child(body)
	var shape := CollisionShape3D.new()
	var trimesh: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	trimesh.backface_collision = true
	shape.shape = trimesh
	body.add_child(shape)

	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = holder.get_world_3d().direct_space_state
	var eyes: Array[Vector3] = _eye_points(mesh, grade)

	var result: Array = []
	for s in range(mesh.get_surface_count()):
		var slot: String = mesh.surface_get_name(s)
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3):
			var a: Vector3 = verts[indices[t]]
			var b: Vector3 = verts[indices[t + 1]]
			var c: Vector3 = verts[indices[t + 2]]
			var n: Vector3 = norms[indices[t]].normalized()
			if _is_visible(space, eyes, a, b, c, n, grade) == want_visible:
				result.append(_triangle_key(slot, a, b, c))

	holder.queue_free()
	await process_frame
	return result


func _is_visible(
	space: PhysicsDirectSpaceState3D, eyes: Array[Vector3],
	a: Vector3, b: Vector3, c: Vector3, n: Vector3, grade: float
) -> bool:
	var centroid: Vector3 = (a + b + c) / 3.0
	for sample in [centroid, centroid.lerp(a, 0.6), centroid.lerp(b, 0.6), centroid.lerp(c, 0.6)]:
		var origin: Vector3 = sample + n * SURFACE_OFFSET
		if origin.y < grade:
			continue
		for eye in eyes:
			if n.dot((eye - origin).normalized()) <= MIN_INCIDENCE:
				continue
			var params := PhysicsRayQueryParameters3D.create(origin, eye)
			if space.intersect_ray(params).is_empty():
				return true
	return false


func _check(group: String, name: String, condition: bool) -> void:
	if condition:
		print("PASS [%s] %s" % [group, name])
	else:
		failures += 1
		printerr("FAIL [%s] %s" % [group, name])
