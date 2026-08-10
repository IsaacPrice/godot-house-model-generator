@tool
class_name PorchBuilder
extends RefCounted


const SLOT_FLOOR := "porch_floor"
const SLOT_RAILING := "porch_railing"
const SLOT_POST := "porch_post"
const SLOT_BALUSTER := "porch_baluster"
const SLOT_UNDERLAYMENT := "roof_underlayment"
const SLOT_TRIM := "trim"

enum PostRole { INTERMEDIATE, END, CORNER }

const EPS := 1e-3


static func build(house: HouseData, floor_data: FloorData, accumulator: SurfaceAccumulator, roof_models: Array[Dictionary]) -> void:
	var cell_size: float = house.level_cell_size
	var valid_cells: Array[Vector2i] = _valid_porch_cells(floor_data, true)
	if valid_cells.is_empty():
		return

	var deck_top: float = -DetailConstants.PORCH_DROP
	var runs: Array[Dictionary] = _open_runs(floor_data, valid_cells, cell_size)
	var roof_context: Dictionary = {}
	if house.porch_has_roof:
		roof_context = _build_roof_context(house, floor_data, valid_cells, cell_size, roof_models)

	_emit_deck(house, accumulator, valid_cells, cell_size, deck_top, runs)
	_emit_posts_and_railings(house, accumulator, runs, deck_top, roof_context)
	if not roof_context.is_empty():
		_emit_ceiling(house, accumulator, roof_context)
		_emit_perimeter_band(house, accumulator, runs, roof_context)


static func roof_cells(house: HouseData, floor_data: FloorData) -> Array[Vector2i]:
	var cells: Array[Vector2i] = floor_data.cells.duplicate()
	if house.porch_has_roof:
		cells.append_array(_valid_porch_cells(floor_data, false))
	return cells


