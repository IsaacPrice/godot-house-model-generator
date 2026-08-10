extends SceneTree


const EPS := 1e-3

var failures: int = 0


func _init() -> void:
	_test_shape("square", PackedVector2Array([
		Vector2(0, 0), Vector2(8, 0), Vector2(8, 8), Vector2(0, 8),
	]), {"valleys": 0, "ridges": 0, "max_offset": 4.0})

	_test_shape("rectangle", PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 6), Vector2(0, 6),
	]), {"valleys": 0, "ridges": 1, "max_offset": 3.0})

	_test_shape("L", PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 6), Vector2(6, 6), Vector2(6, 10), Vector2(0, 10),
	]), {"valleys": 1, "min_ridges": 1})

	_test_shape("T", PackedVector2Array([
		Vector2(0, 0), Vector2(12, 0), Vector2(12, 4), Vector2(8, 4),
		Vector2(8, 10), Vector2(4, 10), Vector2(4, 4), Vector2(0, 4),
	]), {"valleys": 2, "min_ridges": 1})

	_test_shape("U_unequal", PackedVector2Array([
		Vector2(0, 0), Vector2(12, 0), Vector2(12, 10), Vector2(8, 10),
		Vector2(8, 3), Vector2(4, 3), Vector2(4, 10), Vector2(0, 10),
	]), {"valleys": 2, "min_ridges": 2, "max_offset": 2.0})

	var rotated := PackedVector2Array()
	for p in [Vector2(0, 0), Vector2(10, 0), Vector2(10, 6), Vector2(0, 6)]:
		rotated.append(p.rotated(deg_to_rad(30.0)))
	_test_shape("rotated_rectangle", rotated, {"valleys": 0, "ridges": 1, "max_offset": 3.0})

	var hexagon := PackedVector2Array()
	for i in range(6):
		hexagon.append(Vector2(5, 0).rotated(TAU * i / 6.0) + Vector2(10, 10))
	_test_shape("hexagon", hexagon, {"valleys": 0})

	_test_shape("concave_dart", PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 8), Vector2(5, 3), Vector2(0, 8),
	]), {"min_valleys": 1})

	_test_flat_roof()
	_test_winding_and_duplicates()
	_test_wall_clearance()
	_test_clipped_interior()
	_test_clipped_flush()
	_test_gable_rectangle()
	_test_gable_single_end()
	_test_gable_long_walls()
	_test_gable_rejections()
	_test_gable_end_to_end()
	_test_gutters()
	_test_end_to_end_mesh()

	if failures == 0:
		print("ALL ROOF TESTS PASSED")
		quit(0)
	else:
		print("%d ROOF TEST FAILURE(S)" % failures)
		quit(1)


