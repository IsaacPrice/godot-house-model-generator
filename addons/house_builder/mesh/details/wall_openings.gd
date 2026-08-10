@tool
class_name WallOpenings
extends RefCounted


static func collect(house: HouseData, floor_data: FloorData, floor_base_y: float, is_lowest_floor: bool) -> Array[Dictionary]:
	var openings: Array[Dictionary] = []
	for detail in floor_data.wall_details:
		if detail.type == WallDetail.DetailType.STAIRS:
			continue
		if not DetailRules.wall_detail_valid(detail, floor_data, is_lowest_floor):
			push_warning("House builder: skipping invalid %s at cell %s edge %s." % [
				WallDetail.DetailType.keys()[detail.type], detail.cell, WallDetail.EdgeDir.keys()[detail.direction],
			])
			continue

		var normal: Vector2 = WallDetail.NORMALS[detail.direction]

		var spanned: Array[Vector2i] = detail.spanned_cells()
		var first: PackedVector2Array = WallDetail.endpoints(spanned[0], detail.direction, house.level_cell_size)
		var last: PackedVector2Array = WallDetail.endpoints(spanned[spanned.size() - 1], detail.direction, house.level_cell_size)
		var run_a: Vector2 = first[0]
		var run_b: Vector2 = last[1]
		var dir: Vector2 = (run_b - run_a).normalized()
		if not Vector2(dir.y, -dir.x).is_equal_approx(normal):
			var swap: Vector2 = run_a
			run_a = run_b
			run_b = swap
			dir = -dir

		var run_length: float = run_a.distance_to(run_b)
		var width: float = minf(detail.width, run_length - 2.0 * DetailConstants.OPENING_EDGE_MARGIN)
		var mid: Vector2 = (run_a + run_b) * 0.5

		var max_top: float = DetailRules.max_opening_top(floor_data.height)
		var sill: float = clampf(detail.sill_height, 0.0, maxf(max_top, 0.0))
		var height: float = clampf(detail.height, 0.0, maxf(max_top - sill, 0.0))
		var bottom_y: float = floor_base_y + sill
		var top_y: float = bottom_y + height
		if detail.type == WallDetail.DetailType.GARAGE_DOOR:
			bottom_y = minf(bottom_y, house.grade_y())

		openings.append({
			"detail": detail,
			"a": mid - dir * (width * 0.5),
			"b": mid + dir * (width * 0.5),
			"normal": normal,
			"bottom_y": bottom_y,
			"top_y": top_y,
		})
	return openings
