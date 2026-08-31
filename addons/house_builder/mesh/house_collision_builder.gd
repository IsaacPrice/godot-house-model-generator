@tool
class_name HouseCollisionBuilder
extends RefCounted


const RUN_EPS := 1e-3


static func build(house: HouseData, built: Dictionary) -> Array[Dictionary]:
	var shapes: Array[Dictionary] = []
	if house.floors.is_empty():
		return shapes

	var cell_size: float = house.level_cell_size
	var foundation_base: float = house.foundation_base_y()
	var floor_infos: Array[Dictionary] = built.get("floor_infos", [] as Array[Dictionary])

	for i in range(floor_infos.size()):
		var info: Dictionary = floor_infos[i]
		var floor_data: FloorData = info["floor_data"]
		var wall_base: float = foundation_base if i == 0 else info["base_y"]
		_append_walls(shapes, house, floor_data, info["openings"], wall_base, info["top_y"])

	_append_decks(shapes, house, floor_infos)

	var ground_floor: FloorData = house.floors[0]
	var porch_cells: Array[Vector2i] = []
	for cell in ground_floor.porch_cells:
		if not ground_floor.cells.has(cell):
			porch_cells.append(cell)
	for rect in _cell_rects(porch_cells):
		shapes.append(_rect_box("Porch", rect, cell_size, 0.0, foundation_base, -DetailConstants.PORCH_DROP))

	var sidewalk_cells: Array[Vector2i] = SidewalkBuilder.valid_cells(ground_floor)
	var sidewalk_top: float = house.grade_y()
	for rect in _cell_rects(sidewalk_cells):
		var entry: Dictionary = _sidewalk_box(rect, sidewalk_cells, cell_size, house.sidewalk_expand, sidewalk_top - house.sidewalk_thickness, sidewalk_top)
		if not entry.is_empty():
			shapes.append(entry)

	for stair_run in PorchBuilder.stair_runs(house, ground_floor):
		shapes.append(_stair_ramp(stair_run))

	for railing_run in PorchBuilder.railing_runs(house, ground_floor):
		if railing_run["kind"] == "level":
			shapes.append(_railing_box(railing_run, house))
		else:
			shapes.append(_stair_railing_prism(railing_run, house))

	var roof_faces: PackedVector3Array = _roof_faces(built["roof_models"])
	if not roof_faces.is_empty():
		var roof_shape := ConcavePolygonShape3D.new()
		roof_shape.set_faces(roof_faces)
		roof_shape.backface_collision = true
		shapes.append({"name": "Roof", "shape": roof_shape, "transform": Transform3D.IDENTITY})

	return shapes


static func _append_walls(
	shapes: Array[Dictionary], house: HouseData, floor_data: FloorData,
	openings: Array[Dictionary], base_y: float, top_y: float
) -> void:
	var half: float = house.wall_thickness * 0.5
	var name: String = "Wall%d" % floor_data.level

	for loop in Footprint.trace_loops(floor_data.cells, house.level_cell_size):
		var n: int = loop.size()
		for i in range(n):
			var p0: Vector2 = loop.points[i]
			var p1: Vector2 = loop.points[(i + 1) % n]
			var run: float = p0.distance_to(p1)
			if run < RUN_EPS:
				continue
			var d: Vector2 = (p1 - p0) / run
			var normal: Vector2 = loop.normals[i]

			var cursor: float = -half
			for cut in _wall_cuts(openings, p0, normal, d, run):
				if cut["t0"] - cursor > RUN_EPS:
					_append_wall_box(shapes, name, p0, d, normal, half, cursor, cut["t0"], base_y, top_y)
				if top_y - maxf(cut["top_y"], base_y) > RUN_EPS:
					_append_wall_box(shapes, name, p0, d, normal, half, cut["t0"], cut["t1"], maxf(cut["top_y"], base_y), top_y)
				cursor = maxf(cursor, cut["t1"])
			if run + half - cursor > RUN_EPS:
				_append_wall_box(shapes, name, p0, d, normal, half, cursor, run + half, base_y, top_y)


static func _wall_cuts(
	openings: Array[Dictionary], p0: Vector2, normal: Vector2, d: Vector2, run: float
) -> Array[Dictionary]:
	var cuts: Array[Dictionary] = []
	for op in openings:
		var detail: WallDetail = op["detail"]
		if not detail.is_door() or detail.door_mode == WallDetail.DoorMode.STATIC:
			continue
		if not (op["normal"] as Vector2).is_equal_approx(normal):
			continue
		var mid: Vector2 = (op["a"] + op["b"]) * 0.5
		var t: float = (mid - p0).dot(d)
		if t < -RUN_EPS or t > run + RUN_EPS:
			continue
		if (mid - (p0 + d * t)).length() > RUN_EPS:
			continue
		var ta: float = (op["a"] - p0).dot(d)
		var tb: float = (op["b"] - p0).dot(d)
		cuts.append({"t0": minf(ta, tb), "t1": maxf(ta, tb), "top_y": op["top_y"]})

	cuts.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["t0"] < y["t0"])
	return cuts


