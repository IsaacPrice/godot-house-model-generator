@tool
class_name RoofBuilder
extends RefCounted


static func build(house: HouseData, floor_infos: Array[Dictionary], accumulator: SurfaceAccumulator) -> Array[Dictionary]:
	var half_thickness: float = house.wall_thickness * 0.5
	var models: Array[Dictionary] = []
	var gutter_level: int = 0
	var roofed: bool = false

	for i in range(floor_infos.size()):
		var info: Dictionary = floor_infos[i]
		var floor_data: FloorData = info["floor_data"]
		var roof_cells: Array[Vector2i] = info.get("roof_cells", floor_data.cells)
		var top_y: float = info["top_y"]
		var next_floor: FloorData = null
		if i + 1 < floor_infos.size():
			next_floor = floor_infos[i + 1]["floor_data"]

		if next_floor != null and _fully_covered(roof_cells, next_floor):
			if not floor_data.gables.is_empty():
				push_warning("RoofBuilder: gable walls on floor level %d ignored - its roof is fully covered by the floor above." % floor_data.level)
			continue

		var clip_regions: Array[PackedVector2Array] = []
		if next_floor != null:
			for upper_loop in Footprint.trace_loops(next_floor.cells, house.level_cell_size):
				var region := PackedVector2Array()
				for k in range(upper_loop.size()):
					region.append(upper_loop.corner_offset(k, half_thickness - RoofConstants.WALL_CLIP_EMBED))
				clip_regions.append(region)

		var gable_segments: Array[PackedVector2Array] = _gable_segments(house, floor_data, roof_cells)
		var gutters_here: bool = not roofed or floor_data.level == gutter_level

		var downspout_walls: Array[PackedVector2Array] = []
		for house_loop in Footprint.trace_loops(floor_data.cells, house.level_cell_size):
			var wall_region := PackedVector2Array()
			for k in range(house_loop.size()):
				wall_region.append(house_loop.corner_offset(k, half_thickness))
			downspout_walls.append(wall_region)

		var loops: Array[BoundaryLoop] = Footprint.trace_loops(roof_cells, house.level_cell_size)
		for loop in loops:
			var wall_face := PackedVector2Array()
			for k in range(loop.size()):
				wall_face.append(loop.corner_offset(k, half_thickness))

			var input: RoofInput = RoofInput.from_house(house, wall_face, top_y)
			for k in range(gable_segments.size() - 1, -1, -1):
				var seg: PackedVector2Array = gable_segments[k]
				if RoofGenerator.match_wall_edge(wall_face, seg[0], seg[1]) != -1:
					input.gable_walls.append(seg)
					gable_segments.remove_at(k)
			input.clip_regions = clip_regions
			input.clip_keep_margin = house.wall_thickness
			input.wall_clearance = house.corner_trim_width + RoofConstants.WALL_CLEARANCE_MARGIN
			input.soffit_overlap = half_thickness
			input.downspout_walls = downspout_walls
			if not gutters_here:
				input.gutter_style = RoofGutters.Style.NONE
			var model: RoofModel = RoofGenerator.generate(input)
			if model.used_fallback:
				push_warning("RoofBuilder: flat-cap fallback used for a roof section on floor level %d." % floor_data.level)
			_emit(model, accumulator)
			_emit_downspouts(model, input, house.grade_y(), accumulator)
			models.append({"floor_level": floor_data.level, "model": model})
			if not roofed:
				roofed = true
				gutter_level = floor_data.level

		for seg in gable_segments:
			push_error("RoofBuilder: gable wall %s - %s matched no roof outline on floor level %d." % [seg[0], seg[1], floor_data.level])

	return models


static func _fully_covered(roof_cells: Array[Vector2i], next_floor: FloorData) -> bool:
	for cell in roof_cells:
		if not next_floor.has_cell(cell):
			return false
	return true


static func _gable_segments(house: HouseData, floor_data: FloorData, roof_cells: Array[Vector2i]) -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = []
	for gable in floor_data.gables:
		if not DetailRules.gable_edge_valid(gable, roof_cells):
			push_error("RoofBuilder: invalid gable wall on floor level %d - the %s edge of cell %s is not an exterior wall of the roof footprint." % [
				floor_data.level, WallDetail.EdgeDir.keys()[gable.direction], gable.cell,
			])
			continue
		var center: PackedVector2Array = WallDetail.endpoints(gable.cell, gable.direction, house.level_cell_size)
		var outward: Vector2 = WallDetail.NORMALS[gable.direction] * house.wall_thickness * 0.5
		segments.append(PackedVector2Array([center[0] + outward, center[1] + outward]))
	return segments


static func _emit_downspouts(
	model: RoofModel, input: RoofInput, grade_y: float, accumulator: SurfaceAccumulator
) -> void:
	if model.downspouts.is_empty():
		return

	var slot: String = input.slot_gutter
	var material: Material = input.gutter_material
	var width: float = input.downspout_width
	var depth: float = input.downspout_depth
	var bottom: float = grade_y - RoofConstants.DOWNSPOUT_FOOT_EMBED

	for spout in model.downspouts:
		var across: Vector2 = Vector2(spout.outward.y, -spout.outward.x) * (width * 0.5)
		var elbow_top: float = spout.soffit_y - RoofConstants.DOWNSPOUT_ELBOW_GAP
		var elbow_bottom: float = elbow_top - depth

		_emit_prism(accumulator, slot, material,
			spout.head - across, spout.head + across, depth, elbow_bottom, spout.top_y)
		_emit_prism(accumulator, slot, material, spout.head, spout.wall, width, elbow_bottom, elbow_top)
		_emit_prism(accumulator, slot, material,
			spout.wall - across, spout.wall + across, depth, bottom, elbow_top)


static func _emit_prism(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	a: Vector2, b: Vector2, width: float, y0: float, y1: float
) -> void:
	var axis: Vector2 = b - a
	var length: float = axis.length()
	var height: float = y1 - y0
	if length < RoofConstants.MIN_EDGE_LENGTH or height < RoofConstants.MIN_EDGE_LENGTH or width <= 0.0:
		return
	axis /= length
	var side: Vector2 = Vector2(axis.y, -axis.x) * (width * 0.5)

	var corners := PackedVector2Array([a - side, a + side, b + side, b - side])
	for k in range(4):
		var p: Vector2 = corners[k]
		var q: Vector2 = corners[(k + 1) % 4]
		var run: float = p.distance_to(q)
		if run < RoofConstants.MIN_EDGE_LENGTH:
			continue
		var d: Vector2 = (q - p) / run
		PlanPolygon.oriented_quad(
			accumulator, slot, material,
			Vector3(p.x, y0, p.y), Vector3(p.x, y1, p.y),
			Vector3(q.x, y1, q.y), Vector3(q.x, y0, q.y),
			Vector3(d.y, 0.0, -d.x),
			Vector2(0.0, height), Vector2(0.0, 0.0), Vector2(run, 0.0), Vector2(run, height))

	PlanPolygon.emit_horizontal(accumulator, slot, material, corners, y1, true)
	PlanPolygon.emit_horizontal(accumulator, slot, material, corners, y0, false)


static func _emit(model: RoofModel, accumulator: SurfaceAccumulator) -> void:
	for plane in model.planes:
		PlanPolygon.emit(accumulator, plane.slot, plane.material, plane.points, plane.uvs, plane.normal, plane.convex)