func _test_shape(name: String, polygon: PackedVector2Array, expect: Dictionary) -> void:
	var skeleton: StraightSkeleton.Result = StraightSkeleton.compute(polygon)
	_check(name, "skeleton completed", skeleton.completed)
	_check(name, "faces produced", skeleton.faces.size() >= polygon.size())

	var expected_area: float = absf(_signed_area(polygon))
	var total_area: float = 0.0
	var max_offset: float = 0.0
	var worst_offset_error: float = 0.0
	for face in skeleton.faces:
		total_area += absf(_signed_area(face.points))
		var idx: int = face.edge_index
		var a: Vector2 = polygon[idx]
		var b: Vector2 = polygon[(idx + 1) % polygon.size()]
		var dir: Vector2 = (b - a).normalized()
		var normal := Vector2(dir.y, -dir.x)
		var line_const: float = a.dot(normal)
		for i in range(face.points.size()):
			var true_dist: float = line_const - face.points[i].dot(normal)
			worst_offset_error = maxf(worst_offset_error, absf(true_dist - face.offsets[i]))
			max_offset = maxf(max_offset, face.offsets[i])
			_check(name, "offset non-negative", face.offsets[i] > -EPS)
	_check(name, "area conserved (%.4f vs %.4f)" % [total_area, expected_area], absf(total_area - expected_area) < maxf(0.01, expected_area * 0.001))
	_check(name, "offsets match edge distance (worst %.6f)" % worst_offset_error, worst_offset_error < EPS)
	if expect.has("max_offset"):
		_check(name, "max offset %.4f == %.4f" % [max_offset, expect["max_offset"]], absf(max_offset - expect["max_offset"]) < EPS)

	var input := RoofInput.new()
	input.polygon = polygon
	input.base_y = 3.0
	input.pitch_degrees = 30.0
	input.overhang = 0.4
	input.fascia_height = 0.18
	var model: RoofModel = RoofGenerator.generate(input)

	var eave_y: float = input.base_y - input.overhang * tan(deg_to_rad(input.pitch_degrees))

	_check(name, "no fallback", not model.used_fallback)
	var shingles: int = 0
	var lowest_shingle: float = INF
	for plane in model.planes:
		_check(name, "uv count matches point count", plane.uvs.size() == plane.points.size())
		if plane.slot == input.slot_shingles:
			shingles += 1
			var d0: float = plane.points[0].dot(plane.normal)
			for p in plane.points:
				_check(name, "shingle plane is planar", absf(p.dot(plane.normal) - d0) < EPS)
				_check(name, "roof at or above the eave line", p.y > eave_y - EPS)
				lowest_shingle = minf(lowest_shingle, p.y)
		elif plane.slot == input.slot_underlayment:
			for p in plane.points:
				_check(name, "soffit sits at the overhang bottom", absf(p.y - (eave_y - input.fascia_height)) < EPS)
	_check(name, "shingle planes exist", shingles > 0)
	_check(name, "eave line hangs below the wall top", absf(lowest_shingle - eave_y) < EPS)
	for edge in model.edges:
		if edge.type == RoofModel.EdgeType.EAVE:
			_check(name, "eave edge at dropped height", absf(edge.a.y - eave_y) < EPS and absf(edge.b.y - eave_y) < EPS)
	_check(name, "fascia plane per eave edge", _count_planes(model, input.slot_fascia) == polygon.size())
	_check(name, "soffit plane per eave edge", _count_planes(model, input.slot_underlayment) == polygon.size())
	_check(name, "eave edge per outline edge", _count_edges(model, RoofModel.EdgeType.EAVE) == polygon.size())

	var ridges: int = 0
	var valleys: int = 0
	for edge in model.edges:
		if edge.type == RoofModel.EdgeType.RIDGE:
			ridges += 1
			_check(name, "ridge is level", absf(edge.a.y - edge.b.y) < EPS)
		elif edge.type == RoofModel.EdgeType.VALLEY:
			valleys += 1
	if expect.has("ridges"):
		_check(name, "ridge count %d == %d" % [ridges, expect["ridges"]], ridges == expect["ridges"])
	if expect.has("min_ridges"):
		_check(name, "ridge count %d >= %d" % [ridges, expect["min_ridges"]], ridges >= expect["min_ridges"])
	if expect.has("valleys"):
		_check(name, "valley count %d == %d" % [valleys, expect["valleys"]], valleys == expect["valleys"])
	if expect.has("min_valleys"):
		_check(name, "valley count %d >= %d" % [valleys, expect["min_valleys"]], valleys >= expect["min_valleys"])


func _test_flat_roof() -> void:
	var input := RoofInput.new()
	input.polygon = PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 4), Vector2(0, 4)])
	input.base_y = 3.0
	input.pitch_degrees = 0.0
	input.overhang = 0.3
	var model: RoofModel = RoofGenerator.generate(input)
	_check("flat", "no fallback", not model.used_fallback)
	_check("flat", "planes exist", model.planes.size() > 0)
	for plane in model.planes:
		if plane.slot == input.slot_shingles:
			for p in plane.points:
				_check("flat", "cap sits at base_y", absf(p.y - input.base_y) < EPS)


func _test_winding_and_duplicates() -> void:
	var input := RoofInput.new()
	input.polygon = PackedVector2Array([
		Vector2(0, 6), Vector2(10, 6), Vector2(10, 0), Vector2(10, 0), Vector2(0, 0),
	])
	input.base_y = 0.0
	input.pitch_degrees = 35.0
	input.overhang = 0.4
	var model: RoofModel = RoofGenerator.generate(input)
	_check("dirty_input", "no fallback", not model.used_fallback)
	_check("dirty_input", "shingle planes exist", _count_planes(model, input.slot_shingles) > 0)
	_check("dirty_input", "one ridge", _count_edges(model, RoofModel.EdgeType.RIDGE) == 1)


func _test_wall_clearance() -> void:
	var input := RoofInput.new()
	input.polygon = _rect(0, 0, 10, 6)
	input.base_y = 3.0
	input.pitch_degrees = 30.0
	input.overhang = 0.4
	input.wall_clearance = 0.1
	var model: RoofModel = RoofGenerator.generate(input)

	var tan_pitch: float = tan(deg_to_rad(30.0))
	var eave_y: float = input.base_y - (input.overhang - input.wall_clearance) * tan_pitch
	var lowest: float = INF
	for plane in model.planes:
		if plane.slot != input.slot_shingles:
			continue
		for p in plane.points:
			lowest = minf(lowest, p.y)
			var outside: float = maxf(0.0, maxf(maxf(-p.x, p.x - 10.0), maxf(-p.z, p.z - 6.0)))
			if outside <= input.wall_clearance + EPS:
				_check("wall_clearance", "roof clears the trim band (y %.3f at %.2f out)" % [p.y, outside], p.y >= input.base_y - EPS)
	_check("wall_clearance", "eave drop reduced by the clearance", absf(lowest - eave_y) < EPS)