static func _append_wall_box(
	shapes: Array[Dictionary], name: String, origin: Vector2, d: Vector2, normal: Vector2,
	half: float, t0: float, t1: float, y0: float, y1: float
) -> void:
	if t1 - t0 < RUN_EPS or y1 - y0 < RUN_EPS:
		return
	var a: Vector2 = origin + d * t0 - normal * half
	var b: Vector2 = origin + d * t1 + normal * half

	var shape := BoxShape3D.new()
	shape.size = Vector3(absf(b.x - a.x), y1 - y0, absf(b.y - a.y))
	var center := Vector3((a.x + b.x) * 0.5, (y0 + y1) * 0.5, (a.y + b.y) * 0.5)
	shapes.append({"name": name, "shape": shape, "transform": Transform3D(Basis.IDENTITY, center)})


static func _append_decks(shapes: Array[Dictionary], house: HouseData, floor_infos: Array[Dictionary]) -> void:
	var cell_size: float = house.level_cell_size
	for level in InteriorBuilder.deck_levels(floor_infos):
		var tops: Dictionary = InteriorBuilder.cell_tops(house, level)
		var by_top: Dictionary = {}
		for cell in level["cells"]:
			var key: float = tops[cell]
			if not by_top.has(key):
				by_top[key] = [] as Array[Vector2i]
			by_top[key].append(cell)

		for top_y in by_top:
			var bottom_y: float = InteriorBuilder.deck_bottom(house, top_y, level["is_lowest"])
			if top_y - bottom_y < RUN_EPS:
				continue
			for rect in _cell_rects(by_top[top_y]):
				shapes.append(_rect_box("Deck", rect, cell_size, 0.0, bottom_y, top_y))


static func _cell_rects(cells: Array[Vector2i]) -> Array[Rect2i]:
	var remaining: Dictionary = {}
	for cell in cells:
		remaining[cell] = true

	var rects: Array[Rect2i] = []
	while not remaining.is_empty():
		var start: Vector2i = remaining.keys()[0]
		for cell in remaining:
			if cell.y < start.y or (cell.y == start.y and cell.x < start.x):
				start = cell

		var width: int = 1
		while remaining.has(Vector2i(start.x + width, start.y)):
			width += 1
		var height: int = 1
		while _row_filled(remaining, start.x, start.y + height, width):
			height += 1

		for dy in range(height):
			for dx in range(width):
				remaining.erase(Vector2i(start.x + dx, start.y + dy))
		rects.append(Rect2i(start, Vector2i(width, height)))

	return rects


static func _row_filled(remaining: Dictionary, x0: int, y: int, width: int) -> bool:
	for dx in range(width):
		if not remaining.has(Vector2i(x0 + dx, y)):
			return false
	return true


static func _rect_box(name: String, rect: Rect2i, cell_size: float, margin: float, bottom_y: float, top_y: float) -> Dictionary:
	var x0: float = rect.position.x * cell_size - margin
	var x1: float = rect.end.x * cell_size + margin
	var z0: float = rect.position.y * cell_size - margin
	var z1: float = rect.end.y * cell_size + margin

	var shape := BoxShape3D.new()
	shape.size = Vector3(x1 - x0, top_y - bottom_y, z1 - z0)
	var center := Vector3((x0 + x1) * 0.5, (bottom_y + top_y) * 0.5, (z0 + z1) * 0.5)
	return {"name": name, "shape": shape, "transform": Transform3D(Basis.IDENTITY, center)}


static func _sidewalk_box(rect: Rect2i, cells: Array[Vector2i], cell_size: float, expand: float, bottom_y: float, top_y: float) -> Dictionary:
	var x0: float = rect.position.x * cell_size
	var x1: float = rect.end.x * cell_size
	var z0: float = rect.position.y * cell_size
	var z1: float = rect.end.y * cell_size

	if _side_exposed(cells, rect, Vector2i(0, -1)):
		z0 -= expand
	if _side_exposed(cells, rect, Vector2i(0, 1)):
		z1 += expand
	if _side_exposed(cells, rect, Vector2i(-1, 0)):
		x0 -= expand
	if _side_exposed(cells, rect, Vector2i(1, 0)):
		x1 += expand

	if x1 - x0 <= 0.0 or z1 - z0 <= 0.0:
		return {}

	var shape := BoxShape3D.new()
	shape.size = Vector3(x1 - x0, top_y - bottom_y, z1 - z0)
	var center := Vector3((x0 + x1) * 0.5, (bottom_y + top_y) * 0.5, (z0 + z1) * 0.5)
	return {"name": "Sidewalk", "shape": shape, "transform": Transform3D(Basis.IDENTITY, center)}


