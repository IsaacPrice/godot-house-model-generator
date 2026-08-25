@tool
class_name FoundationBuilder
extends RefCounted


const SLOT_FOUNDATION := "foundation"

static func build(house: HouseData, ground_floor: FloorData, accumulator: SurfaceAccumulator, ground_reaching_posts: Array[Dictionary], openings: Array[Dictionary] = []) -> void:
	var half_thickness: float = house.wall_thickness * 0.5
	var top_y: float = house.foundation_top_y()
	var base_y: float = top_y - house.foundation_height

	var notches: Array[Dictionary] = []
	for op in openings:
		if op["detail"].type == WallDetail.DetailType.GARAGE_DOOR and op["bottom_y"] < top_y - PerforatedRing.POSITION_EPS:
			notches.append(op)

	var below_grade: bool = base_y <= house.grade_y() + PerforatedRing.POSITION_EPS
	var cap_bottom_visibility: int = SurfaceAccumulator.Visibility.BURIED if below_grade else SurfaceAccumulator.Visibility.EXTERIOR

	var loops: Array[BoundaryLoop] = Footprint.trace_loops(ground_floor.cells, house.level_cell_size)
	for loop in loops:
		if notches.is_empty():
			RingGeometry.build(
				accumulator, SLOT_FOUNDATION, house.foundation_material, loop,
				half_thickness, half_thickness + house.foundation_overhang,
				base_y, top_y, true, true,
				SurfaceAccumulator.Visibility.INTERIOR, SurfaceAccumulator.Visibility.EXTERIOR, cap_bottom_visibility
			)
		else:
			PerforatedRing.build(
				accumulator, SLOT_FOUNDATION, house.foundation_material, loop,
				half_thickness, half_thickness + house.foundation_overhang,
				base_y, top_y, notches, true, true,
				SurfaceAccumulator.Visibility.INTERIOR, SurfaceAccumulator.Visibility.EXTERIOR, cap_bottom_visibility
			)

	var overhang: float = house.foundation_overhang
	for post in ground_reaching_posts:
		var near: Vector2 = post["near"]
		var far: Vector2 = post["far"]
		var x0: float = min(near.x, far.x) - overhang
		var x1: float = max(near.x, far.x) + overhang
		var z0: float = min(near.y, far.y) - overhang
		var z1: float = max(near.y, far.y) + overhang
		BoxBuilder.build(accumulator, SLOT_FOUNDATION, house.foundation_material, Vector2(x0, z0), Vector2(x1, z1), base_y, top_y)