func _test_clipped_interior() -> void:
	var input := RoofInput.new()
	input.polygon = _rect(0, 0, 16, 10)
	input.base_y = 3.0
	input.pitch_degrees = 30.0
	input.overhang = 0.4
	input.fascia_height = 0.18
	input.clip_regions = [_rect(6, 3, 10, 7)]
	input.clip_keep_margin = 0.2
	var model: RoofModel = RoofGenerator.generate(input)

	_check("clip_interior", "no fallback", not model.used_fallback)
	_check("clip_interior", "shingle planes exist", _count_planes(model, input.slot_shingles) > 0)

	var clip_inner: PackedVector2Array = _rect(6.05, 3.05, 9.95, 6.95)
	var touches_upper_wall := false
	for plane in model.planes:
		for p in plane.points:
			var plan := Vector2(p.x, p.z)
			_check("clip_interior", "no roof under the upper storey", not Geometry2D.is_point_in_polygon(plan, clip_inner))
			if plane.slot == input.slot_shingles and (
				(absf(plan.x - 6.0) < 0.05 or absf(plan.x - 10.0) < 0.05) and plan.y > 2.9 and plan.y < 7.1
				or (absf(plan.y - 3.0) < 0.05 or absf(plan.y - 7.0) < 0.05) and plan.x > 5.9 and plan.x < 10.1
			):
				touches_upper_wall = true
	_check("clip_interior", "roof butts into the upper walls", touches_upper_wall)
	_check("clip_interior", "ridge cut into two pieces", _count_edges(model, RoofModel.EdgeType.RIDGE) == 2)
	_check("clip_interior", "no valleys introduced", _count_edges(model, RoofModel.EdgeType.VALLEY) == 0)


func _test_clipped_flush() -> void:
	var input := RoofInput.new()
	input.polygon = _rect(0, 0, 8, 12)
	input.base_y = 3.0
	input.pitch_degrees = 30.0
	input.overhang = 0.4
	input.fascia_height = 0.18
	input.clip_regions = [_rect(-0.02, 6, 8.02, 12.02)]
	input.clip_keep_margin = 0.2
	var model: RoofModel = RoofGenerator.generate(input)

	_check("clip_flush", "no fallback", not model.used_fallback)
	_check("clip_flush", "shingle planes exist", _count_planes(model, input.slot_shingles) > 0)

	var keep_limit: float = 6.0 + input.overhang + input.clip_keep_margin + 0.05
	for plane in model.planes:
		for p in plane.points:
			_check("clip_flush", "no geometry beyond the keep region (z %.2f)" % p.z, p.z <= keep_limit)


