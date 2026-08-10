@tool
class_name RoofGutters
extends RefCounted


enum Style { NONE, K_STYLE, HALF_ROUND }

const K_STYLE_SECTION: Array[Vector2] = [
	Vector2(0.00, 0.00),
	Vector2(0.00, 1.00),
	Vector2(0.30, 1.00),
	Vector2(0.44, 0.76),
	Vector2(0.56, 0.62),
	Vector2(0.60, 0.42),
	Vector2(0.82, 0.26),
	Vector2(1.00, 0.15),
	Vector2(0.88, 0.00),
]


static func build(
	model: RoofModel, input: RoofInput, wall_poly: PackedVector2Array,
	eave_poly: PackedVector2Array, segments: Array[Dictionary],
	eave_y: float, soffit_y: float
) -> void:
	if input.gutter_style == Style.NONE:
		return
	if input.gutter_width <= 0.0 or input.gutter_height <= 0.0:
		return

	var inner: PackedVector2Array = section(input.gutter_style, input.gutter_width, input.gutter_height)
	if inner.size() < 2:
		return
	var outer: PackedVector2Array = _shell_offset(inner, RoofConstants.GUTTER_THICKNESS)

	var inner_rings: Array[PackedVector2Array] = _offset_rings(eave_poly, inner)
	var outer_rings: Array[PackedVector2Array] = _offset_rings(eave_poly, outer)
	var arc: PackedFloat32Array = _arc_lengths(inner)

	var runs: Array[Dictionary] = _chain_runs(segments, eave_poly)
	for run in runs:
		_emit_run(model, input, eave_poly, inner, outer, inner_rings, outer_rings, arc, run, eave_y)

	if input.downspouts_enabled:
		_plan_downspouts(model, input, wall_poly, eave_poly, runs, eave_y, soffit_y)


