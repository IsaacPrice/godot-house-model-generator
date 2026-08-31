@tool
class_name InteriorBuilder
extends RefCounted


const SLOT_WALL := "interior_wall"
const SLOT_FLOOR := "interior_floor"
const SLOT_CEILING := "ceiling"
const SLOT_TRIM := "interior_trim"

const ALL_FACES := BoxBuilder.Face.POS_Z | BoxBuilder.Face.NEG_Z | BoxBuilder.Face.POS_X | BoxBuilder.Face.NEG_X | BoxBuilder.Face.TOP | BoxBuilder.Face.BOTTOM

const MIN_DECK_THICKNESS := 1e-3

const RUN_EPS := 1e-3


static func build(house: HouseData, floor_infos: Array[Dictionary], accumulator: SurfaceAccumulator) -> void:
	if floor_infos.is_empty():
		return
	_build_decks(house, floor_infos, accumulator)
	_build_baseboards(house, floor_infos, accumulator)


static func deck_levels(floor_infos: Array[Dictionary]) -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	if floor_infos.is_empty():
		return levels

	var first: FloorData = floor_infos[0]["floor_data"]
	levels.append({
		"y": floor_infos[0]["base_y"],
		"cells": first.cells.duplicate(),
		"below_cells": first.cells.duplicate(),
		"sunken_cells": first.garage_cells.duplicate(),
		"is_lowest": true,
	})

	for i in range(1, floor_infos.size()):
		var below: FloorData = floor_infos[i - 1]["floor_data"]
		var above: FloorData = floor_infos[i]["floor_data"]
		levels.append({
			"y": floor_infos[i]["base_y"],
			"cells": _union(below.cells, above.cells),
			"below_cells": below.cells,
			"sunken_cells": [] as Array[Vector2i],
			"is_lowest": false,
		})

	var last: Dictionary = floor_infos[floor_infos.size() - 1]
	var top_floor: FloorData = last["floor_data"]
	levels.append({
		"y": last["top_y"],
		"cells": top_floor.cells.duplicate(),
		"below_cells": top_floor.cells,
		"sunken_cells": [] as Array[Vector2i],
		"is_lowest": false,
	})

	return levels


static func _union(a: Array[Vector2i], b: Array[Vector2i]) -> Array[Vector2i]:
	var merged: Array[Vector2i] = a.duplicate()
	for cell in b:
		if not merged.has(cell):
			merged.append(cell)
	return merged


static func _build_decks(house: HouseData, floor_infos: Array[Dictionary], accumulator: SurfaceAccumulator) -> void:
	var cell_size: float = house.level_cell_size
	var interior: int = SurfaceAccumulator.Visibility.INTERIOR
	var exterior: int = SurfaceAccumulator.Visibility.EXTERIOR

	for level in deck_levels(floor_infos):
		var cells: Array[Vector2i] = level["cells"]
		var below_cells: Array[Vector2i] = level["below_cells"]
		var tops: Dictionary = cell_tops(house, level)

		for cell in cells:
			var top_y: float = tops[cell]
			var bottom_y: float = deck_bottom(house, top_y, level["is_lowest"])
			if top_y - bottom_y < MIN_DECK_THICKNESS:
				continue

			var x0: float = cell.x * cell_size
			var x1: float = x0 + cell_size
			var z0: float = cell.y * cell_size
			var z1: float = z0 + cell_size
			var corners := PackedVector2Array([
				Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1),
			])

			PlanPolygon.emit_horizontal(
				accumulator, SLOT_FLOOR, house.interior_floor_material,
				corners, top_y, true, 1.0, interior
			)

			var under: int = interior if level["is_lowest"] or below_cells.has(cell) else exterior
			PlanPolygon.emit_horizontal(
				accumulator, SLOT_CEILING, house.ceiling_material,
				corners, bottom_y, false, 1.0, under
			)

			for k in range(4):
				var step := Vector2i(
					int(signf(corners[(k + 1) % 4].x - corners[k].x)),
					int(signf(corners[(k + 1) % 4].y - corners[k].y)))
				var outward := Vector2i(step.y, -step.x)
				var neighbour: Vector2i = cell + outward
				var side_bottom: float = bottom_y
				if tops.has(neighbour):
					if tops[neighbour] >= top_y - MIN_DECK_THICKNESS:
						continue
					side_bottom = tops[neighbour]
				_deck_side(accumulator, house, corners[k], corners[(k + 1) % 4], Vector2(outward), side_bottom, top_y)


static func cell_tops(house: HouseData, level: Dictionary) -> Dictionary:
	var tops: Dictionary = {}
	var sunken: Array[Vector2i] = level["sunken_cells"]
	var grade: float = maxf(house.grade_y(), house.foundation_base_y())
	for cell in level["cells"]:
		tops[cell] = minf(grade, level["y"]) if sunken.has(cell) else level["y"]
	return tops


static func deck_bottom(house: HouseData, top_y: float, is_lowest: bool) -> float:
	var bottom_y: float = top_y - house.interior_floor_thickness
	var foundation_base: float = house.foundation_base_y()
	if is_lowest and bottom_y < foundation_base and top_y > foundation_base:
		return foundation_base
	return bottom_y