func _test_gable_rectangle() -> void:
	var input := RoofInput.new()
	input.polygon = _rect(0, 0, 10, 6)
	input.base_y = 3.0
	input.pitch_degrees = 30.0
	input.overhang = 0.4
	input.fascia_height = 0.18
	input.gable_walls = [
		PackedVector2Array([Vector2(0, 1), Vector2(0, 4)]),
		PackedVector2Array([Vector2(10, 1), Vector2(10, 4)]),
	]
	var model: RoofModel = RoofGenerator.generate(input)

	var tan_pitch: float = tan(deg_to_rad(30.0))
	var eave_y: float = input.base_y - input.overhang * tan_pitch
	var apex_y: float = input.base_y + (3.4 - input.overhang) * tan_pitch

	_check("gable_rect", "no fallback", not model.used_fallback)
	_check("gable_rect", "two shingle planes", _count_planes(model, input.slot_shingles) == 2)
	_check("gable_rect", "two gable triangles", _count_planes(model, input.slot_gable) == 2)

	var min_x: float = INF
	var max_x: float = -INF
	var fascia_top: float = -INF
	var soffit_top: float = -INF
	for plane in model.planes:
		if plane.slot == input.slot_shingles:
			for p in plane.points:
				min_x = minf(min_x, p.x)
				max_x = maxf(max_x, p.x)
		elif plane.slot == input.slot_gable:
			_check("gable_rect", "gable is vertical", absf(plane.normal.y) < EPS)
			_check("gable_rect", "gable is a triangle", plane.points.size() == 3)
			var top: float = -INF
			var bottom: float = INF
			for p in plane.points:
				_check("gable_rect", "gable sits on the wall plane (x %.2f)" % p.x, absf(p.x) < EPS or absf(p.x - 10.0) < EPS)
				top = maxf(top, p.y)
				bottom = minf(bottom, p.y)
			_check("gable_rect", "gable base flush with the wall top", absf(bottom - input.base_y) < EPS)
			_check("gable_rect", "gable peak at the ridge height", absf(top - apex_y) < EPS)
		elif plane.slot == input.slot_fascia:
			for p in plane.points:
				fascia_top = maxf(fascia_top, p.y)
		elif plane.slot == input.slot_underlayment:
			for p in plane.points:
				soffit_top = maxf(soffit_top, p.y)
	_check("gable_rect", "roof planes overhang the gable walls", absf(min_x + 0.4) < EPS and absf(max_x - 10.4) < EPS)

	_check("gable_rect", "no hips or valleys left", _count_edges(model, RoofModel.EdgeType.HIP) == 0 and _count_edges(model, RoofModel.EdgeType.VALLEY) == 0)
	_check("gable_rect", "four rake edges", _count_edges(model, RoofModel.EdgeType.RAKE) == 4)
	for edge in model.edges:
		if edge.type == RoofModel.EdgeType.RAKE:
			var lo: float = minf(edge.a.y, edge.b.y)
			var hi: float = maxf(edge.a.y, edge.b.y)
			_check("gable_rect", "rake runs from eave to ridge", absf(lo - eave_y) < EPS and absf(hi - apex_y) < EPS)
		elif edge.type == RoofModel.EdgeType.RIDGE:
			_check("gable_rect", "ridge is level at the peak", absf(edge.a.y - apex_y) < EPS and absf(edge.b.y - apex_y) < EPS)
			_check("gable_rect", "ridge spans gable plane to gable plane", absf(minf(edge.a.x, edge.b.x) + 0.4) < EPS and absf(maxf(edge.a.x, edge.b.x) - 10.4) < EPS)
	_check("gable_rect", "one continuous ridge", _count_edges(model, RoofModel.EdgeType.RIDGE) == 1)

	_check("gable_rect", "2 fascia + 4 rake boards", _count_planes(model, input.slot_fascia) == 6)
	_check("gable_rect", "2 soffits + 4 rake soffits", _count_planes(model, input.slot_underlayment) == 6)
	_check("gable_rect", "eave edges only on the long sides", _count_edges(model, RoofModel.EdgeType.EAVE) == 2)
	_check("gable_rect", "rake boards climb to the ridge (top %.2f)" % fascia_top, absf(fascia_top - apex_y) < EPS)
	_check("gable_rect", "rake soffits climb under the boards (top %.2f)" % soffit_top, absf(soffit_top - (apex_y - input.fascia_height)) < EPS)


func _test_gable_single_end() -> void:
	var input := RoofInput.new()
	input.polygon = _rect(0, 0, 10, 6)
	input.base_y = 3.0
	input.pitch_degrees = 30.0
	input.overhang = 0.4
	input.gable_walls = [PackedVector2Array([Vector2(0, 2), Vector2(0, 3)])]
	var model: RoofModel = RoofGenerator.generate(input)

	_check("gable_one_end", "no fallback", not model.used_fallback)
	_check("gable_one_end", "three shingle planes", _count_planes(model, input.slot_shingles) == 3)
	_check("gable_one_end", "one gable triangle", _count_planes(model, input.slot_gable) == 1)
	_check("gable_one_end", "two rake edges", _count_edges(model, RoofModel.EdgeType.RAKE) == 2)
	_check("gable_one_end", "hips only at the far end", _count_edges(model, RoofModel.EdgeType.HIP) == 2)
	_check("gable_one_end", "one ridge reaching the gable", _count_edges(model, RoofModel.EdgeType.RIDGE) == 1)


