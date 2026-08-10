extends SceneTree


const EPS := 1e-3

var failures: int = 0


func _init() -> void:
	_test_slab_basics()
	_test_expand()
	_test_ring_hole()
	_test_scene_nodes()
	_test_collision()
	_test_garage_keep_notch()
	_test_lower_mode()
	_test_stairs_grade()

	if failures == 0:
		print("ALL SIDEWALK TESTS PASSED")
		quit(0)
	else:
		print("%d SIDEWALK TEST FAILURE(S)" % failures)
		quit(1)


func _bar_house() -> HouseData:
	var house := HouseData.new()
	house.level_cell_size = 2.0
	var floor_data := FloorData.new()
	floor_data.level = 0
	floor_data.height = 3.0
	for x in range(3):
		floor_data.add_cell(Vector2i(x, 0))
	house.add_floor(floor_data)
	return house


func _sidewalk_house() -> HouseData:
	var house := _bar_house()
	house.floors[0].add_sidewalk_cell(Vector2i(0, 1))
	house.floors[0].add_sidewalk_cell(Vector2i(1, 1))
	return house


func _test_slab_basics() -> void:
	var house := _sidewalk_house()
	var mesh: ArrayMesh = SidewalkBuilder.build(house)
	_check("slab", "mesh built", mesh != null)
	if mesh == null:
		return
	_check("slab", "sidewalk surface present", MeshChecks.find_surface(mesh, "sidewalk") >= 0)
	MeshChecks.check_windings("slab", mesh, _check)

	_check("slab", "top surface at grade (-1.0)", absf(MeshChecks.surface_height_at(mesh, "sidewalk", Vector2(1, 3), 1.0) - (-1.0)) < EPS)
	_check("slab", "bottom surface a thickness below (-1.2)", absf(MeshChecks.surface_height_at(mesh, "sidewalk", Vector2(1, 3), -1.0) - (-1.2)) < EPS)
	_check("slab", "top area covers both cells", absf(MeshChecks.facing_area(mesh, "sidewalk", Vector3.UP) - 8.0) < EPS)
	_check("slab", "south skirt spans length x thickness", absf(MeshChecks.facing_area(mesh, "sidewalk", Vector3(0, 0, 1)) - 4.0 * 0.2) < EPS)

	var house_mesh: ArrayMesh = HouseMeshBuilder.build(house)
	_check("slab", "house mesh has no sidewalk surface", MeshChecks.find_surface(house_mesh, "sidewalk") == -1)


func _test_expand() -> void:
	var house := _sidewalk_house()
	house.sidewalk_expand = 0.3
	var mesh: ArrayMesh = SidewalkBuilder.build(house)
	_check("expand", "grown slab built", mesh != null)
	if mesh != null:
		_check("expand", "grown top reaches (1, 4.2)", absf(MeshChecks.surface_height_at(mesh, "sidewalk", Vector2(1, 4.2), 1.0) - (-1.0)) < EPS)
		_check("expand", "grown top reaches (-0.25, 3)", absf(MeshChecks.surface_height_at(mesh, "sidewalk", Vector2(-0.25, 3), 1.0) - (-1.0)) < EPS)
		_check("expand", "grown top area 4.6 x 2.6", absf(MeshChecks.facing_area(mesh, "sidewalk", Vector3.UP) - 4.6 * 2.6) < EPS)

	house.sidewalk_expand = -0.4
	mesh = SidewalkBuilder.build(house)
	_check("expand", "shrunk slab built", mesh != null)
	if mesh != null:
		_check("expand", "shrunk top absent at (1, 3.9)", MeshChecks.surface_height_at(mesh, "sidewalk", Vector2(1, 3.9), 1.0) == -INF)
		_check("expand", "shrunk top present at (1, 3)", absf(MeshChecks.surface_height_at(mesh, "sidewalk", Vector2(1, 3), 1.0) - (-1.0)) < EPS)
		_check("expand", "shrunk top area 3.2 x 1.2", absf(MeshChecks.facing_area(mesh, "sidewalk", Vector3.UP) - 3.2 * 1.2) < EPS)

	var tiny := _bar_house()
	tiny.floors[0].add_sidewalk_cell(Vector2i(0, 1))
	tiny.sidewalk_expand = -1.0
	_check("expand", "fully shrunk slab collapses to null", SidewalkBuilder.build(tiny) == null)


