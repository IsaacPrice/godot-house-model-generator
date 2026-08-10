extends SceneTree


const EPS := 1e-3

var failures: int = 0


func _init() -> void:
	_test_empty_house()
	_test_bar_house_shapes()
	_test_l_footprint_merges_to_two_boxes()
	_test_two_floor_boxes()
	_test_porch_and_stairs()
	_test_gable_roof_collision()

	if failures == 0:
		print("ALL COLLISION TESTS PASSED")
		quit(0)
	else:
		print("%d COLLISION TEST FAILURE(S)" % failures)
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


func _build_shapes(house: HouseData) -> Array[Dictionary]:
	var built: Dictionary = HouseMeshBuilder.build_with_roof_models(house)
	return HouseCollisionBuilder.build(house, built["roof_models"])


func _entries_named(shapes: Array[Dictionary], name: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for entry in shapes:
		if entry["name"] == name:
			found.append(entry)
	return found


func _test_empty_house() -> void:
	_check("empty", "no floors produces no shapes", _build_shapes(HouseData.new()).is_empty())


func _test_bar_house_shapes() -> void:
	var house := _bar_house()
	var shapes: Array[Dictionary] = _build_shapes(house)

	_check("bar", "exactly 2 shapes, got %d" % shapes.size(), shapes.size() == 2)

	var boxes: Array[Dictionary] = _entries_named(shapes, "Floor0")
	_check("bar", "one merged floor box", boxes.size() == 1)
	if boxes.size() == 1:
		var shape: BoxShape3D = boxes[0]["shape"]
		var transform: Transform3D = boxes[0]["transform"]
		_check("bar", "box size %s" % shape.size, shape.size.is_equal_approx(Vector3(6.2, 3.0 + house.foundation_height, 2.2)))
		var expected_center := Vector3(3.0, (3.0 - house.foundation_height) * 0.5, 1.0)
		_check("bar", "box center %s" % transform.origin, transform.origin.is_equal_approx(expected_center))

	var roofs: Array[Dictionary] = _entries_named(shapes, "Roof")
	_check("bar", "one roof shape", roofs.size() == 1)
	if roofs.size() == 1:
		var roof: ConcavePolygonShape3D = roofs[0]["shape"]
		_check("bar", "roof collides both-sided", roof.backface_collision)
		var faces: PackedVector3Array = roof.get_faces()
		_check("bar", "roof has whole triangles", faces.size() > 0 and faces.size() % 3 == 0)
		var min_y: float = INF
		var max_y: float = -INF
		for p in faces:
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
		_check("bar", "roof faces stay near the top (min y %.2f)" % min_y, min_y > 2.0)
		_check("bar", "ridge rises above the walls (max y %.2f)" % max_y, max_y > 3.0)


func _test_l_footprint_merges_to_two_boxes() -> void:
	var house := HouseData.new()
	var floor_data := FloorData.new()
	floor_data.level = 0
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		floor_data.add_cell(cell)
	house.add_floor(floor_data)

	var boxes: Array[Dictionary] = _entries_named(_build_shapes(house), "Floor0")
	_check("l_shape", "L footprint merges to 2 boxes, got %d" % boxes.size(), boxes.size() == 2)


func _test_two_floor_boxes() -> void:
	var house := _bar_house()
	var upper := FloorData.new()
	upper.level = 1
	upper.height = 2.6
	upper.add_cell(Vector2i(0, 0))
	upper.add_cell(Vector2i(1, 0))
	house.add_floor(upper)

	var shapes: Array[Dictionary] = _build_shapes(house)
	var upper_boxes: Array[Dictionary] = _entries_named(shapes, "Floor1")
	_check("two_floor", "one upper box", upper_boxes.size() == 1)
	if upper_boxes.size() == 1:
		var shape: BoxShape3D = upper_boxes[0]["shape"]
		var transform: Transform3D = upper_boxes[0]["transform"]
		_check("two_floor", "upper box size %s" % shape.size, shape.size.is_equal_approx(Vector3(4.2, 2.6, 2.2)))
		_check("two_floor", "upper box center %s" % transform.origin, transform.origin.is_equal_approx(Vector3(2.0, 3.0 + 1.3, 1.0)))


func _test_porch_and_stairs() -> void:
	var house := _bar_house()
	house.sidewalk_drop = house.foundation_height
	house.porch_has_roof = false
	house.porch_floor_overhang = 0.0
	var floor_data: FloorData = house.floors[0]
	floor_data.add_porch_cell(Vector2i(0, 1))
	floor_data.add_porch_cell(Vector2i(1, 1))
	var stairs := WallDetail.create(WallDetail.DetailType.STAIRS)
	stairs.cell = Vector2i(0, 1)
	stairs.direction = WallDetail.EdgeDir.SOUTH
	stairs.stair_has_railing = true
	floor_data.set_wall_detail(stairs)

	var shapes: Array[Dictionary] = _build_shapes(house)

	var porch_boxes: Array[Dictionary] = _entries_named(shapes, "Porch")
	_check("porch", "one merged porch box", porch_boxes.size() == 1)
	if porch_boxes.size() == 1:
		var shape: BoxShape3D = porch_boxes[0]["shape"]
		var transform: Transform3D = porch_boxes[0]["transform"]
		var top_y: float = transform.origin.y + shape.size.y * 0.5
		var bottom_y: float = transform.origin.y - shape.size.y * 0.5
		_check("porch", "deck top at %.3f" % top_y, absf(top_y - (-DetailConstants.PORCH_DROP)) < EPS)
		_check("porch", "skirt reaches the foundation base", absf(bottom_y - (-house.foundation_height)) < EPS)
		_check("porch", "porch box plan size %s" % shape.size, absf(shape.size.x - 4.0) < EPS and absf(shape.size.z - 2.0) < EPS)

	var ramps: Array[Dictionary] = _entries_named(shapes, "StairRamp")
	_check("stairs", "one stair ramp", ramps.size() == 1)
	if ramps.size() == 1:
		var shape: ConvexPolygonShape3D = ramps[0]["shape"]
		_check("stairs", "ramp is a 6-point prism", shape.points.size() == 6)
		var min_y: float = INF
		var max_y: float = -INF
		var max_z: float = -INF
		for p in shape.points:
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
			max_z = maxf(max_z, p.z)
		_check("stairs", "ramp top at the deck surface", absf(max_y - (-DetailConstants.PORCH_DROP)) < EPS)
		_check("stairs", "ramp lands on grade", absf(min_y - (-house.foundation_height)) < EPS)
		_check("stairs", "ramp runs to the lowest tread's front (z %.2f)" % max_z, absf(max_z - 4.3) < EPS)

	var railings: Array[Dictionary] = _entries_named(shapes, "Railing")
	_check("railing", "three level railing boxes, got %d" % railings.size(), railings.size() == 3)
	for entry in railings:
		var shape: BoxShape3D = entry["shape"]
		var transform: Transform3D = entry["transform"]
		var top_y: float = transform.origin.y + shape.size.y * 0.5
		var bottom_y: float = transform.origin.y - shape.size.y * 0.5
		_check("railing", "box bottom at the deck surface", absf(bottom_y - (-DetailConstants.PORCH_DROP)) < EPS)
		_check("railing", "box top railing-height above the deck", absf(top_y - (-DetailConstants.PORCH_DROP + house.porch_railing_height)) < EPS)
		_check("railing", "box is one post width thick", absf(minf(shape.size.x, shape.size.z) - house.porch_post_width) < EPS)

	var stair_railings: Array[Dictionary] = _entries_named(shapes, "StairRailing")
	_check("stair_railing", "two stair railing prisms, got %d" % stair_railings.size(), stair_railings.size() == 2)
	for entry in stair_railings:
		var shape: ConvexPolygonShape3D = entry["shape"]
		_check("stair_railing", "prism has 8 points", shape.points.size() == 8)
		var min_y: float = INF
		var max_y: float = -INF
		for p in shape.points:
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
		_check("stair_railing", "prism bottom lands on grade", absf(min_y - (-house.foundation_height)) < EPS)
		_check("stair_railing", "prism top railing-height above the deck", absf(max_y - (-DetailConstants.PORCH_DROP + house.porch_railing_height)) < EPS)


func _test_gable_roof_collision() -> void:
	var house := _bar_house()
	var gable := GableData.new()
	gable.cell = Vector2i(0, 0)
	gable.direction = WallDetail.EdgeDir.WEST
	house.floors[0].gables.append(gable)

	var roofs: Array[Dictionary] = _entries_named(_build_shapes(house), "Roof")
	_check("gable", "one roof shape", roofs.size() == 1)
	if roofs.size() != 1:
		return
	var shape: ConcavePolygonShape3D = roofs[0]["shape"]
	var faces: PackedVector3Array = shape.get_faces()

	var gable_face_verts: int = 0
	var peak: float = -INF
	for i in range(0, faces.size(), 3):
		var on_gable_plane := true
		for k in range(3):
			if absf(faces[i + k].x + 0.1) > EPS:
				on_gable_plane = false
		if on_gable_plane:
			gable_face_verts += 3
			for k in range(3):
				peak = maxf(peak, faces[i + k].y)
	_check("gable", "gable end triangles in the roof shape", gable_face_verts >= 3)
	_check("gable", "gable peak above the wall top (y %.2f)" % peak, peak > 3.0)


func _check(shape: String, what: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("FAIL [%s] %s" % [shape, what])