func _test_gable_long_walls() -> void:
	var input := RoofInput.new()
	input.polygon = _rect(0, 0, 10, 6)
	input.base_y = 3.0
	input.pitch_degrees = 30.0
	input.overhang = 0.4
	input.gable_walls = [
		PackedVector2Array([Vector2(2, 0), Vector2(6, 0)]),
		PackedVector2Array([Vector2(2, 6), Vector2(6, 6)]),
	]
	var model: RoofModel = RoofGenerator.generate(input)

	var tan_pitch: float = tan(deg_to_rad(30.0))
	var apex_y: float = input.base_y + (5.4 - input.overhang) * tan_pitch

	_check("gable_long", "no fallback", not model.used_fallback)
	_check("gable_long", "two shingle planes", _count_planes(model, input.slot_shingles) == 2)
	_check("gable_long", "two gable triangles", _count_planes(model, input.slot_gable) == 2)
	_check("gable_long", "four rake edges", _count_edges(model, RoofModel.EdgeType.RAKE) == 4)
	_check("gable_long", "no hips or valleys", _count_edges(model, RoofModel.EdgeType.HIP) == 0 and _count_edges(model, RoofModel.EdgeType.VALLEY) == 0)
	_check("gable_long", "one ridge", _count_edges(model, RoofModel.EdgeType.RIDGE) == 1)
	for edge in model.edges:
		if edge.type == RoofModel.EdgeType.RIDGE:
			_check("gable_long", "ridge perpendicular to the gabled walls", absf(edge.a.x - 5.0) < EPS and absf(edge.b.x - 5.0) < EPS)
			_check("gable_long", "ridge level at the raised peak", absf(edge.a.y - apex_y) < EPS and absf(edge.b.y - apex_y) < EPS)
	for plane in model.planes:
		if plane.slot == input.slot_gable:
			_check("gable_long", "gable is vertical", absf(plane.normal.y) < EPS)
			var top: float = -INF
			for p in plane.points:
				_check("gable_long", "gable sits on the wall plane (z %.2f)" % p.z, absf(p.z) < EPS or absf(p.z - 6.0) < EPS)
				top = maxf(top, p.y)
			_check("gable_long", "gable peak at the raised ridge height", absf(top - apex_y) < EPS)

	var single := RoofInput.new()
	single.polygon = _rect(0, 0, 10, 6)
	single.base_y = 3.0
	single.pitch_degrees = 30.0
	single.overhang = 0.4
	single.gable_walls = [PackedVector2Array([Vector2(2, 0), Vector2(6, 0)])]
	model = RoofGenerator.generate(single)
	_check("gable_long_single", "no fallback", not model.used_fallback)
	_check("gable_long_single", "three shingle planes", _count_planes(model, single.slot_shingles) == 3)
	_check("gable_long_single", "one gable triangle", _count_planes(model, single.slot_gable) == 1)
	_check("gable_long_single", "two rake edges", _count_edges(model, RoofModel.EdgeType.RAKE) == 2)
	_check("gable_long_single", "two hips at the far side", _count_edges(model, RoofModel.EdgeType.HIP) == 2)
	_check("gable_long_single", "one ridge", _count_edges(model, RoofModel.EdgeType.RIDGE) == 1)


func _test_gable_rejections() -> void:
	print("  (the ERROR lines below are expected - they are what's under test)")

	var stray := RoofInput.new()
	stray.polygon = _rect(0, 0, 10, 6)
	stray.base_y = 3.0
	stray.pitch_degrees = 30.0
	stray.overhang = 0.4
	stray.gable_walls = [PackedVector2Array([Vector2(3, 3), Vector2(4, 3)])]
	var model: RoofModel = RoofGenerator.generate(stray)
	_check("gable_invalid", "no gable built from a stray segment", _count_planes(model, stray.slot_gable) == 0)
	_check("gable_invalid", "roof stays a full hip", _count_planes(model, stray.slot_shingles) == 4)
	_check("gable_invalid", "no rake edges", _count_edges(model, RoofModel.EdgeType.RAKE) == 0)

	var adjacent := RoofInput.new()
	adjacent.polygon = _rect(0, 0, 10, 6)
	adjacent.base_y = 3.0
	adjacent.pitch_degrees = 30.0
	adjacent.overhang = 0.4
	adjacent.gable_walls = [
		PackedVector2Array([Vector2(2, 0), Vector2(6, 0)]),
		PackedVector2Array([Vector2(0, 2), Vector2(0, 4)]),
	]
	model = RoofGenerator.generate(adjacent)
	_check("gable_adjacent", "no fallback", not model.used_fallback)
	_check("gable_adjacent", "exactly one wall gabled", _count_planes(model, adjacent.slot_gable) == 1)


func _test_gable_end_to_end() -> void:
	var house := HouseData.new()
	house.level_cell_size = 2.0
	var floor_data := FloorData.new()
	floor_data.level = 0
	floor_data.height = 3.0
	for x in range(3):
		floor_data.add_cell(Vector2i(x, 0))
	house.add_floor(floor_data)

	var west := GableData.new()
	west.cell = Vector2i(0, 0)
	west.direction = WallDetail.EdgeDir.WEST
	floor_data.gables.append(west)
	var east := GableData.new()
	east.cell = Vector2i(2, 0)
	east.direction = WallDetail.EdgeDir.EAST
	floor_data.gables.append(east)

	var built: Dictionary = HouseMeshBuilder.build_with_roof_models(house)
	_check_mesh_windings("gable_end_to_end", built["mesh"])
	var gable_planes: int = 0
	for entry in built["roof_models"]:
		gable_planes += _count_planes(entry["model"], RoofSurface.SLOT_GABLE)
	_check("gable_end_to_end", "both end walls gabled", gable_planes == 2)

	print("  (the ERROR line below is expected - it is what's under test)")
	floor_data.gables.clear()
	var bad := GableData.new()
	bad.cell = Vector2i(0, 0)
	bad.direction = WallDetail.EdgeDir.EAST
	floor_data.gables.append(bad)
	built = HouseMeshBuilder.build_with_roof_models(house)
	gable_planes = 0
	for entry in built["roof_models"]:
		gable_planes += _count_planes(entry["model"], RoofSurface.SLOT_GABLE)
	_check("gable_end_to_end", "invalid gable marker refused", gable_planes == 0)