func _test_ring_hole() -> void:
	var house := _bar_house()
	var floor_data: FloorData = house.floors[0]
	for cell in [
		Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0),
		Vector2i(4, 1), Vector2i(6, 1),
		Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2),
	]:
		floor_data.add_sidewalk_cell(cell)

	var mesh: ArrayMesh = SidewalkBuilder.build(house)
	_check("ring", "ring slab built", mesh != null)
	if mesh == null:
		return
	MeshChecks.check_windings("ring", mesh, _check)
	_check("ring", "hole center is open", MeshChecks.surface_height_at(mesh, "sidewalk", Vector2(11, 3), 1.0) == -INF)
	_check("ring", "ring band is solid", absf(MeshChecks.surface_height_at(mesh, "sidewalk", Vector2(9, 1), 1.0) - (-1.0)) < EPS)
	_check("ring", "ring top area is 8 cells", absf(MeshChecks.facing_area(mesh, "sidewalk", Vector3.UP) - 32.0) < EPS)

	house.sidewalk_expand = 0.5
	mesh = SidewalkBuilder.build(house)
	_check("ring", "grown ring built", mesh != null)
	if mesh == null:
		return
	MeshChecks.check_windings("ring grown", mesh, _check)
	_check("ring", "hole shrank (solid at its old rim)", absf(MeshChecks.surface_height_at(mesh, "sidewalk", Vector2(10.2, 3), 1.0) - (-1.0)) < EPS)
	_check("ring", "hole center still open", MeshChecks.surface_height_at(mesh, "sidewalk", Vector2(11, 3), 1.0) == -INF)
	_check("ring", "grown ring area 7x7 minus 1x1 hole", absf(MeshChecks.facing_area(mesh, "sidewalk", Vector3.UP) - 48.0) < EPS)


func _test_scene_nodes() -> void:
	var house := _sidewalk_house()
	var building: Node3D = HouseSceneBuilder.build(house)
	var house_mesh: MeshInstance3D = building.get_node_or_null("HouseMesh")
	var sidewalk_mesh: MeshInstance3D = building.get_node_or_null("SidewalkMesh")
	_check("scene", "HouseMesh present", house_mesh != null)
	_check("scene", "SidewalkMesh present", sidewalk_mesh != null)
	_check("scene", "StaticBody3D present", building.get_node_or_null("StaticBody3D") != null)
	if house_mesh != null and sidewalk_mesh != null:
		_check("scene", "sidewalk shares the house's recenter shift", sidewalk_mesh.position.is_equal_approx(house_mesh.position))
		_check("scene", "sidewalk mesh carries the sidewalk surface", MeshChecks.find_surface(sidewalk_mesh.mesh, "sidewalk") >= 0)
	building.free()

	var plain: Node3D = HouseSceneBuilder.build(_bar_house())
	_check("scene", "no sidewalk cells, no SidewalkMesh node", plain.get_node_or_null("SidewalkMesh") == null)
	_check("scene", "plain house still has its HouseMesh", plain.get_node_or_null("HouseMesh") != null)
	plain.free()


func _test_collision() -> void:
	var house := _sidewalk_house()
	var shapes: Array[Dictionary] = _build_shapes(house)
	var boxes: Array[Dictionary] = _entries_named(shapes, "Sidewalk")
	_check("collision", "one sidewalk box", boxes.size() == 1)
	if boxes.size() == 1:
		var shape: BoxShape3D = boxes[0]["shape"]
		_check("collision", "box size (4, 0.2, 2)", shape.size.is_equal_approx(Vector3(4, 0.2, 2)))
		_check("collision", "box centered at (2, -1.1, 3)", boxes[0]["transform"].origin.is_equal_approx(Vector3(2, -1.1, 3)))

	house.sidewalk_expand = 0.3
	boxes = _entries_named(_build_shapes(house), "Sidewalk")
	_check("collision", "expanded box present", boxes.size() == 1)
	if boxes.size() == 1:
		var shape: BoxShape3D = boxes[0]["shape"]
		_check("collision", "expanded box size (4.6, 0.2, 2.6)", shape.size.is_equal_approx(Vector3(4.6, 0.2, 2.6)))