static func _deck_side(
	accumulator: SurfaceAccumulator, house: HouseData,
	p: Vector2, q: Vector2, outward: Vector2, bottom_y: float, top_y: float
) -> void:
	var run: float = p.distance_to(q)
	if run < RUN_EPS:
		return
	accumulator.add_quad(
		SLOT_FLOOR, house.interior_floor_material,
		Vector3(p.x, bottom_y, p.y),
		Vector3(p.x, top_y, p.y),
		Vector3(q.x, top_y, q.y),
		Vector3(q.x, bottom_y, q.y),
		Vector3(outward.x, 0, outward.y),
		Vector2(0, top_y - bottom_y), Vector2(0, 0), Vector2(run, 0), Vector2(run, top_y - bottom_y),
		SurfaceAccumulator.Visibility.INTERIOR
	)


static func _build_baseboards(house: HouseData, floor_infos: Array[Dictionary], accumulator: SurfaceAccumulator) -> void:
	var height: float = house.interior_base_trim_height
	var depth: float = house.interior_base_trim_depth
	if height <= 0.0 or depth <= 0.0:
		return

	var half_thickness: float = house.wall_thickness * 0.5

	for info in floor_infos:
		var floor_data: FloorData = info["floor_data"]
		var deck_top: float = info["base_y"]
		var openings: Array[Dictionary] = info.get("openings", [] as Array[Dictionary])

		for loop in Footprint.trace_loops(floor_data.cells, house.level_cell_size):
			var n: int = loop.size()
			for i in range(n):
				var j: int = (i + 1) % n
				var start: Vector2 = loop.corner_offset(i, -half_thickness)
				var end: Vector2 = loop.corner_offset(j, -half_thickness)
				var run: float = start.distance_to(end)
				if run < RUN_EPS:
					continue
				var d: Vector2 = (end - start) / run
				var normal: Vector2 = loop.normals[i]

				var cuts: Array[Vector2] = _door_cuts(openings, loop.points[i], loop.points[j], normal, start, d, deck_top, house.interior_casing_width)
				cuts.append_array(_bay_cuts(floor_data, house.level_cell_size, loop.points[i], loop.points[j], normal, start, d))
				cuts.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
				for span in _open_spans(run, cuts):
					var s0: float = span[0] - (depth if span[0] <= RUN_EPS else 0.0)
					var s1: float = span[1] + (depth if span[1] >= run - RUN_EPS else 0.0)
					BoxBuilder.build(
						accumulator, SLOT_TRIM, house.interior_trim_material,
						start + d * s0, start + d * s1 - normal * depth,
						deck_top, deck_top + height,
						BoxBuilder.face_toward(normal) | BoxBuilder.Face.BOTTOM,
						ALL_FACES & ~(BoxBuilder.face_toward(normal) | BoxBuilder.Face.BOTTOM)
					)


static func _door_cuts(
	openings: Array[Dictionary], p_i: Vector2, p_j: Vector2, normal: Vector2,
	origin: Vector2, d: Vector2, deck_top: float, margin: float
) -> Array[Vector2]:
	var cuts: Array[Vector2] = []
	var edge_len: float = p_i.distance_to(p_j)
	if edge_len < RUN_EPS:
		return cuts
	var edge_dir: Vector2 = (p_j - p_i) / edge_len

	for op in openings:
		if not (op["normal"] as Vector2).is_equal_approx(normal):
			continue
		if op["bottom_y"] > deck_top + RUN_EPS:
			continue
		var mid: Vector2 = (op["a"] + op["b"]) * 0.5
		var t: float = (mid - p_i).dot(edge_dir)
		if t < -RUN_EPS or t > edge_len + RUN_EPS:
			continue
		if (mid - (p_i + edge_dir * t)).length() > RUN_EPS:
			continue
		var ta: float = (op["a"] - origin).dot(d)
		var tb: float = (op["b"] - origin).dot(d)
		cuts.append(Vector2(minf(ta, tb) - margin, maxf(ta, tb) + margin))

	cuts.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
	return cuts


static func _bay_cuts(
	floor_data: FloorData, cell_size: float, p_i: Vector2, p_j: Vector2, normal: Vector2,
	origin: Vector2, d: Vector2
) -> Array[Vector2]:
	var cuts: Array[Vector2] = []
	if floor_data.garage_cells.is_empty():
		return cuts

	var edge_len: float = p_i.distance_to(p_j)
	var steps: int = int(round(edge_len / cell_size))
	for k in range(steps):
		var probe: Vector2 = p_i + d * ((k + 0.5) * cell_size) - normal * (cell_size * 0.5)
		var owner := Vector2i(floori(probe.x / cell_size), floori(probe.y / cell_size))
		if not floor_data.garage_cells.has(owner):
			continue
		var t0: float = (p_i + d * (k * cell_size) - origin).dot(d)
		cuts.append(Vector2(t0, t0 + cell_size))
	return cuts


static func _open_spans(run: float, cuts: Array[Vector2]) -> Array[Vector2]:
	var spans: Array[Vector2] = []
	var cursor: float = 0.0
	for cut in cuts:
		if cut.x - cursor > RUN_EPS:
			spans.append(Vector2(cursor, minf(cut.x, run)))
		cursor = maxf(cursor, cut.y)
	if run - cursor > RUN_EPS:
		spans.append(Vector2(cursor, run))
	return spans