func _test_gutters() -> void:
	var plain := RoofInput.new()
	plain.polygon = _rect(0, 0, 8, 6)
	plain.base_y = 3.0
	plain.pitch_degrees = 30.0
	plain.overhang = 0.4
	plain.fascia_height = 0.18
	var off: RoofModel = RoofGenerator.generate(plain)
	_check("gutter_off", "no trough by default", _count_planes(off, plain.slot_gutter) == 0)
	_check("gutter_off", "no downspouts by default", off.downspouts.is_empty())

	var input := RoofInput.new()
	input.polygon = _rect(0, 0, 8, 6)
	input.base_y = 3.0
	input.pitch_degrees = 30.0
	input.overhang = 0.4
	input.fascia_height = 0.18
	input.gutter_style = RoofGutters.Style.K_STYLE
	input.downspouts_enabled = true
	var model: RoofModel = RoofGenerator.generate(input)

	var eave_y: float = input.base_y - input.overhang * tan(deg_to_rad(input.pitch_degrees))
	var eave_poly: PackedVector2Array = _rect(-0.4, -0.4, 8.4, 6.4)
	var top: float = eave_y - RoofConstants.GUTTER_TOP_DROP
	var deepest: float = top - input.gutter_height - RoofConstants.GUTTER_THICKNESS * 2.0

	_check("gutter_hip", "trough planes exist", _count_planes(model, input.slot_gutter) > 0)
	for plane in model.planes:
		if plane.slot != input.slot_gutter:
			continue
		for p in plane.points:
			_check("gutter_hip", "trough hangs below the eave line (y %.3f)" % p.y, p.y < eave_y - EPS and p.y >= deepest - EPS)
			_check("gutter_hip", "trough is outside the eave outline", not Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), eave_poly))

	_check("gutter_hip", "one downspout per corner (%d)" % model.downspouts.size(), model.downspouts.size() == 4)
	for spout in model.downspouts:
		_check("gutter_hip", "outlet hangs outboard of the pipe", (spout.head - spout.wall).dot(spout.outward) > 0.0)
		_check("gutter_hip", "pipe hugs the wall face", _distance_to_outline(spout.wall, input.polygon) < input.downspout_depth)
		_check("gutter_hip", "outlet clears the overhang", _distance_to_outline(spout.head, input.polygon) > input.overhang)
		_check("gutter_hip", "trough bottom above the soffit", spout.top_y > spout.soffit_y)

	input.gutter_style = RoofGutters.Style.HALF_ROUND
	var round_model: RoofModel = RoofGenerator.generate(input)
	var lowest: float = INF
	for plane in round_model.planes:
		if plane.slot == input.slot_gutter:
			for p in plane.points:
				lowest = minf(lowest, p.y)
	_check("gutter_round", "trough planes exist", _count_planes(round_model, input.slot_gutter) > 0)
	_check("gutter_round", "trough reaches its full depth", absf(lowest - (top - input.gutter_height)) < RoofConstants.GUTTER_THICKNESS * 2.0)

	var gabled := RoofInput.new()
	gabled.polygon = _rect(0, 0, 10, 6)
	gabled.base_y = 3.0
	gabled.pitch_degrees = 30.0
	gabled.overhang = 0.4
	gabled.fascia_height = 0.18
	gabled.gutter_style = RoofGutters.Style.K_STYLE
	gabled.downspouts_enabled = true
	gabled.gable_walls = [
		PackedVector2Array([Vector2(0, 2), Vector2(0, 4)]),
		PackedVector2Array([Vector2(10, 2), Vector2(10, 4)]),
	]
	var gable_model: RoofModel = RoofGenerator.generate(gabled)
	_check("gutter_gable", "no fallback", not gable_model.used_fallback)
	_check("gutter_gable", "trough planes exist", _count_planes(gable_model, gabled.slot_gutter) > 0)
	for plane in gable_model.planes:
		if plane.slot != gabled.slot_gutter:
			continue
		for p in plane.points:
			_check("gutter_gable", "no trough on the gable ends (x %.3f)" % p.x, p.x > -0.4 - EPS and p.x < 10.4 + EPS)
	_check("gutter_gable", "the two eaves are still guttered", gable_model.downspouts.size() >= 4)
	for spout in gable_model.downspouts:
		_check("gutter_gable", "pipe found a wall to run down", _distance_to_outline(spout.wall, gabled.polygon) < gabled.downspout_depth)

	var long_run := RoofInput.new()
	long_run.polygon = _rect(0, 0, 30, 6)
	long_run.base_y = 3.0
	long_run.pitch_degrees = 30.0
	long_run.overhang = 0.4
	long_run.fascia_height = 0.18
	long_run.gutter_style = RoofGutters.Style.K_STYLE
	long_run.downspouts_enabled = true
	long_run.downspout_max_span = 8.0
	var long_model: RoofModel = RoofGenerator.generate(long_run)

	var front: Array[float] = _front_wall_pipes(long_model)
	_check("gutter_span", "the long wall is covered end to end (%d pipes)" % front.size(), front.size() >= 5)
	_check("gutter_span", "first pipe near the corner (%.2f)" % front[0], front[0] < long_run.downspout_max_span)
	_check("gutter_span", "last pipe near the far corner (%.2f)" % front[front.size() - 1],
		front[front.size() - 1] > 30.0 - long_run.downspout_max_span)
	for k in range(front.size() - 1):
		var gap: float = front[k + 1] - front[k]
		_check("gutter_span", "no stretch exceeds the max span (%.2f)" % gap, gap <= long_run.downspout_max_span + EPS)

	long_run.downspout_max_span = 40.0
	var sparse: Array[float] = _front_wall_pipes(RoofGenerator.generate(long_run))
	_check("gutter_span", "a generous max span thins them out (%d vs %d)" % [sparse.size(), front.size()],
		sparse.size() < front.size())


