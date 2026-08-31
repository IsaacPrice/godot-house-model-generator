extends SceneTree


const EPS := 1e-3

var failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_deck_coverage()
	_test_multi_storey_decks()
	_test_interior_wall_slot()
	_test_baseboards()
	_test_window_casing_and_stool()
	_test_roof_underside()
	_test_gable_interior()
	_test_glass_slab()
	_test_optimization_modes()
	await _test_enclosure()

	if failures == 0:
		print("ALL INTERIOR TESTS PASSED")
		quit(0)
	else:
		print("%d INTERIOR TEST FAILURE(S)" % failures)
		quit(1)


func _house(cells: Array[Vector2i], levels: int = 1) -> HouseData:
	var house := HouseData.new()
	house.level_cell_size = 2.0
	house.wall_thickness = 0.2
	house.interior_floor_thickness = 0.2
	for level in range(levels):
		var floor_data := FloorData.new()
		floor_data.level = level
		floor_data.height = 3.0
		for cell in cells:
			floor_data.add_cell(cell)
		house.add_floor(floor_data)
	return house


func _test_deck_coverage() -> void:
	var house: HouseData = _house([Vector2i(0, 0), Vector2i(1, 0)])
	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("decks", mesh, _check)

	var cell_area: float = 2.0 * 2.0 * 2.0

	for entry in [[0.0, "ground floor"], [3.0, "attic floor"]]:
		var y: float = entry[0]
		var area: float = MeshChecks.facing_area(
			mesh, InteriorBuilder.SLOT_FLOOR, Vector3(0, 1, 0), _at_height(y))
		_check("decks", "%s covers the footprint (%.3f)" % [entry[1], area], absf(area - cell_area) < EPS)

	for entry in [[-0.2, "crawlspace underside"], [2.8, "top floor ceiling"]]:
		var y: float = entry[0]
		var area: float = MeshChecks.facing_area(
			mesh, InteriorBuilder.SLOT_CEILING, Vector3(0, -1, 0), _at_height(y))
		_check("decks", "%s covers the footprint (%.3f)" % [entry[1], area], absf(area - cell_area) < EPS)

	var seam: Callable = func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.x - 2.0) < EPS and absf(b.x - 2.0) < EPS and absf(c.x - 2.0) < EPS
	var seam_area: float = MeshChecks.facing_area(mesh, InteriorBuilder.SLOT_FLOOR, Vector3(1, 0, 0), seam)
	_check("decks", "no deck side wall between adjacent cells (%.3f)" % seam_area, seam_area < EPS)


func _test_multi_storey_decks() -> void:
	var house: HouseData = _house([Vector2i(0, 0)], 2)
	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("multi_storey", mesh, _check)

	var levels: Dictionary = {}
	var arrays: Array = MeshChecks.surface_arrays(mesh, InteriorBuilder.SLOT_FLOOR)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for t in range(0, indices.size(), 3):
		if norms[indices[t]].dot(Vector3(0, 1, 0)) > 0.99:
			levels[roundi(verts[indices[t]].y * 1000.0)] = true

	_check("multi_storey", "one floor deck per level boundary (%d)" % levels.size(), levels.size() == 3)
	for y in [0, 3000, 6000]:
		_check("multi_storey", "floor deck at y=%.1f" % (y / 1000.0), levels.has(y))


func _test_interior_wall_slot() -> void:
	var house: HouseData = _house([Vector2i(0, 0)])
	var mesh: ArrayMesh = HouseMeshBuilder.build(house)

	_check("interior_wall", "wall inner faces get their own surface",
		MeshChecks.find_surface(mesh, InteriorBuilder.SLOT_WALL) >= 0)

	var inward: float = MeshChecks.facing_area(mesh, InteriorBuilder.SLOT_WALL, Vector3(0, 0, 1))
	_check("interior_wall", "north wall inner face is 1.8 x 3.0 (%.3f)" % inward, absf(inward - 1.8 * 3.0) < EPS)

	var siding_inward: float = MeshChecks.facing_area(mesh, WallBuilder.SLOT_SIDING, Vector3(0, 0, 1), _behind(0.0))
	_check("interior_wall", "siding keeps no inward run (%.3f)" % siding_inward, siding_inward < EPS)