func _test_garage_keep_notch() -> void:
	var house := _garage_house()
	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("keep_notch", mesh, _check)

	var openings: Array[Dictionary] = WallOpenings.collect(house, house.floors[0], 0.0, true)
	_check("keep_notch", "one opening", openings.size() == 1)
	if openings.size() != 1:
		return
	var op: Dictionary = openings[0]
	_check("keep_notch", "opening bottom at grade", absf(op["bottom_y"] - (-1.0)) < EPS)
	_check("keep_notch", "opening lintel unchanged", absf(op["top_y"] - 2.2) < EPS)
	_check("keep_notch", "opening spans x 2.2..5.8", absf(minf(op["a"].x, op["b"].x) - 2.2) < EPS and absf(maxf(op["a"].x, op["b"].x) - 5.8) < EPS)

	_check("keep_notch", "garage panels reach grade", absf(_surface_min_y(mesh, "garage_door") - (-1.0)) < EPS)
	_check("keep_notch", "casing reaches grade", absf(_surface_min_y(mesh, "window_frame") - (-1.0)) < EPS)

	var south_face: float = MeshChecks.facing_area(mesh, "foundation", Vector3(0, 0, 1), func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z - 2.15) < 0.01 and absf(b.z - 2.15) < 0.01 and absf(c.z - 2.15) < 0.01)
	_check("keep_notch", "foundation south face cut by the notch", absf(south_face - (6.3 - 3.6) * 0.4) < EPS)

	var jamb: float = MeshChecks.facing_area(mesh, "foundation", Vector3(1, 0, 0), func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.x - 2.2) < 0.01 and absf(b.x - 2.2) < 0.01 and absf(c.x - 2.2) < 0.01)
	_check("keep_notch", "foundation jamb reveal at x=2.2", absf(jamb - 0.25 * 0.4) < EPS)

	_check("keep_notch", "foundation top cap cut over the notch", MeshChecks.surface_height_at(mesh, "foundation", Vector2(4.0, 2.05), 1.0) == -INF)
	_check("keep_notch", "foundation top cap intact beside the notch", absf(MeshChecks.surface_height_at(mesh, "foundation", Vector2(1.0, 2.05), 1.0)) < EPS)

	var shallow := _garage_house()
	shallow.sidewalk_drop = 0.3
	var shallow_mesh: ArrayMesh = HouseMeshBuilder.build(shallow)
	MeshChecks.check_windings("keep_notch shallow", shallow_mesh, _check)
	_check("keep_notch", "shallow notch threshold at -0.3", absf(MeshChecks.surface_height_at(shallow_mesh, "foundation", Vector2(4.0, 2.05), 1.0) - (-0.3)) < EPS)
	_check("keep_notch", "shallow garage panels reach -0.3", absf(_surface_min_y(shallow_mesh, "garage_door") - (-0.3)) < EPS)


func _test_lower_mode() -> void:
	var house := _garage_house()
	house.foundation_mode = HouseData.FoundationMode.LOWER
	var door := WallDetail.create(WallDetail.DetailType.DOOR, 0, house)
	door.cell = Vector2i(0, 0)
	door.direction = WallDetail.EdgeDir.NORTH
	house.floors[0].set_wall_detail(door)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("lower", mesh, _check)
	_check("lower", "siding extends to grade", absf(_surface_min_y(mesh, "siding") - (-1.0)) < EPS)
	_check("lower", "door bottom stays at the floor", absf(_surface_min_y(mesh, "door")) < EPS)
	_check("lower", "garage panels reach grade", absf(_surface_min_y(mesh, "garage_door") - (-1.0)) < EPS)
	_check("lower", "trim posts reach grade", absf(_surface_min_y(mesh, "trim") - (-1.0)) < EPS)
	_check("lower", "foundation top at grade", absf(_surface_max_y(mesh, "foundation") - (-1.0)) < EPS)
	_check("lower", "foundation base a band below", absf(_surface_min_y(mesh, "foundation") - (-1.4)) < EPS)

	var south_face: float = MeshChecks.facing_area(mesh, "foundation", Vector3(0, 0, 1), func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z - 2.15) < 0.01 and absf(b.z - 2.15) < 0.01 and absf(c.z - 2.15) < 0.01)
	_check("lower", "foundation south face intact", absf(south_face - 6.3 * 0.4) < EPS)

	var boxes: Array[Dictionary] = _entries_named(_build_shapes(house), "Floor0")
	_check("lower", "one floor box", boxes.size() == 1)
	if boxes.size() == 1:
		var shape: BoxShape3D = boxes[0]["shape"]
		_check("lower", "floor box spans down to the lowered foundation", absf(shape.size.y - (3.0 + 1.4)) < EPS)