func _front_wall_pipes(model: RoofModel) -> Array[float]:
	var out: Array[float] = []
	for spout in model.downspouts:
		if spout.wall.y < 3.0:
			out.append(spout.wall.x)
	out.sort()
	return out

	var porch := RoofInput.new()
	porch.polygon = _rect(0, 0, 8, 6)
	porch.base_y = 3.0
	porch.pitch_degrees = 30.0
	porch.overhang = 0.4
	porch.fascia_height = 0.18
	porch.gutter_style = RoofGutters.Style.K_STYLE
	porch.downspouts_enabled = true
	porch.downspout_walls = [_rect(3, 2, 5, 4)]
	var porch_model: RoofModel = RoofGenerator.generate(porch)
	_check("gutter_no_wall", "trough still built", _count_planes(porch_model, porch.slot_gutter) > 0)
	_check("gutter_no_wall", "no pipe without a wall to run down", porch_model.downspouts.is_empty())

	_test_gutters_end_to_end()


func _test_gutters_end_to_end() -> void:
	var house := HouseData.new()
	house.level_cell_size = 2.0
	var lower := FloorData.new()
	lower.level = 0
	lower.height = 3.0
	for x in range(3):
		for y in range(3):
			lower.add_cell(Vector2i(x, y))
	house.add_floor(lower)
	var upper := FloorData.new()
	upper.level = 1
	upper.height = 3.0
	upper.add_cell(Vector2i(1, 1))
	house.add_floor(upper)

	var built: Dictionary = HouseMeshBuilder.build_with_roof_models(house)
	var ground_spouts: Array[RoofModel.Downspout] = []
	for entry in built["roof_models"]:
		var model: RoofModel = entry["model"]
		var troughs: int = _count_planes(model, "gutter")
		if entry["floor_level"] == 0:
			_check("gutter_levels", "the lowest roof is guttered", troughs > 0)
			ground_spouts.append_array(model.downspouts)
		else:
			_check("gutter_levels", "the tower's roof is not (%d planes)" % troughs, troughs == 0)
			_check("gutter_levels", "and has no downspouts", model.downspouts.is_empty())
	_check("gutter_levels", "the lowest roof has downspouts", ground_spouts.size() > 0)

	for spout in ground_spouts:
		var along_x: float = absf(spout.wall.x - roundf(spout.wall.x / house.level_cell_size) * house.level_cell_size)
		var along_y: float = absf(spout.wall.y - roundf(spout.wall.y / house.level_cell_size) * house.level_cell_size)
		_check("gutter_grid", "downspout sits on a cell corner (%.3f, %.3f)" % [spout.wall.x, spout.wall.y],
			minf(along_x, along_y) < EPS)

	var floor_gap: float = house.level_cell_size * RoofConstants.DOWNSPOUT_MIN_SPACING_CELLS - EPS
	for a in range(ground_spouts.size()):
		for b in range(a + 1, ground_spouts.size()):
			var gap: float = ground_spouts[a].wall.distance_to(ground_spouts[b].wall)
			_check("gutter_grid", "downspouts stay %.1f cells apart (%.3f m)"
				% [RoofConstants.DOWNSPOUT_MIN_SPACING_CELLS, gap], gap > floor_gap)

	var mesh: ArrayMesh = built["mesh"]
	var deepest: float = INF
	for s in range(mesh.get_surface_count()):
		if mesh.surface_get_name(s) != "gutter":
			continue
		for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			deepest = minf(deepest, v.y)
	_check("gutter_levels", "pipes reach grade (%.3f)" % deepest,
		absf(deepest - (house.grade_y() - RoofConstants.DOWNSPOUT_FOOT_EMBED)) < EPS)