static func stair_runs(house: HouseData, floor_data: FloorData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var valid_cells: Array[Vector2i] = _valid_porch_cells(floor_data, false)
	if valid_cells.is_empty():
		return result

	var deck_top: float = -DetailConstants.PORCH_DROP
	var grade: float = house.grade_y()
	var total_rise: float = deck_top - grade
	if total_rise <= EPS:
		return result

	for run in _open_runs(floor_data, valid_cells, house.level_cell_size):
		for subrun in _split_subruns(run, house.level_cell_size):
			if not subrun["is_stairs"]:
				continue
			var detail: WallDetail = subrun["detail"]
			var step_count: int = maxi(1, roundi(total_rise / detail.stair_step_height))
			if step_count < 2:
				continue
			result.append({
				"p0": subrun["p0"],
				"p1": subrun["p1"],
				"normal": run["normal"],
				"deck_top": deck_top,
				"base_y": grade,
				"run": (step_count - 1) * detail.stair_step_depth + house.porch_floor_overhang,
			})
	return result


static func railing_runs(house: HouseData, floor_data: FloorData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var valid_cells: Array[Vector2i] = _valid_porch_cells(floor_data, false)
	if valid_cells.is_empty():
		return result

	var deck_top: float = -DetailConstants.PORCH_DROP
	var total_rise: float = deck_top - house.grade_y()
	for run in _open_runs(floor_data, valid_cells, house.level_cell_size):
		for subrun in _split_subruns(run, house.level_cell_size):
			if not subrun["is_stairs"]:
				result.append({
					"kind": "level",
					"p0": subrun["p0"],
					"p1": subrun["p1"],
					"normal": run["normal"],
					"deck_top": deck_top,
				})
			elif subrun["detail"].stair_has_railing and total_rise > EPS:
				var detail: WallDetail = subrun["detail"]
				var step_count: int = maxi(1, roundi(total_rise / detail.stair_step_height))
				for anchor in [subrun["p0"], subrun["p1"]]:
					result.append({
						"kind": "stair",
						"anchor": anchor,
						"normal": run["normal"],
						"d": run["dir"],
						"run": step_count * detail.stair_step_depth,
						"deck_top": deck_top,
						"rise": total_rise,
					})
	return result


static func post_plan(house: HouseData, floor_data: FloorData) -> Array[Dictionary]:
	var valid_cells: Array[Vector2i] = _valid_porch_cells(floor_data, false)
	if valid_cells.is_empty():
		return []
	return _plan_posts(house, _open_runs(floor_data, valid_cells, house.level_cell_size), house.level_cell_size)


static func _valid_porch_cells(floor_data: FloorData, warn: bool) -> Array[Vector2i]:
	var valid: Array[Vector2i] = []
	for cell in floor_data.porch_cells:
		if floor_data.cells.has(cell):
			if warn:
				push_warning("House builder: porch cell %s overlaps the house footprint; skipped." % cell)
		else:
			valid.append(cell)
	return valid


static func _build_roof_context(house: HouseData, floor_data: FloorData, valid_cells: Array[Vector2i], cell_size: float, roof_models: Array[Dictionary]) -> Dictionary:
	var region_offset: float = house.wall_thickness * 0.5 - RoofConstants.WALL_CLIP_EMBED
	var regions: Array[PackedVector2Array] = []
	for loop in Footprint.trace_loops(valid_cells, cell_size):
		regions.append_array(Geometry2D.offset_polygon(loop.points, region_offset, Geometry2D.JOIN_MITER))

	var min_y: float = INF
	for region in regions:
		min_y = minf(min_y, RoofSurface.min_height_over_region(roof_models, region, floor_data.level))
	if min_y == INF:
		push_warning("House builder: porch roof skipped - no roof surface above the porch.")
		return {}

	return {
		"models": roof_models,
		"level": floor_data.level,
		"regions": regions,
		"ceiling_y": min_y - DetailConstants.PORCH_CEILING_DROP,
	}


static func _open_runs(floor_data: FloorData, valid_cells: Array[Vector2i], cell_size: float) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for cell in valid_cells:
		for direction in WallDetail.EdgeDir.values():
			if not DetailRules.is_boundary_edge(valid_cells, cell, direction):
				continue
			if floor_data.cells.has(cell + Vector2i(WallDetail.NORMALS[direction])):
				continue
			var horizontal: bool = direction == WallDetail.EdgeDir.NORTH or direction == WallDetail.EdgeDir.SOUTH
			var key: Array = [direction, cell.y if horizontal else cell.x]
			if not groups.has(key):
				groups[key] = []
			var detail: WallDetail = floor_data.get_wall_detail(cell, direction)
			var is_stairs: bool = detail != null and detail.type == WallDetail.DetailType.STAIRS
			groups[key].append({
				"cell": cell,
				"along": cell.x if horizontal else cell.y,
				"gap": is_stairs,
				"detail": detail if is_stairs else null,
			})

	var runs: Array[Dictionary] = []
	for key in groups:
		var direction: int = key[0]
		var normal: Vector2 = WallDetail.NORMALS[direction]
		var entries: Array = groups[key]
		entries.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["along"] < y["along"])

		var start_index: int = 0
		for k in range(entries.size() + 1):
			var breaks: bool = k == entries.size() or (k > 0 and entries[k]["along"] != entries[k - 1]["along"] + 1)
			if not breaks:
				continue
			var run_entries: Array = entries.slice(start_index, k)
			start_index = k
			var d: Vector2 = Vector2(-normal.y, normal.x)
			var first: PackedVector2Array = WallDetail.endpoints(run_entries[0]["cell"], direction, cell_size)
			if (first[1] - first[0]).normalized().dot(d) < 0.0:
				run_entries.reverse()
			var edges: Array[Dictionary] = []
			for entry in run_entries:
				edges.append({"cell": entry["cell"], "gap": entry["gap"], "detail": entry["detail"]})
			var run_start: PackedVector2Array = WallDetail.endpoints(edges[0]["cell"], direction, cell_size)
			var start: Vector2 = run_start[1] if (run_start[1] - run_start[0]).normalized().dot(d) < 0.0 else run_start[0]
			runs.append({
				"normal": normal,
				"dir": d,
				"direction": direction,
				"start": start,
				"edges": edges,
			})
	return runs


static func _emit_deck(house: HouseData, accumulator: SurfaceAccumulator, valid_cells: Array[Vector2i], cell_size: float, deck_top: float, runs: Array[Dictionary]) -> void:
	var overhang: float = house.porch_floor_overhang
	var corner_partners: Dictionary = _corner_partners(runs, cell_size) if overhang > 0.0 else {}

	var polys: Array[PackedVector2Array] = []
	for loop in Footprint.trace_loops(valid_cells, cell_size):
		polys.append(loop.points)
	if overhang > 0.0:
		for run in runs:
			for subrun in _split_subruns(run, cell_size):
				_union_into(polys, _subrun_overhang_rect(subrun["p0"], subrun["p1"], run["normal"], overhang, corner_partners))
	for poly in polys:
		PlanPolygon.emit_horizontal(accumulator, SLOT_FLOOR, house.porch_floor_material, poly, deck_top, true)

	var slab_bottom: float = deck_top - house.porch_floor_thickness
	var foundation_base: float = house.foundation_base_y()
	for run in runs:
		var normal: Vector2 = run["normal"]
		for subrun in _split_subruns(run, cell_size):
			var structural0: Vector2 = subrun["p0"]
			var structural1: Vector2 = subrun["p1"]
			var slab0: Vector2 = structural0
			var slab1: Vector2 = structural1
			if overhang > 0.0:
				slab0 = _offset_corner(structural0, normal, overhang, corner_partners)
				slab1 = _offset_corner(structural1, normal, overhang, corner_partners)
			_vertical_quad(accumulator, SLOT_FLOOR, house.porch_floor_material, slab0, slab1, slab_bottom, deck_top, normal, deck_top)
			if overhang > 0.0:
				PlanPolygon.emit_horizontal(accumulator, SLOT_FLOOR, house.porch_floor_material, PackedVector2Array([structural0, structural1, slab1, slab0]), slab_bottom, false)
			if not subrun["is_stairs"] and slab_bottom > foundation_base + EPS:
				_vertical_quad(accumulator, "foundation", house.foundation_material, structural0, structural1, foundation_base, slab_bottom, normal, slab_bottom)


static func _corner_partners(runs: Array[Dictionary], cell_size: float) -> Dictionary:
	var by_point: Dictionary = {}
	for run in runs:
		var end: Vector2 = run["start"] + run["dir"] * (run["edges"].size() * cell_size)
		for point in [run["start"], end]:
			var key := Vector2i((point * 1000.0).round())
			if not by_point.has(key):
				by_point[key] = []
			by_point[key].append(run["normal"])
	return by_point


static func _offset_corner(point: Vector2, own_normal: Vector2, overhang: float, corner_partners: Dictionary) -> Vector2:
	var offset: Vector2 = own_normal * overhang
	var key := Vector2i((point * 1000.0).round())
	for other_normal in corner_partners.get(key, []):
		if other_normal != own_normal:
			offset += other_normal * overhang
	return point + offset


static func _subrun_overhang_rect(p0: Vector2, p1: Vector2, normal: Vector2, overhang: float, corner_partners: Dictionary) -> PackedVector2Array:
	var offset_p0: Vector2 = _offset_corner(p0, normal, overhang, corner_partners)
	var offset_p1: Vector2 = _offset_corner(p1, normal, overhang, corner_partners)
	return PackedVector2Array([p0, p1, offset_p1, offset_p0])


static func _union_into(polys: Array[PackedVector2Array], rect: PackedVector2Array) -> void:
	for i in range(polys.size()):
		var merged: Array[PackedVector2Array] = Geometry2D.merge_polygons(polys[i], rect)
		if merged.size() == 1:
			polys[i] = merged[0]
			return
	polys.append(rect)


static func _emit_ceiling(house: HouseData, accumulator: SurfaceAccumulator, roof_context: Dictionary) -> void:
	for region in roof_context["regions"]:
		PlanPolygon.emit_horizontal(accumulator, SLOT_UNDERLAYMENT, house.roof_underlayment_material, region, roof_context["ceiling_y"], false)

static func _soffit_y(house: HouseData, roof_context: Dictionary) -> float:
	for entry in roof_context["models"]:
		if entry["floor_level"] != roof_context["level"]:
			continue
		var model: RoofModel = entry["model"]
		for edge in model.edges:
			if edge.type == RoofModel.EdgeType.EAVE:
				return minf(edge.a.y, edge.b.y) - house.roof_fascia_height
	return -INF


static func _emit_perimeter_band(house: HouseData, accumulator: SurfaceAccumulator, runs: Array[Dictionary], roof_context: Dictionary) -> void:
	var bottom_y: float = _soffit_y(house, roof_context)
	var top_y: float = roof_context["ceiling_y"] + DetailConstants.POST_ROOF_EMBED
	if bottom_y == -INF or top_y <= bottom_y + EPS:
		return

	for run in runs:
		var d: Vector2 = run["dir"]
		var normal: Vector2 = run["normal"]
		var start: Vector2 = run["start"]
		var length: float = run["edges"].size() * house.level_cell_size
		var end: Vector2 = start + d * length

		for side in [1.0, -1.0]:
			PlanPolygon.oriented_quad(
				accumulator, SLOT_TRIM, house.trim_material,
				Vector3(start.x, bottom_y, start.y),
				Vector3(start.x, top_y, start.y),
				Vector3(end.x, top_y, end.y),
				Vector3(end.x, bottom_y, end.y),
				Vector3(normal.x * side, 0.0, normal.y * side),
				Vector2(0, top_y - bottom_y), Vector2(0, 0),
				Vector2(length, 0), Vector2(length, top_y - bottom_y)
			)


static func _emit_posts_and_railings(house: HouseData, accumulator: SurfaceAccumulator, runs: Array[Dictionary], deck_top: float, roof_context: Dictionary) -> void:
	var cell_size: float = house.level_cell_size
	var post_top: float = deck_top + house.porch_railing_height
	if roof_context.has("ceiling_y"):
		post_top = roof_context["ceiling_y"] + DetailConstants.POST_ROOF_EMBED

	_emit_posts(house, accumulator, _plan_posts(house, runs, cell_size), deck_top, post_top)

	for run in runs:
		var d: Vector2 = run["dir"]
		var normal: Vector2 = run["normal"]

		for subrun in _split_subruns(run, cell_size):
			if subrun["is_stairs"]:
				_emit_stairs(house, accumulator, subrun["p0"], subrun["p1"], d, normal, deck_top, subrun["detail"])
			else:
				_emit_railed_subrun(house, accumulator, subrun["p0"], subrun["p1"], d, normal, deck_top)


static func _split_subruns(run: Dictionary, cell_size: float) -> Array[Dictionary]:
	var d: Vector2 = run["dir"]
	var start: Vector2 = run["start"]
	var edges: Array[Dictionary] = run["edges"]
	var subruns: Array[Dictionary] = []
	var sub_start: int = 0
	for k in range(1, edges.size() + 1):
		if k < edges.size() and edges[k]["gap"] == edges[sub_start]["gap"]:
			continue
		subruns.append({
			"p0": start + d * (sub_start * cell_size),
			"p1": start + d * (k * cell_size),
			"is_stairs": edges[sub_start]["gap"],
			"detail": edges[sub_start]["detail"],
		})
		sub_start = k
	return subruns


static func _plan_posts(house: HouseData, runs: Array[Dictionary], cell_size: float) -> Array[Dictionary]:
	var corner_normals: Dictionary = _corner_partners(runs, cell_size)
	var half_post: float = house.porch_post_width * 0.5
	var planned: Array[Dictionary] = []

	for run in runs:
		var d: Vector2 = run["dir"]
		var center_offset: Vector2 = -run["normal"] * half_post
		var subruns: Array[Dictionary] = _split_subruns(run, cell_size)
		for i in range(subruns.size()):
			var subrun: Dictionary = subruns[i]
			if subrun["is_stairs"]:
				if subrun["detail"].stair_has_railing:
					for anchor in [subrun["p0"], subrun["p1"]]:
						var head_role: int = PostRole.CORNER if _normals_at(anchor, corner_normals).size() == 2 else PostRole.END
						_add_post(planned, house.porch_post_width, anchor, head_role, true)
				continue

			var length: float = subrun["p0"].distance_to(subrun["p1"])
			var segment_count: int = maxi(1, ceili(length / DetailConstants.POST_MAX_SPACING))
			for k in range(segment_count + 1):
				var source: Vector2 = subrun["p0"] + d * (length * k / segment_count)
				var center: Vector2 = source + center_offset
				var role: int = PostRole.INTERMEDIATE
				if k == 0 or k == segment_count:
					var normals: Array = _normals_at(source, corner_normals)
					if normals.size() == 2:
						center = source - (normals[0] + normals[1]) * half_post
						role = PostRole.CORNER
					elif _borders_stairs(subruns, (i - 1) if k == 0 else (i + 1)):
						role = PostRole.END
					else:
						center += d * (half_post if k == 0 else -half_post)
				_add_post(planned, house.porch_post_width, center, role, false)
	return planned


static func _borders_stairs(subruns: Array[Dictionary], index: int) -> bool:
	return index >= 0 and index < subruns.size() and subruns[index]["is_stairs"]


static func _normals_at(point: Vector2, corner_normals: Dictionary) -> Array:
	var distinct: Array = []
	for normal in corner_normals.get(Vector2i((point * 1000.0).round()), []):
		if not distinct.has(normal):
			distinct.append(normal)
	return distinct


static func _add_post(planned: Array[Dictionary], merge_distance: float, center: Vector2, role: int, provisional: bool) -> void:
	for entry in planned:
		if entry["center"].distance_to(center) >= merge_distance:
			continue
		entry["role"] = maxi(entry["role"], role)
		if entry["provisional"] and not provisional:
			entry["center"] = center
			entry["provisional"] = false
		return
	planned.append({"center": center, "role": role, "provisional": provisional})


static func _emit_posts(house: HouseData, accumulator: SurfaceAccumulator, planned: Array[Dictionary], deck_top: float, post_top: float) -> void:
	var half_post: float = house.porch_post_width * 0.5
	for entry in planned:
		var center: Vector2 = entry["center"]
		var base_y: float = deck_top
		if _wants_post_base(house, entry["role"]):
			base_y = _emit_post_base(house, accumulator, center, deck_top, post_top)
		if post_top - base_y <= EPS:
			continue
		BoxBuilder.build(
			accumulator, SLOT_POST, house.porch_post_material,
			center - Vector2(half_post, half_post), center + Vector2(half_post, half_post),
			base_y, post_top
		)


static func _wants_post_base(house: HouseData, role: int) -> bool:
	match house.porch_post_base_mode:
		HouseData.PostBaseMode.ALL:
			return true
		HouseData.PostBaseMode.ENDS_AND_CORNERS:
			return role != PostRole.INTERMEDIATE
		_:
			return false


static func _emit_post_base(house: HouseData, accumulator: SurfaceAccumulator, center: Vector2, deck_top: float, post_top: float) -> float:
	var base_half: float = maxf(house.porch_post_base_width, house.porch_post_width) * 0.5
	var trim_half: float = base_half + house.porch_post_base_trim_overhang
	var trim_height: float = house.porch_post_base_trim_height
	var pier_top: float = clampf(deck_top + house.porch_post_base_height, deck_top, post_top - trim_height - EPS)
	var trim_top: float = pier_top + trim_height
	var foundation_base: float = house.foundation_base_y()

	if pier_top > foundation_base + EPS:
		BoxBuilder.build(
			accumulator, "foundation", house.foundation_material,
			center - Vector2(base_half, base_half), center + Vector2(base_half, base_half),
			foundation_base, pier_top
		)
	BoxBuilder.build(
		accumulator, SLOT_TRIM, house.trim_material,
		center - Vector2(trim_half, trim_half), center + Vector2(trim_half, trim_half),
		pier_top, trim_top
	)
	return trim_top


static func _emit_railed_subrun(
	house: HouseData, accumulator: SurfaceAccumulator,
	p0: Vector2, p1: Vector2, d: Vector2, normal: Vector2, deck_top: float
) -> void:
	var length: float = p0.distance_to(p1)
	var center_offset: Vector2 = -normal * house.porch_post_width * 0.5

	var rail_half: float = DetailConstants.RAIL_WIDTH * 0.5
	var near: Vector2 = p0 + center_offset - normal * rail_half
	var far: Vector2 = p1 + center_offset + normal * rail_half
	var top: float = deck_top + house.porch_railing_height
	BoxBuilder.build(accumulator, SLOT_RAILING, house.porch_railing_material, near, far, deck_top + DetailConstants.BOTTOM_RAIL_BASE, deck_top + DetailConstants.BOTTOM_RAIL_TOP)
	BoxBuilder.build(accumulator, SLOT_RAILING, house.porch_railing_material, near, far, top - DetailConstants.TOP_RAIL_HEIGHT, top)

	var infill_bottom: float = deck_top + DetailConstants.BOTTOM_RAIL_TOP
	var infill_top: float = top - DetailConstants.TOP_RAIL_HEIGHT
	match house.porch_railing_style:
		HouseData.RailingStyle.PICKET:
			var count: int = maxi(1, roundi(length / house.porch_baluster_spacing))
			var half_baluster: float = house.porch_baluster_width * 0.5
			for k in range(count):
				var center: Vector2 = p0 + d * (length * (k + 0.5) / count) + center_offset
				BoxBuilder.build(
					accumulator, SLOT_BALUSTER, house.porch_baluster_material,
					center - Vector2(half_baluster, half_baluster), center + Vector2(half_baluster, half_baluster),
					infill_bottom, infill_top
				)
		HouseData.RailingStyle.HORIZONTAL:
			var half_rail: float = house.porch_horizontal_rail_height * 0.5
			for fraction in _rail_fractions(house):
				var mid: float = lerpf(infill_bottom, infill_top, fraction)
				BoxBuilder.build(
					accumulator, SLOT_BALUSTER, house.porch_baluster_material,
					near, far, mid - half_rail, mid + half_rail
				)
		HouseData.RailingStyle.CROSS:
			var cell_size: float = house.level_cell_size
			var sections: int = maxi(1, roundi(length / cell_size))
			for k in range(sections):
				var s0: float = length * k / sections
				var s1: float = length * (k + 1) / sections
				_cross_slat(house, accumulator, p0, d, normal, center_offset, s0, infill_bottom, s1, infill_top)
				_cross_slat(house, accumulator, p0, d, normal, center_offset, s0, infill_top, s1, infill_bottom)


static func _rail_fractions(house: HouseData) -> Array[float]:
	var count: int = maxi(1, house.porch_horizontal_rail_count)
	var fractions: Array[float] = []
	for k in range(1, count + 1):
		fractions.append(float(k) / float(count + 1))
	return fractions


static func _cross_slat(
	house: HouseData, accumulator: SurfaceAccumulator,
	p0: Vector2, d: Vector2, normal: Vector2, center_offset: Vector2,
	s0: float, y0: float, s1: float, y1: float
) -> void:
	var a2 := Vector2(s0, y0)
	var b2 := Vector2(s1, y1)
	var axis: Vector2 = (b2 - a2).normalized()
	var perp: Vector2 = Vector2(-axis.y, axis.x) * (DetailConstants.CROSS_SLAT_WIDTH * 0.5)
	var half_thick: Vector2 = normal * (DetailConstants.CROSS_SLAT_THICKNESS * 0.5)
	var slat_length: float = a2.distance_to(b2)

	for side in [1.0, -1.0]:
		var offset: Vector2 = center_offset + half_thick * side
		var face_normal := Vector3(normal.x * side, 0.0, normal.y * side)
		var corners: Array[Vector3] = []
		for corner2 in [a2 - perp, a2 + perp, b2 + perp, b2 - perp]:
			var plan: Vector2 = p0 + d * corner2.x + offset
			corners.append(Vector3(plan.x, corner2.y, plan.y))
		PlanPolygon.oriented_quad(
			accumulator, SLOT_BALUSTER, house.porch_baluster_material,
			corners[0], corners[1], corners[2], corners[3], face_normal,
			Vector2(0, DetailConstants.CROSS_SLAT_WIDTH), Vector2(0, 0),
			Vector2(slat_length, 0), Vector2(slat_length, DetailConstants.CROSS_SLAT_WIDTH)
		)


static func _emit_stairs(
	house: HouseData, accumulator: SurfaceAccumulator,
	p0: Vector2, p1: Vector2, d: Vector2, normal: Vector2,
	deck_top: float, detail: WallDetail
) -> void:
	var grade: float = house.grade_y()
	var total_rise: float = deck_top - grade
	if total_rise <= EPS:
		return

	var step_count: int = maxi(1, roundi(total_rise / detail.stair_step_height))
	var actual_rise: float = total_rise / step_count
	var depth: float = detail.stair_step_depth
	var overhang: float = house.porch_floor_overhang
	var thickness: float = house.porch_floor_thickness

	for i in range(step_count):
		var tread_top: float = deck_top - actual_rise * (i + 1)
		var tread_bottom: float = maxf(tread_top - thickness, grade)
		var back0: Vector2 = p0 + normal * (i * depth)
		var back1: Vector2 = p1 + normal * (i * depth)

		var riser_top: float = deck_top - thickness - actual_rise * i
		if riser_top > tread_bottom + EPS:
			_vertical_quad(accumulator, "foundation", house.foundation_material, back0, back1, tread_bottom, riser_top, normal, riser_top)

		if i == step_count - 1:
			continue

		var near: Vector2 = back0 - d * overhang
		var far: Vector2 = back1 + normal * (depth + overhang) + d * overhang
		BoxBuilder.build(accumulator, SLOT_FLOOR, house.porch_floor_material, near, far, tread_bottom, tread_top)

	_emit_stair_stringer(house, accumulator, p0, normal, -d, step_count, depth, actual_rise, deck_top, grade, thickness)
	_emit_stair_stringer(house, accumulator, p1, normal, d, step_count, depth, actual_rise, deck_top, grade, thickness)

	if detail.stair_has_railing:
		_emit_stair_railing(house, accumulator, p0, p1, d, normal, deck_top, step_count, depth, actual_rise)


static func _emit_stair_stringer(
	house: HouseData, accumulator: SurfaceAccumulator,
	anchor: Vector2, normal: Vector2, face_dir: Vector2,
	step_count: int, depth: float, actual_rise: float, deck_top: float, foundation_base: float, thickness: float
) -> void:
	var face_normal := Vector3(face_dir.x, 0.0, face_dir.y)
	for i in range(step_count):
		var y_top: float = deck_top - actual_rise * (i + 1) - thickness
		if y_top <= foundation_base + EPS:
			continue
		var a: Vector2 = anchor + normal * (i * depth)
		var b: Vector2 = anchor + normal * ((i + 1) * depth)
		PlanPolygon.oriented_quad(
			accumulator, "foundation", house.foundation_material,
			Vector3(a.x, foundation_base, a.y), Vector3(b.x, foundation_base, b.y),
			Vector3(b.x, y_top, b.y), Vector3(a.x, y_top, a.y),
			face_normal,
			Vector2(i * depth, 0), Vector2((i + 1) * depth, 0), Vector2((i + 1) * depth, y_top - foundation_base), Vector2(i * depth, y_top - foundation_base)
		)


static func _emit_stair_railing(
	house: HouseData, accumulator: SurfaceAccumulator,
	p0: Vector2, p1: Vector2, d: Vector2, normal: Vector2,
	deck_top: float, step_count: int, depth: float, actual_rise: float
) -> void:
	var total_run: float = step_count * depth
	var total_rise: float = step_count * actual_rise
	for anchor in [p0, p1]:
		_emit_stair_railing_side(house, accumulator, anchor, d, normal, deck_top, total_run, total_rise)


static func _emit_stair_railing_side(
	house: HouseData, accumulator: SurfaceAccumulator,
	anchor: Vector2, d: Vector2, normal: Vector2,
	deck_top: float, total_run: float, total_rise: float
) -> void:
	var slope: float = total_rise / total_run
	var rake := func(u: float) -> float: return deck_top - slope * u
	var half_post: float = house.porch_post_width * 0.5
	var rail_half: float = DetailConstants.RAIL_WIDTH * 0.5

	var segment_count: int = maxi(1, ceili(total_run / DetailConstants.POST_MAX_SPACING))
	for k in range(1, segment_count + 1):
		var u: float = total_run * k / segment_count
		var point: Vector2 = anchor + normal * u
		var base_y: float = rake.call(u)
		BoxBuilder.build(
			accumulator, SLOT_POST, house.porch_post_material,
			point - Vector2(half_post, half_post), point + Vector2(half_post, half_post),
			base_y, base_y + house.porch_railing_height
		)

	var top_offset: float = house.porch_railing_height - DetailConstants.TOP_RAIL_HEIGHT
	_sloped_box(accumulator, SLOT_RAILING, house.porch_railing_material, anchor, normal, d, rail_half, total_run,
		deck_top + DetailConstants.BOTTOM_RAIL_BASE, deck_top + DetailConstants.BOTTOM_RAIL_TOP,
		deck_top - total_rise + DetailConstants.BOTTOM_RAIL_BASE, deck_top - total_rise + DetailConstants.BOTTOM_RAIL_TOP)
	_sloped_box(accumulator, SLOT_RAILING, house.porch_railing_material, anchor, normal, d, rail_half, total_run,
		deck_top + top_offset, deck_top + house.porch_railing_height,
		deck_top - total_rise + top_offset, deck_top - total_rise + house.porch_railing_height)

	match house.porch_railing_style:
		HouseData.RailingStyle.PICKET:
			var count: int = maxi(1, roundi(total_run / house.porch_baluster_spacing))
			var half_baluster: float = house.porch_baluster_width * 0.5
			for k in range(count):
				var u: float = total_run * (k + 0.5) / count
				var center: Vector2 = anchor + normal * u
				var bottom: float = rake.call(u) + DetailConstants.BOTTOM_RAIL_TOP
				var top: float = rake.call(u) + top_offset
				BoxBuilder.build(
					accumulator, SLOT_BALUSTER, house.porch_baluster_material,
					center - Vector2(half_baluster, half_baluster), center + Vector2(half_baluster, half_baluster),
					bottom, top
				)
		HouseData.RailingStyle.HORIZONTAL:
			var half_rail: float = house.porch_horizontal_rail_height * 0.5
			for fraction in _rail_fractions(house):
				var near_mid: float = lerpf(deck_top + DetailConstants.BOTTOM_RAIL_TOP, deck_top + top_offset, fraction)
				var far_mid: float = lerpf(deck_top - total_rise + DetailConstants.BOTTOM_RAIL_TOP, deck_top - total_rise + top_offset, fraction)
				_sloped_box(accumulator, SLOT_BALUSTER, house.porch_baluster_material, anchor, normal, d, rail_half, total_run,
					near_mid - half_rail, near_mid + half_rail, far_mid - half_rail, far_mid + half_rail)
		HouseData.RailingStyle.CROSS:
			var sections: int = maxi(1, roundi(total_run / house.level_cell_size))
			for k in range(sections):
				var u0: float = total_run * k / sections
				var u1: float = total_run * (k + 1) / sections
				_cross_slat(house, accumulator, anchor, normal, d, Vector2.ZERO, u0, rake.call(u0) + DetailConstants.BOTTOM_RAIL_TOP, u1, rake.call(u1) + top_offset)
				_cross_slat(house, accumulator, anchor, normal, d, Vector2.ZERO, u0, rake.call(u0) + top_offset, u1, rake.call(u1) + DetailConstants.BOTTOM_RAIL_TOP)


static func _sloped_box(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	origin: Vector2, axis: Vector2, lateral: Vector2, lateral_half: float, length: float,
	near_bottom: float, near_top: float, far_bottom: float, far_top: float
) -> void:
	var far_origin: Vector2 = origin + axis * length
	var sides: Dictionary = {}
	for side in [1.0, -1.0]:
		var near: Vector2 = origin + lateral * (lateral_half * side)
		var far: Vector2 = far_origin + lateral * (lateral_half * side)
		sides[side] = {
			"nb": Vector3(near.x, near_bottom, near.y), "nt": Vector3(near.x, near_top, near.y),
			"fb": Vector3(far.x, far_bottom, far.y), "ft": Vector3(far.x, far_top, far.y),
		}

	for side in [1.0, -1.0]:
		var c: Dictionary = sides[side]
		var face_normal := Vector3(lateral.x * side, 0.0, lateral.y * side)
		PlanPolygon.oriented_quad(accumulator, slot, material, c["nb"], c["nt"], c["ft"], c["fb"], face_normal,
			Vector2(0, 0), Vector2(0, near_top - near_bottom), Vector2(length, far_top - far_bottom), Vector2(length, 0))

	var c1: Dictionary = sides[1.0]
	var c2: Dictionary = sides[-1.0]
	var axis_normal := Vector3(axis.x, 0.0, axis.y)
	PlanPolygon.oriented_quad(accumulator, slot, material, c1["nt"], c2["nt"], c2["ft"], c1["ft"], Vector3.UP,
		Vector2(0, 0), Vector2(2.0 * lateral_half, 0), Vector2(2.0 * lateral_half, length), Vector2(0, length))
	PlanPolygon.oriented_quad(accumulator, slot, material, c1["nb"], c2["nb"], c2["fb"], c1["fb"], Vector3.DOWN,
		Vector2(0, 0), Vector2(2.0 * lateral_half, 0), Vector2(2.0 * lateral_half, length), Vector2(0, length))
	PlanPolygon.oriented_quad(accumulator, slot, material, c1["nb"], c1["nt"], c2["nt"], c2["nb"], -axis_normal,
		Vector2(0, 0), Vector2(0, near_top - near_bottom), Vector2(2.0 * lateral_half, near_top - near_bottom), Vector2(2.0 * lateral_half, 0))
	PlanPolygon.oriented_quad(accumulator, slot, material, c1["fb"], c1["ft"], c2["ft"], c2["fb"], axis_normal,
		Vector2(0, 0), Vector2(0, far_top - far_bottom), Vector2(2.0 * lateral_half, far_top - far_bottom), Vector2(2.0 * lateral_half, 0))


static func _vertical_quad(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	x0: Vector2, x1: Vector2, y0: float, y1: float, normal: Vector2, v_ref: float
) -> void:
	var length: float = x0.distance_to(x1)
	accumulator.add_quad(
		slot, material,
		Vector3(x0.x, y0, x0.y),
		Vector3(x0.x, y1, x0.y),
		Vector3(x1.x, y1, x1.y),
		Vector3(x1.x, y0, x1.y),
		Vector3(normal.x, 0, normal.y),
		Vector2(0, v_ref - y0), Vector2(0, v_ref - y1), Vector2(length, v_ref - y1), Vector2(length, v_ref - y0)
	)