func _test_baseboards() -> void:
	var house: HouseData = _house([Vector2i(0, 0), Vector2i(1, 0)])
	var floor_data: FloorData = house.floors[0]
	var door := WallDetail.create(WallDetail.DetailType.DOOR, 0, house)
	door.cell = Vector2i(0, 0)
	door.direction = WallDetail.EdgeDir.NORTH
	floor_data.set_wall_detail(door)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("baseboard", mesh, _check)

	_check("baseboard", "interior trim surface exists",
		MeshChecks.find_surface(mesh, InteriorBuilder.SLOT_TRIM) >= 0)

	var top: float = house.interior_base_trim_height
	var arrays: Array = MeshChecks.surface_arrays(mesh, InteriorBuilder.SLOT_TRIM)
	var in_doorway := false
	var min_x: float = INF
	var max_x: float = -INF
	for v in arrays[Mesh.ARRAY_VERTEX]:
		if v.y > top + EPS or absf(v.z - 0.1) > 0.1 + EPS:
			continue
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
		if v.x > 0.5 + house.interior_casing_width + EPS and v.x < 1.5 - house.interior_casing_width - EPS:
			in_doorway = true

	_check("baseboard", "baseboard runs the north wall (%.2f .. %.2f)" % [min_x, max_x],
		min_x < 0.5 and max_x > 3.5)
	_check("baseboard", "baseboard stops at the door casing", not in_doorway)


func _test_window_casing_and_stool() -> void:
	var house: HouseData = _house([Vector2i(0, 0), Vector2i(1, 0)])
	var window := WallDetail.create(WallDetail.DetailType.WINDOW, 0, house)
	window.cell = Vector2i(0, 0)
	window.direction = WallDetail.EdgeDir.NORTH
	house.floors[0].set_wall_detail(window)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("casing", mesh, _check)

	var casing_front: float = house.wall_thickness * 0.5 + house.interior_casing_depth
	var inward: float = MeshChecks.facing_area(
		mesh, InteriorBuilder.SLOT_TRIM, Vector3(0, 0, 1),
		func(a: Vector3, b: Vector3, c: Vector3) -> bool:
			return absf(a.z - casing_front) < EPS and a.y > house.interior_base_trim_height)
	_check("casing", "window casing faces into the room (%.4f)" % inward, inward > 0.0)

	var stool_top: float = window.sill_height
	var stool: float = MeshChecks.facing_area(
		mesh, InteriorBuilder.SLOT_TRIM, Vector3(0, 1, 0), _at_height(stool_top))
	_check("casing", "window stool caps the sill from inside (%.4f)" % stool, stool > 0.0)


func _test_roof_underside() -> void:
	var house: HouseData = _house([Vector2i(0, 0), Vector2i(1, 0)])
	house.roof_pitch_degrees = 30.0
	var mesh: ArrayMesh = HouseMeshBuilder.build(house)

	var arrays: Array = MeshChecks.surface_arrays(mesh, InteriorBuilder.SLOT_CEILING)
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var sloped: int = 0
	for t in range(0, indices.size(), 3):
		var n: Vector3 = norms[indices[t]]
		if n.y < -EPS and n.y > -0.99:
			sloped += 1
	_check("roof_underside", "pitched roof gets a sloped underside (%d tris)" % sloped, sloped > 0)

	var ridge: float = MeshChecks.surface_height_at(mesh, RoofSurface.SLOT_SHINGLES, Vector2(2.0, 2.0), 1.0)
	var under: float = MeshChecks.surface_height_at(mesh, InteriorBuilder.SLOT_CEILING, Vector2(2.0, 2.0), -1.0)
	_check("roof_underside", "underside hangs a deck thickness below the shingles (%.3f)" % (ridge - under),
		absf((ridge - under) - house.roof_deck_thickness) < EPS)


func _test_gable_interior() -> void:
	var house: HouseData = _house([Vector2i(0, 0), Vector2i(1, 0)])
	var gable := GableData.new()
	gable.cell = Vector2i(0, 0)
	gable.direction = WallDetail.EdgeDir.WEST
	house.floors[0].gables.append(gable)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("gable_interior", mesh, _check)

	var above_walls: Callable = func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return maxf(a.y, maxf(b.y, c.y)) > 3.0 + EPS
	var outward: float = MeshChecks.facing_area(mesh, RoofSurface.SLOT_GABLE, Vector3(-1, 0, 0), above_walls)
	var inward: float = MeshChecks.facing_area(mesh, InteriorBuilder.SLOT_CEILING, Vector3(1, 0, 0), above_walls)
	_check("gable_interior", "gable end is closed from inside (%.3f vs %.3f)" % [outward, inward],
		outward > 0.0 and absf(outward - inward) < EPS)


func _test_glass_slab() -> void:
	var house: HouseData = _house([Vector2i(0, 0), Vector2i(1, 0)])
	var window := WallDetail.create(WallDetail.DetailType.WINDOW, 0, house)
	window.cell = Vector2i(0, 0)
	window.direction = WallDetail.EdgeDir.NORTH
	house.floors[0].set_wall_detail(window)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	var half: float = DetailConstants.GLASS_THICKNESS * 0.5

	var outer: float = MeshChecks.facing_area(mesh, WindowBuilder.SLOT_GLASS, Vector3(0, 0, -1), _behind(-half))
	var inner: float = MeshChecks.facing_area(mesh, WindowBuilder.SLOT_GLASS, Vector3(0, 0, 1), _behind(half))
	_check("glass", "outer pane sits proud of the centreline (%.4f)" % outer, outer > 0.0)
	_check("glass", "inner pane matches it (%.4f)" % inner, absf(outer - inner) < EPS)