static func _side_exposed(cells: Array[Vector2i], rect: Rect2i, dir: Vector2i) -> bool:
	if dir.y != 0:
		var z: int = rect.position.y - 1 if dir.y < 0 else rect.end.y
		for x in range(rect.position.x, rect.end.x):
			if cells.has(Vector2i(x, z)):
				return false
		return true
	var x_side: int = rect.position.x - 1 if dir.x < 0 else rect.end.x
	for y in range(rect.position.y, rect.end.y):
		if cells.has(Vector2i(x_side, y)):
			return false
	return true


static func _stair_ramp(stair_run: Dictionary) -> Dictionary:
	var p0: Vector2 = stair_run["p0"]
	var p1: Vector2 = stair_run["p1"]
	var normal: Vector2 = stair_run["normal"]
	var deck_top: float = stair_run["deck_top"]
	var base_y: float = stair_run["base_y"]
	var far0: Vector2 = p0 + normal * stair_run["run"]
	var far1: Vector2 = p1 + normal * stair_run["run"]

	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(p0.x, deck_top, p0.y), Vector3(p1.x, deck_top, p1.y),
		Vector3(p0.x, base_y, p0.y), Vector3(p1.x, base_y, p1.y),
		Vector3(far0.x, base_y, far0.y), Vector3(far1.x, base_y, far1.y),
	])
	return {"name": "StairRamp", "shape": shape, "transform": Transform3D.IDENTITY}


static func _railing_box(railing_run: Dictionary, house: HouseData) -> Dictionary:
	var inset: Vector2 = -railing_run["normal"] * house.porch_post_width
	var a: Vector2 = railing_run["p0"]
	var b: Vector2 = railing_run["p1"] + inset
	var bottom_y: float = railing_run["deck_top"]
	var top_y: float = bottom_y + house.porch_railing_height

	var shape := BoxShape3D.new()
	shape.size = Vector3(absf(b.x - a.x), top_y - bottom_y, absf(b.y - a.y))
	var center := Vector3((a.x + b.x) * 0.5, (bottom_y + top_y) * 0.5, (a.y + b.y) * 0.5)
	return {"name": "Railing", "shape": shape, "transform": Transform3D(Basis.IDENTITY, center)}


static func _stair_railing_prism(railing_run: Dictionary, house: HouseData) -> Dictionary:
	var side: Vector2 = railing_run["d"] * (house.porch_post_width * 0.5)
	var near_a: Vector2 = railing_run["anchor"] - side
	var near_b: Vector2 = railing_run["anchor"] + side
	var advance: Vector2 = railing_run["normal"] * railing_run["run"]
	var near_bottom: float = railing_run["deck_top"]
	var far_bottom: float = near_bottom - railing_run["rise"]
	var height: float = house.porch_railing_height

	var points := PackedVector3Array()
	for corner in [near_a, near_b]:
		points.append(Vector3(corner.x, near_bottom, corner.y))
		points.append(Vector3(corner.x, near_bottom + height, corner.y))
		var far: Vector2 = corner + advance
		points.append(Vector3(far.x, far_bottom, far.y))
		points.append(Vector3(far.x, far_bottom + height, far.y))

	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return {"name": "StairRailing", "shape": shape, "transform": Transform3D.IDENTITY}


static func _roof_faces(roof_models: Array[Dictionary]) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for entry in roof_models:
		var model: RoofModel = entry["model"]
		for plane in model.planes:
			if plane.slot == RoofSurface.SLOT_SHINGLES or plane.slot == RoofSurface.SLOT_GABLE:
				_append_plane_faces(faces, plane)
	return faces


static func _append_plane_faces(faces: PackedVector3Array, plane: RoofModel.RoofPlane) -> void:
	var points: PackedVector3Array = plane.points
	if points.size() < 3:
		return

	if not plane.convex and points.size() > 3:
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
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(plan)
		if not indices.is_empty():
			for index in indices:
				faces.append(points[index])
			return

	for i in range(1, points.size() - 1):
		faces.append(points[0])
		faces.append(points[i])
		faces.append(points[i + 1])