func _distance_to_outline(p: Vector2, polygon: PackedVector2Array) -> float:
	var best: float = INF
	for i in range(polygon.size()):
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, polygon[i], polygon[(i + 1) % polygon.size()])
		best = minf(best, p.distance_to(closest))
	return best


func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


func _test_end_to_end_mesh() -> void:
	var t_house := HouseData.new()
	t_house.level_cell_size = 2.0
	var t_floor := FloorData.new()
	t_floor.level = 0
	t_floor.height = 3.0
	for cell in [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(1, 1), Vector2i(1, 2),
	]:
		t_floor.add_cell(cell)
	t_house.add_floor(t_floor)
	_check_mesh_windings("end_to_end_T", HouseMeshBuilder.build(t_house))

	var two_house := HouseData.new()
	two_house.level_cell_size = 2.0
	var lower := FloorData.new()
	lower.level = 0
	lower.height = 3.0
	for x in range(3):
		for y in range(3):
			lower.add_cell(Vector2i(x, y))
	two_house.add_floor(lower)
	var upper := FloorData.new()
	upper.level = 1
	upper.height = 3.0
	upper.add_cell(Vector2i(1, 1))
	two_house.add_floor(upper)
	var mesh: ArrayMesh = HouseMeshBuilder.build(two_house)
	_check_mesh_windings("end_to_end_two_storey", mesh)

	var upper_inner: PackedVector2Array = _rect(2.2, 2.2, 3.8, 3.8)
	var lower_roof_verts: int = 0
	for s in range(mesh.get_surface_count()):
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			if v.y > 3.05 and v.y < 5.95:
				lower_roof_verts += 1
				_check("end_to_end_two_storey", "lower roof clear of upper interior", not Geometry2D.is_point_in_polygon(Vector2(v.x, v.z), upper_inner))
	_check("end_to_end_two_storey", "lower-level roof exists", lower_roof_verts > 0)

	var flush_house := HouseData.new()
	flush_house.level_cell_size = 2.0
	var flush_lower := FloorData.new()
	flush_lower.level = 0
	flush_lower.height = 3.0
	for x in range(3):
		for y in range(3):
			flush_lower.add_cell(Vector2i(x, y))
	flush_house.add_floor(flush_lower)
	var flush_upper := FloorData.new()
	flush_upper.level = 1
	flush_upper.height = 3.0
	for x in range(3):
		for y in range(1, 3):
			flush_upper.add_cell(Vector2i(x, y))
	flush_house.add_floor(flush_upper)
	_check_mesh_windings("end_to_end_flush", HouseMeshBuilder.build(flush_house))


func _check_mesh_windings(name: String, mesh: ArrayMesh) -> void:
	_check(name, "mesh has surfaces", mesh.get_surface_count() > 0)
	var expected_sign: float = 0.0
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		_check(name, "surface %d has triangles" % s, indices.size() >= 3)
		for t in range(0, indices.size(), 3):
			var a: Vector3 = verts[indices[t]]
			var b: Vector3 = verts[indices[t + 1]]
			var c: Vector3 = verts[indices[t + 2]]
			var geometric: Vector3 = (b - a).cross(c - a)
			if geometric.length() < 1e-9:
				continue
			var stored: Vector3 = norms[indices[t]] + norms[indices[t + 1]] + norms[indices[t + 2]]
			var sign_here: float = signf(geometric.dot(stored))
			_check(name, "triangle winding is not degenerate", sign_here != 0.0)
			if expected_sign == 0.0:
				expected_sign = sign_here
			else:
				_check(name, "surface %d triangle winding consistent" % s, sign_here == expected_sign)


func _count_planes(model: RoofModel, slot: String) -> int:
	var count: int = 0
	for plane in model.planes:
		if plane.slot == slot:
			count += 1
	return count


func _count_edges(model: RoofModel, type: int) -> int:
	var count: int = 0
	for edge in model.edges:
		if edge.type == type:
			count += 1
	return count


func _check(shape: String, what: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("FAIL [%s] %s" % [shape, what])


func _signed_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = points.size()
	for i in range(n):
		area += points[i].x * points[(i + 1) % n].y - points[(i + 1) % n].x * points[i].y
	return area * 0.5