func _test_optimization_modes() -> void:
	var house: HouseData = _house([Vector2i(0, 0), Vector2i(1, 0)])
	var interior_slots: Array[String] = [
		InteriorBuilder.SLOT_WALL, InteriorBuilder.SLOT_FLOOR,
		InteriorBuilder.SLOT_CEILING, InteriorBuilder.SLOT_TRIM,
	]

	house.mesh_optimization = HouseData.MeshOptimization.DROP_BURIED
	var reachable: ArrayMesh = HouseMeshBuilder.build(house)
	for slot in interior_slots:
		_check("optimization", "'%s' survives DROP_BURIED" % slot, MeshChecks.find_surface(reachable, slot) >= 0)

	house.mesh_optimization = HouseData.MeshOptimization.EXTERIOR_ONLY
	var lean: ArrayMesh = HouseMeshBuilder.build(house)
	for slot in interior_slots:
		_check("optimization", "'%s' is dropped by EXTERIOR_ONLY" % slot, MeshChecks.find_surface(lean, slot) < 0)
	MeshChecks.check_windings("optimization", lean, _check)


func _test_enclosure() -> void:
	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]

	var plain: HouseData = _house(cells)
	await _check_sealed("bare shell", plain, Vector3(2.0, 1.5, 2.0))

	var dressed: HouseData = _house(cells)
	var window := WallDetail.create(WallDetail.DetailType.WINDOW, 0, dressed)
	window.cell = Vector2i(0, 0)
	window.direction = WallDetail.EdgeDir.NORTH
	dressed.floors[0].set_wall_detail(window)
	var door := WallDetail.create(WallDetail.DetailType.DOOR, 0, dressed)
	door.cell = Vector2i(1, 0)
	door.direction = WallDetail.EdgeDir.NORTH
	dressed.floors[0].set_wall_detail(door)
	await _check_sealed("window and door", dressed, Vector3(2.0, 1.5, 2.0))

	var storeys: HouseData = _house(cells, 2)
	await _check_sealed("upper storey", storeys, Vector3(2.0, 4.5, 2.0))

	var garage: HouseData = _house(cells)
	garage.sidewalk_drop = 0.3
	garage.foundation_height = 0.5
	garage.floors[0].add_garage_cell(Vector2i(0, 0))
	var bay_door := WallDetail.create(WallDetail.DetailType.GARAGE_DOOR, 0, garage)
	bay_door.cell = Vector2i(0, 0)
	bay_door.direction = WallDetail.EdgeDir.NORTH
	garage.floors[0].set_wall_detail(bay_door)
	await _check_sealed("sunken garage bay", garage, Vector3(1.0, 1.0, 1.0))

	var bay_decks: Dictionary = {}
	var arrays: Array = MeshChecks.surface_arrays(HouseMeshBuilder.build(garage), InteriorBuilder.SLOT_FLOOR)
	for v in arrays[Mesh.ARRAY_VERTEX]:
		if v.x < 2.0 - EPS and v.z < 2.0 - EPS:
			bay_decks[roundi(v.y * 1000.0)] = true
	_check("enclosure", "bay floor drops to grade", bay_decks.has(roundi(garage.grade_y() * 1000.0)))


func _check_sealed(label: String, house: HouseData, eye: Vector3) -> void:
	var mesh: ArrayMesh = HouseMeshBuilder.build(house)

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

	var escaped: int = 0
	var total: int = 0
	for elevation in [-0.9, -0.5, 0.0, 0.5, 0.9]:
		var y: float = elevation
		var r: float = sqrt(maxf(0.0, 1.0 - y * y))
		for i in range(16):
			var angle: float = TAU * i / 16.0
			var direction := Vector3(cos(angle) * r, y, sin(angle) * r)
			total += 1
			var params := PhysicsRayQueryParameters3D.create(eye, eye + direction * 200.0)
			if space.intersect_ray(params).is_empty():
				escaped += 1

	_check("enclosure", "%s: no ray escapes the interior (%d/%d)" % [label, escaped, total], escaped == 0)

	holder.queue_free()
	await process_frame


func _at_height(y: float) -> Callable:
	return func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.y - y) < EPS and absf(b.y - y) < EPS and absf(c.y - y) < EPS


func _behind(z: float) -> Callable:
	return func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z - z) < EPS and absf(b.z - z) < EPS and absf(c.z - z) < EPS


func _check(group: String, name: String, condition: bool) -> void:
	if condition:
		print("PASS [%s] %s" % [group, name])
	else:
		failures += 1
		printerr("FAIL [%s] %s" % [group, name])
