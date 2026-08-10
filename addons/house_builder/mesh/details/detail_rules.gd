@tool
class_name DetailRules
extends RefCounted


static func is_boundary_edge(cells: Array[Vector2i], cell: Vector2i, direction: int) -> bool:
	if not cells.has(cell):
		return false
	return not cells.has(cell + Vector2i(WallDetail.NORMALS[direction]))


static func max_opening_width(cell_size: float, span: int) -> float:
	return cell_size * span - 2.0 * DetailConstants.OPENING_EDGE_MARGIN


static func max_opening_top(floor_height: float) -> float:
	return floor_height - DetailConstants.HEADER_MIN


static func wall_detail_valid(detail: WallDetail, floor_data: FloorData, is_lowest_floor: bool) -> bool:
	var boundary_cells: Array[Vector2i] = floor_data.cells
	if detail.type == WallDetail.DetailType.STAIRS:
		boundary_cells = floor_data.porch_cells

	for spanned in detail.spanned_cells():
		if not is_boundary_edge(boundary_cells, spanned, detail.direction):
			return false
		for other in floor_data.wall_details:
			if other != detail and other.covers(spanned, detail.direction):
				return false

	if detail.type == WallDetail.DetailType.STAIRS:
		return true

	var reaches_ground: bool = detail.type == WallDetail.DetailType.DOOR or detail.type == WallDetail.DetailType.GARAGE_DOOR
	return not (reaches_ground and not is_lowest_floor)


static func dormer_edge_valid(dormer: DormerData, floor_data: FloorData) -> bool:
	for spanned in dormer.spanned_cells():
		if not is_boundary_edge(floor_data.cells, spanned, dormer.direction):
			return false
	return true


static func gable_edge_valid(gable: GableData, roof_boundary_cells: Array[Vector2i]) -> bool:
	return is_boundary_edge(roof_boundary_cells, gable.cell, gable.direction)


static func chimney_cell_valid(chimney: ChimneyData, floor_data: FloorData) -> bool:
	return floor_data.cells.has(chimney.cell)


static func can_paint_porch_cell(floor_data: FloorData, cell: Vector2i) -> bool:
	return not floor_data.cells.has(cell) and not floor_data.sidewalk_cells.has(cell)


static func can_paint_sidewalk_cell(floor_data: FloorData, cell: Vector2i) -> bool:
	return not floor_data.cells.has(cell) and not floor_data.porch_cells.has(cell)