static func section(style: Style, width: float, height: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	match style:
		Style.K_STYLE:
			for p in K_STYLE_SECTION:
				out.append(Vector2(p.x * width, p.y * height))
		Style.HALF_ROUND:
			var steps: int = RoofConstants.HALF_ROUND_SEGMENTS
			for i in range(steps + 1):
				var a: float = PI * float(i) / float(steps)
				out.append(Vector2(width * 0.5 * (1.0 - cos(a)), height * sin(a)))
	return out


static func _shell_offset(inner: PackedVector2Array, thickness: float) -> PackedVector2Array:
	var count: int = inner.size()
	var normals: Array[Vector2] = []
	for i in range(count - 1):
		var d: Vector2 = (inner[i + 1] - inner[i]).normalized()
		normals.append(Vector2(-d.y, d.x))

	var out := PackedVector2Array()
	for i in range(count):
		var n_in: Vector2 = normals[maxi(i - 1, 0)]
		var n_out: Vector2 = normals[mini(i, normals.size() - 1)]
		var denom: float = 1.0 + n_in.dot(n_out)
		var miter: Vector2 = n_out
		if denom >= RoofConstants.ANTIPARALLEL_DENOM_EPS:
			miter = (n_in + n_out) / denom
		out.append(inner[i] + miter * thickness)
	return out


static func _arc_lengths(profile: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var total: float = 0.0
	out.append(0.0)
	for i in range(1, profile.size()):
		total += profile[i].distance_to(profile[i - 1])
		out.append(total)
	return out


static func _offset_rings(eave_poly: PackedVector2Array, profile: PackedVector2Array) -> Array[PackedVector2Array]:
	var base: float = RoofConstants.GUTTER_FASCIA_GAP + RoofConstants.GUTTER_THICKNESS
	var out: Array[PackedVector2Array] = []
	for p in profile:
		out.append(RoofGenerator.miter_offset(eave_poly, base + p.x))
	return out


static func _chain_runs(segments: Array[Dictionary], eave_poly: PackedVector2Array) -> Array[Dictionary]:
	var n: int = eave_poly.size()
	var by_edge: Dictionary = {}
	for seg in segments:
		var i: int = seg["index"]
		var j: int = (i + 1) % n
		var p1: Vector2 = eave_poly[i]
		var p2: Vector2 = eave_poly[j]
		var edge_length: float = p1.distance_to(p2)
		if edge_length < RoofConstants.MIN_EDGE_LENGTH:
			continue
		var dir: Vector2 = (p2 - p1) / edge_length
		var ta: float = clampf((seg["a"] - p1).dot(dir) / edge_length, 0.0, 1.0)
		var tb: float = clampf((seg["b"] - p1).dot(dir) / edge_length, 0.0, 1.0)
		var length: float = (tb - ta) * edge_length
		if length < RoofConstants.GUTTER_MIN_RUN_LENGTH:
			continue
		if not by_edge.has(i):
			by_edge[i] = []
		by_edge[i].append({
			"index": i, "ta": ta, "tb": tb,
			"length": length, "edge_length": edge_length, "dir": dir,
		})

	var pieces: Array[Dictionary] = []
	for i in range(n):
		if not by_edge.has(i):
			continue
		var parts: Array = by_edge[i]
		parts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["ta"] < b["ta"])
		for part in parts:
			pieces.append(part)
	if pieces.is_empty():
		return []

	var count: int = pieces.size()
	var joins: Array[bool] = []
	for k in range(count):
		var cur: Dictionary = pieces[k]
		var nxt: Dictionary = pieces[(k + 1) % count]
		joins.append(
			is_equal_approx(cur["tb"], 1.0) and is_zero_approx(nxt["ta"])
			and int(nxt["index"]) == (int(cur["index"]) + 1) % n
		)

	var start: int = -1
	for k in range(count):
		if not joins[k]:
			start = (k + 1) % count
			break
	if start == -1:
		return [{"pieces": pieces, "closed": true}]

	var runs: Array[Dictionary] = []
	var current: Array[Dictionary] = []
	for step in range(count):
		var k: int = (start + step) % count
		current.append(pieces[k])
		if not joins[k]:
			runs.append({"pieces": current, "closed": false})
			current = []
	return runs


static func _emit_run(
	model: RoofModel, input: RoofInput, eave_poly: PackedVector2Array,
	inner: PackedVector2Array, outer: PackedVector2Array,
	inner_rings: Array[PackedVector2Array], outer_rings: Array[PackedVector2Array],
	arc: PackedFloat32Array, run: Dictionary, eave_y: float
) -> void:
	var pieces: Array = run["pieces"]
	var closed: bool = run["closed"]
	var last: int = pieces.size() - 1
	var count: int = inner.size()
	var thickness: float = RoofConstants.GUTTER_THICKNESS
	var s: float = 0.0

	for index in range(pieces.size()):
		var piece: Dictionary = pieces[index]
		var i: int = piece["index"]
		var j: int = (i + 1) % eave_poly.size()
		var length: float = piece["length"]
		var dir: Vector2 = piece["dir"]
		var outward := Vector2(dir.y, -dir.x)
		var along := Vector3(dir.x, 0.0, dir.y)

		var square_a: bool = not closed and index == 0
		var square_b: bool = not closed and index == last
		var ia: PackedVector3Array = _station(inner_rings, inner, eave_poly, i, j, piece["ta"], square_a, eave_y)
		var ib: PackedVector3Array = _station(inner_rings, inner, eave_poly, i, j, piece["tb"], square_b, eave_y)
		var oa: PackedVector3Array = _station(outer_rings, outer, eave_poly, i, j, piece["ta"], square_a, eave_y)
		var ob: PackedVector3Array = _station(outer_rings, outer, eave_poly, i, j, piece["tb"], square_b, eave_y)
		var s_end: float = s + length

		for k in range(count - 1):
			var facing: Vector3 = _lift(outward, _section_normal(inner, k))
			_quad(model, input, ia[k], ia[k + 1], ib[k + 1], ib[k], facing,
				Vector2(s, arc[k]), Vector2(s, arc[k + 1]),
				Vector2(s_end, arc[k + 1]), Vector2(s_end, arc[k]))
			_quad(model, input, oa[k], oa[k + 1], ob[k + 1], ob[k], -facing,
				Vector2(s, arc[k]), Vector2(s, arc[k + 1]),
				Vector2(s_end, arc[k + 1]), Vector2(s_end, arc[k]))

		for k in [0, count - 1]:
			_quad(model, input, ia[k], oa[k], ob[k], ib[k], Vector3.UP,
				Vector2(s, 0.0), Vector2(s, thickness),
				Vector2(s_end, thickness), Vector2(s_end, 0.0))

		if not closed and index == 0:
			_cap(model, input, ia, oa, arc, -along)
		if not closed and index == last:
			_cap(model, input, ib, ob, arc, along)

		s = s_end


static func _cap(
	model: RoofModel, input: RoofInput, inner_pts: PackedVector3Array,
	outer_pts: PackedVector3Array, arc: PackedFloat32Array, facing: Vector3
) -> void:
	var thickness: float = RoofConstants.GUTTER_THICKNESS
	for k in range(inner_pts.size() - 1):
		_quad(model, input, inner_pts[k], inner_pts[k + 1], outer_pts[k + 1], outer_pts[k], facing,
			Vector2(arc[k], 0.0), Vector2(arc[k + 1], 0.0),
			Vector2(arc[k + 1], thickness), Vector2(arc[k], thickness))


static func _station(
	rings: Array[PackedVector2Array], profile: PackedVector2Array,
	eave_poly: PackedVector2Array, i: int, j: int, t: float, square: bool, eave_y: float
) -> PackedVector3Array:
	var top: float = eave_y - RoofConstants.GUTTER_TOP_DROP
	var base: float = RoofConstants.GUTTER_FASCIA_GAP + RoofConstants.GUTTER_THICKNESS
	var anchor := Vector2.ZERO
	var normal := Vector2.ZERO
	if square:
		var dir: Vector2 = (eave_poly[j] - eave_poly[i]).normalized()
		normal = Vector2(dir.y, -dir.x)
		anchor = eave_poly[i].lerp(eave_poly[j], t)

	var out := PackedVector3Array()
	for k in range(profile.size()):
		var p: Vector2 = anchor + normal * (base + profile[k].x) if square else rings[k][i].lerp(rings[k][j], t)
		out.append(Vector3(p.x, top - profile[k].y, p.y))
	return out


static func _section_normal(profile: PackedVector2Array, k: int) -> Vector2:
	var d: Vector2 = (profile[k + 1] - profile[k]).normalized()
	return Vector2(d.y, -d.x)


static func _lift(outward: Vector2, n: Vector2) -> Vector3:
	return Vector3(outward.x * n.x, -n.y, outward.y * n.x)


static func _quad(
	model: RoofModel, input: RoofInput,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3,
	uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2
) -> void:
	var normal: Vector3 = (c - a).cross(d - b)
	if normal.length_squared() < RoofConstants.COINCIDENT_POINT_EPS:
		return
	normal = normal.normalized()
	if normal.dot(facing) < 0.0:
		normal = -normal

	var points := PackedVector3Array([a, b, c, d])
	var uvs := PackedVector2Array([uv_a, uv_b, uv_c, uv_d])
	if (c - a).cross(b - a).dot(normal) > 0.0:
		points = PackedVector3Array([a, d, c, b])
		uvs = PackedVector2Array([uv_a, uv_d, uv_c, uv_b])

	var plane := RoofModel.RoofPlane.new()
	plane.slot = input.slot_gutter
	plane.material = input.gutter_material
	plane.normal = normal
	plane.convex = true
	plane.points = points
	plane.uvs = uvs
	model.planes.append(plane)


const PRIORITY_OUTSIDE_CORNER := 0
const PRIORITY_INSIDE_CORNER := 1


static func _plan_downspouts(
	model: RoofModel, input: RoofInput, wall_poly: PackedVector2Array,
	eave_poly: PackedVector2Array, runs: Array[Dictionary], eave_y: float, soffit_y: float
) -> void:
	var walls: Array[PackedVector2Array] = input.downspout_walls
	if walls.is_empty():
		walls = [wall_poly]
	if input.downspout_width <= 0.0 or input.downspout_depth <= 0.0:
		return

	var grid: float = input.downspout_grid
	var separation: float = grid * RoofConstants.DOWNSPOUT_MIN_SPACING_CELLS if grid > 0.0 else RoofConstants.DOWNSPOUT_MERGE_DISTANCE
	if input.downspout_max_span > 0.0:
		separation = minf(separation, input.downspout_max_span * RoofConstants.DOWNSPOUT_SPAN_SPACING_FRACTION)

	var context := {
		"pieces": [], "eave_poly": eave_poly, "walls": walls, "total": 0.0, "closed": false,
		"grid": grid,
		"head_offset": RoofConstants.GUTTER_FASCIA_GAP + RoofConstants.GUTTER_THICKNESS + input.gutter_width * 0.5,
		"reach": input.overhang + input.gutter_width + RoofConstants.DOWNSPOUT_WALL_REACH_EPS,
		"step": grid if grid > 0.0 else RoofConstants.DOWNSPOUT_SEARCH_STEP,
		"search": grid * RoofConstants.DOWNSPOUT_GRID_SEARCH_CELLS if grid > 0.0 else input.overhang + input.gutter_width,
		"wall_step": RoofConstants.DOWNSPOUT_WALL_GAP + input.downspout_depth * 0.5,
		"top_y": eave_y - RoofConstants.GUTTER_TOP_DROP - input.gutter_height,
		"soffit_y": soffit_y,
		"separation": separation,
	}

	for run in runs:
		var pieces: Array = run["pieces"]
		var total: float = 0.0
		for piece in pieces:
			total += piece["length"]
		if total < RoofConstants.GUTTER_MIN_RUN_LENGTH:
			continue
		context["pieces"] = pieces
		context["total"] = total
		context["closed"] = run["closed"]

		var landed: Array[float] = []
		for anchor in _corner_anchors(pieces, total, run["closed"], input.overhang):
			var at: float = _place(model, context, anchor["s"])
			if not is_inf(at):
				landed.append(at)
		for s in _span_anchors(landed, total, run["closed"], input.downspout_max_span):
			_place(model, context, s)


static func _place(model: RoofModel, context: Dictionary, s: float) -> float:
	var spot: Dictionary = _resolve_anchor(context, s)
	if spot.is_empty():
		return INF

	var wall_point: Vector2 = spot["wall"] + spot["outward"] * context["wall_step"]
	for other in model.downspouts:
		if other.wall.distance_to(wall_point) < context["separation"]:
			return INF

	var spout := RoofModel.Downspout.new()
	spout.head = spot["head"]
	spout.wall = wall_point
	spout.outward = spot["outward"]
	spout.top_y = context["top_y"]
	spout.soffit_y = context["soffit_y"]
	model.downspouts.append(spout)
	return spot["s"]


static func _corner_anchors(pieces: Array, total: float, closed: bool, overhang: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var count: int = pieces.size()
	if not closed:
		out.append({"s": overhang, "priority": PRIORITY_OUTSIDE_CORNER})
		out.append({"s": total - overhang, "priority": PRIORITY_OUTSIDE_CORNER})

	var acc: float = 0.0
	for index in range(count):
		acc += pieces[index]["length"]
		if not closed and index == count - 1:
			continue
		var here: Vector2 = pieces[index]["dir"]
		var onward: Vector2 = pieces[(index + 1) % count]["dir"]
		var convex: bool = here.cross(onward) > 0.0
		var at: float = acc - overhang if convex else acc + overhang
		out.append({
			"s": fposmod(at, total) if closed else clampf(at, 0.0, total),
			"priority": PRIORITY_OUTSIDE_CORNER if convex else PRIORITY_INSIDE_CORNER,
		})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["priority"] != b["priority"]:
			return a["priority"] < b["priority"]
		return a["s"] < b["s"])
	return out


static func _span_anchors(landed: Array[float], total: float, closed: bool, max_span: float) -> Array[float]:
	var out: Array[float] = []
	if max_span <= 0.0:
		return out

	var sorted: Array[float] = landed.duplicate()
	sorted.sort()
	var gaps: Array[Vector2] = []
	if sorted.is_empty():
		gaps.append(Vector2(0.0, total))
	else:
		for k in range(sorted.size() - 1):
			gaps.append(Vector2(sorted[k], sorted[k + 1]))
		if closed:
			gaps.append(Vector2(sorted[sorted.size() - 1], sorted[0] + total))
		else:
			gaps.append(Vector2(0.0, sorted[0]))
			gaps.append(Vector2(sorted[sorted.size() - 1], total))

	for gap in gaps:
		var span: float = gap.y - gap.x
		if span <= max_span:
			continue
		var extra: int = int(ceil(span / max_span)) - 1
		for m in range(1, extra + 1):
			out.append(fposmod(gap.x + span * float(m) / float(extra + 1), total))
	return out


static func _resolve_anchor(context: Dictionary, s: float) -> Dictionary:
	var pieces: Array = context["pieces"]
	var eave_poly: PackedVector2Array = context["eave_poly"]
	var walls: Array[PackedVector2Array] = context["walls"]
	var total: float = context["total"]
	var closed: bool = context["closed"]
	var grid: float = context["grid"]
	var step: float = context["step"]

	var steps: int = int(ceil(context["search"] / step)) if step > 0.0 else 0
	for i in range(steps + 1):
		var directions: Array[float] = [1.0, -1.0]
		if i == 0:
			directions = [0.0]
		for direction in directions:
			var at: float = s + direction * step * float(i)
			var spot: Dictionary = _at_run(pieces, eave_poly, at, total, closed)
			if spot.is_empty():
				continue
			if grid > 0.0:
				at += _grid_delta(spot["point"], spot["dir"], grid)
				spot = _at_run(pieces, eave_poly, at, total, closed)
				if spot.is_empty():
					continue
				if absf(_grid_delta(spot["point"], spot["dir"], grid)) > RoofConstants.FACE_WELD_EPS:
					continue
			var outward: Vector2 = spot["outward"]
			var head: Vector2 = spot["point"] + outward * context["head_offset"]
			var hit: Dictionary = _cast_to_wall(head, outward, walls, context["reach"])
			if hit["hit"]:
				return {"s": at, "head": head, "wall": hit["point"], "outward": outward}
	return {}


static func _grid_delta(point: Vector2, dir: Vector2, grid: float) -> float:
	var along: float = point.dot(dir)
	return round(along / grid) * grid - along


static func _at_run(
	pieces: Array, eave_poly: PackedVector2Array, at: float, total: float, closed: bool
) -> Dictionary:
	if closed:
		return _at_arc(pieces, eave_poly, fposmod(at, total))
	if at < 0.0 or at > total:
		return {}
	return _at_arc(pieces, eave_poly, at)


static func _at_arc(pieces: Array, eave_poly: PackedVector2Array, s: float) -> Dictionary:
	var acc: float = 0.0
	for index in range(pieces.size()):
		var piece: Dictionary = pieces[index]
		var length: float = piece["length"]
		if s <= acc + length or index == pieces.size() - 1:
			var i: int = piece["index"]
			var j: int = (i + 1) % eave_poly.size()
			var t: float = piece["ta"] + clampf(s - acc, 0.0, length) / piece["edge_length"]
			var dir: Vector2 = piece["dir"]
			return {
				"point": eave_poly[i].lerp(eave_poly[j], clampf(t, 0.0, 1.0)),
				"dir": dir,
				"outward": Vector2(dir.y, -dir.x),
			}
		acc += length
	return {}


static func _cast_to_wall(
	head: Vector2, outward: Vector2, walls: Array[PackedVector2Array], reach: float
) -> Dictionary:
	var tail: Vector2 = head - outward * reach
	var slack: float = RoofConstants.DOWNSPOUT_WALL_EDGE_SLACK
	var best: float = INF
	var found := Vector2.ZERO
	for poly in walls:
		for k in range(poly.size()):
			var a: Vector2 = poly[k]
			var b: Vector2 = poly[(k + 1) % poly.size()]
			var along: Vector2 = (b - a).normalized() * slack
			var hit = Geometry2D.segment_intersects_segment(head, tail, a - along, b + along)
			if hit == null:
				continue
			var distance: float = head.distance_to(hit)
			if distance < best:
				best = distance
				found = hit
	return {"hit": best < INF, "point": found}
