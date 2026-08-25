@tool
class_name WallBuilder
extends RefCounted


const SLOT_SIDING := "siding"

static func build(house: HouseData, floor_data: FloorData, floor_base_y: float, accumulator: SurfaceAccumulator, openings: Array[Dictionary] = [], is_lowest: bool = false, floor_below: FloorData = null) -> void:
	var half_thickness: float = house.wall_thickness * 0.5
	var base_y: float = house.foundation_top_y() if is_lowest else floor_base_y
	var top_y: float = floor_base_y + floor_data.height
	var cap_bottom_visibility: int = _base_visibility(floor_data, is_lowest, floor_below)

	var loops: Array[BoundaryLoop] = Footprint.trace_loops(floor_data.cells, house.level_cell_size)
	for loop in loops:
		if openings.is_empty():
			RingGeometry.build(
				accumulator, SLOT_SIDING, house.siding_material, loop,
				half_thickness, half_thickness, base_y, top_y, true, true,
				SurfaceAccumulator.Visibility.INTERIOR, SurfaceAccumulator.Visibility.BURIED,
				cap_bottom_visibility
			)
		else:
			PerforatedRing.build(
				accumulator, SLOT_SIDING, house.siding_material, loop,
				half_thickness, half_thickness, base_y, top_y, openings, true, true,
				SurfaceAccumulator.Visibility.INTERIOR, SurfaceAccumulator.Visibility.BURIED,
				cap_bottom_visibility
			)


static func _base_visibility(floor_data: FloorData, is_lowest: bool, floor_below: FloorData) -> int:
	if is_lowest:
		return SurfaceAccumulator.Visibility.BURIED
	if floor_below == null:
		return SurfaceAccumulator.Visibility.EXTERIOR

	for cell in floor_data.cells:
		if not floor_below.cells.has(cell) and not floor_below.porch_cells.has(cell):
			return SurfaceAccumulator.Visibility.EXTERIOR
	return SurfaceAccumulator.Visibility.INTERIOR
