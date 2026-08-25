@tool
class_name TrimBuilder
extends RefCounted


const SLOT_TRIM := "trim"

static func build_all(house: HouseData, accumulator: SurfaceAccumulator) -> Array[Dictionary]:
	var half_thickness: float = house.wall_thickness * 0.5
	var ground_reaching: Array[Dictionary] = []
	var previous_corners: Dictionary = {}

	var floor_base_y: float = 0.0
	for floor_data in house.floors:
		var top_y: float = floor_base_y + floor_data.height
		var loops: Array[BoundaryLoop] = Footprint.trace_loops(floor_data.cells, house.level_cell_size)
		var current_corners: Dictionary = {}

		for loop in loops:
			var n: int = loop.size()
			for i in range(n):
				var normal_in: Vector2 = loop.normals[(i - 1 + n) % n]
				var normal_out: Vector2 = loop.normals[i]
				var turn: float = normal_in.x * normal_out.y - normal_in.y * normal_out.x
				if turn <= 0.0:
					continue

				var bisector: Vector2 = normal_in + normal_out
				var outer_point: Vector2 = loop.corner_offset(i, half_thickness)
				current_corners[outer_point] = bisector

				var continues_from_below: bool = previous_corners.has(outer_point) and previous_corners[outer_point].is_equal_approx(bisector)
				var reaches_ground: bool = floor_base_y == 0.0 and not continues_from_below
				var post_base_y: float = house.foundation_top_y() if reaches_ground else floor_base_y

				var near: Vector2 = loop.corner_offset(i, -half_thickness)
				var far: Vector2 = outer_point + bisector * house.corner_trim_width
				var interior: int = BoxBuilder.face_toward(-normal_in) | BoxBuilder.face_toward(-normal_out)
				BoxBuilder.build(accumulator, SLOT_TRIM, house.trim_material, near, far, post_base_y, top_y, BoxBuilder.Face.TOP, interior)

				if reaches_ground:
					ground_reaching.append({"near": near, "far": far})

		previous_corners = current_corners
		floor_base_y = top_y

	return ground_reaching