func _test_stairs_grade() -> void:
	var house := _bar_house()
	house.porch_has_roof = false
	var floor_data: FloorData = house.floors[0]
	floor_data.add_porch_cell(Vector2i(0, 1))
	floor_data.add_porch_cell(Vector2i(1, 1))
	var stairs := WallDetail.create(WallDetail.DetailType.STAIRS, 0, house)
	stairs.cell = Vector2i(0, 1)
	stairs.direction = WallDetail.EdgeDir.SOUTH
	floor_data.set_wall_detail(stairs)

	var runs: Array[Dictionary] = PorchBuilder.stair_runs(house, floor_data)
	_check("stairs", "one stair run", runs.size() == 1)
	if runs.size() == 1:
		_check("stairs", "stairs land on grade", absf(runs[0]["base_y"] - (-1.0)) < EPS)
		_check("stairs", "run length matches 4 treads", absf(runs[0]["run"] - (4 * house.stair_default_step_depth + house.porch_floor_overhang)) < EPS)
	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("stairs", mesh, _check)
	_check("stairs", "no tread lies on the grade the slab tops out at", absf(_surface_min_y(mesh, "porch_floor") - (-1.0 + 0.19 - house.porch_floor_thickness)) < EPS)

	house.sidewalk_drop = 0.03
	_check("stairs", "tiny drop generates no stairs", PorchBuilder.stair_runs(house, floor_data).is_empty())

	house.sidewalk_drop = -0.5
	_check("stairs", "negative drop generates no stairs", PorchBuilder.stair_runs(house, floor_data).is_empty())
	floor_data.add_sidewalk_cell(Vector2i(2, 1))
	var slab: ArrayMesh = SidewalkBuilder.build(house)
	_check("stairs", "negative drop slab sits above the floor", slab != null and absf(MeshChecks.surface_height_at(slab, "sidewalk", Vector2(5, 3), 1.0) - 0.5) < EPS)


func _garage_house() -> HouseData:
	var house := _bar_house()
	var garage := WallDetail.create(WallDetail.DetailType.GARAGE_DOOR, 0, house)
	garage.cell = Vector2i(1, 0)
	garage.direction = WallDetail.EdgeDir.SOUTH
	garage.span = 2
	garage.apply_span_defaults(house.level_cell_size)
	house.floors[0].set_wall_detail(garage)
	return house


func _build_shapes(house: HouseData) -> Array[Dictionary]:
	var built: Dictionary = HouseMeshBuilder.build_with_roof_models(house)
	return HouseCollisionBuilder.build(house, built["roof_models"])


func _entries_named(shapes: Array[Dictionary], name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in shapes:
		if entry["name"] == name:
			result.append(entry)
	return result


func _surface_min_y(mesh: ArrayMesh, slot: String) -> float:
	var arrays: Array = MeshChecks.surface_arrays(mesh, slot)
	if arrays.is_empty():
		return INF
	var min_y: float = INF
	for v in arrays[Mesh.ARRAY_VERTEX]:
		min_y = minf(min_y, v.y)
	return min_y


func _surface_max_y(mesh: ArrayMesh, slot: String) -> float:
	var arrays: Array = MeshChecks.surface_arrays(mesh, slot)
	if arrays.is_empty():
		return -INF
	var max_y: float = -INF
	for v in arrays[Mesh.ARRAY_VERTEX]:
		max_y = maxf(max_y, v.y)
	return max_y


func _check(group: String, name: String, condition: bool) -> void:
	if condition:
		print("PASS [%s] %s" % [group, name])
	else:
		failures += 1
		printerr("FAIL [%s] %s" % [group, name])
