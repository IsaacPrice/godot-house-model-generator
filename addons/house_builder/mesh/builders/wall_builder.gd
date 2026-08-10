@tool
class_name WallBuilder
extends RefCounted


const SLOT_SIDING := "siding"

static func build(house: HouseData, floor_data: FloorData, floor_base_y: float, accumulator: SurfaceAccumulator, openings: Array[Dictionary] = [], is_lowest: bool = false) -> void:
	var half_thickness: float = house.wall_thickness * 0.5
	var base_y: float = house.foundation_top_y() if is_lowest else floor_base_y
	var top_y: float = floor_base_y + floor_data.height

	var loops: Array[BoundaryLoop] = Footprint.trace_loops(floor_data.cells, house.level_cell_size)
	for loop in loops:
		if openings.is_empty():
			RingGeometry.build(accumulator, SLOT_SIDING, house.siding_material, loop, half_thickness, half_thickness, base_y, top_y)
		else:
			PerforatedRing.build(accumulator, SLOT_SIDING, house.siding_material, loop, half_thickness, half_thickness, base_y, top_y, openings)
