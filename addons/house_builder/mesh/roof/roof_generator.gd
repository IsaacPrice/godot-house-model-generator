@tool
class_name RoofGenerator
extends RefCounted


static func generate(input: RoofInput) -> RoofModel:
	var model := RoofModel.new()

	var wall_poly: PackedVector2Array = _sanitize(input.polygon)
	if wall_poly.size() < 3:
		return model

	var eave_poly: PackedVector2Array = _offset_outward(wall_poly, input.overhang)
	var has_overhang: bool = input.overhang > 0.0 and eave_poly != wall_poly
	var drop_run: float = maxf(0.0, input.overhang - input.wall_clearance) if has_overhang else 0.0

	var clips: Array[PackedVector2Array] = []
	for region in input.clip_regions:
		var clean: PackedVector2Array = _sanitize(region)
		if clean.size() >= 3:
			clips.append(clean)
	var keeps: Array[PackedVector2Array] = _compute_keep_regions(wall_poly, clips, input)
	if not clips.is_empty() and keeps.is_empty():
		return model

	var flat: bool = input.pitch_degrees < RoofConstants.FLAT_PITCH_DEGREES
	var pitch_rad: float = deg_to_rad(clampf(input.pitch_degrees, 0.0, RoofConstants.MAX_PITCH_DEGREES))
	var tan_pitch: float = 0.0 if flat else tan(pitch_rad)
	var eave_y: float = input.base_y - drop_run * tan_pitch

	var gable_indices: Array[int] = _resolve_gable_edges(wall_poly, input.gable_walls)
	var gable_ends: Array[Dictionary] = []

	if flat:
		if not gable_indices.is_empty():
			push_warning("RoofGenerator: gable walls ignored on a flat roof.")
		_build_flat_cap(model, input, eave_poly, keeps, clips)
	else:
		var skeleton: StraightSkeleton.Result = null
		var skeleton_ok := false
		while true:
			skeleton = StraightSkeleton.compute(eave_poly, _edge_weights(eave_poly.size(), gable_indices))
			skeleton_ok = skeleton.completed and _areas_conserved(eave_poly, skeleton.faces)
			if not skeleton_ok:
				if gable_indices.is_empty():
					break
				push_error("RoofGenerator: straight skeleton failed with gable walls - rebuilding them as hips.")
				gable_indices = []
				continue
			var extraction: Dictionary = _extract_gable_ends(skeleton.faces, eave_poly, wall_poly, gable_indices)
			gable_ends = extraction["ends"]
			var failed: Array[int] = extraction["failed"]
			if failed.is_empty():
				break
			gable_indices.erase(failed[0])

		if skeleton_ok:
			_build_pitched_planes(model, input, eave_poly, skeleton.faces, pitch_rad, drop_run, keeps, clips)
			_build_gable_ends(model, input, gable_ends, eave_poly, tan_pitch, drop_run, eave_y, has_overhang, keeps, clips)
			_classify_edges(model, input, eave_poly, skeleton.faces, tan_pitch, drop_run, keeps, clips, gable_ends)
		else:
			push_warning("RoofGenerator: straight skeleton unreliable for this footprint - falling back to a flat cap.")
			model.used_fallback = true
			_build_flat_cap(model, input, eave_poly, keeps, clips)

	var eave_segments: Array[Dictionary] = _eave_segments(eave_poly, keeps, clips, gable_ends)
	for seg in eave_segments:
		var edge := RoofModel.RoofEdge.new()
		edge.type = RoofModel.EdgeType.EAVE
		edge.a = Vector3(seg["a"].x, eave_y, seg["a"].y)
		edge.b = Vector3(seg["b"].x, eave_y, seg["b"].y)
		model.edges.append(edge)

	_build_fascia(model, input, eave_poly, eave_segments, eave_y)
	_build_soffit(model, input, eave_poly, eave_segments, keeps, clips, has_overhang, eave_y)
	RoofGutters.build(model, input, wall_poly, eave_poly, eave_segments, eave_y, eave_y - input.fascia_height)
	return model


static func _sanitize(polygon: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in polygon:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > RoofConstants.FACE_WELD_EPS:
			pts.append(p)
	while pts.size() > 1 and pts[0].distance_to(pts[pts.size() - 1]) <= RoofConstants.FACE_WELD_EPS:
		pts.remove_at(pts.size() - 1)
	if pts.size() < 3:
		return PackedVector2Array()

	var area: float = _signed_area(pts)
	if absf(area) < RoofConstants.MIN_POLYGON_AREA:
		return PackedVector2Array()
	if area < 0.0:
		pts.reverse()
	return pts


static func _offset_outward(polygon: PackedVector2Array, distance: float) -> PackedVector2Array:
	if distance <= 0.0:
		return polygon

	var out: PackedVector2Array = miter_offset(polygon, distance)

	if absf(_signed_area(out)) <= absf(_signed_area(polygon)):
		push_warning("RoofGenerator: overhang offset degenerated the eave outline - building this roof without overhang.")
		return polygon
	return out


static func miter_offset(polygon: PackedVector2Array, distance: float) -> PackedVector2Array:
	var n: int = polygon.size()
	var normals: Array[Vector2] = []
	for i in range(n):
		var dir: Vector2 = (polygon[(i + 1) % n] - polygon[i]).normalized()
		normals.append(Vector2(dir.y, -dir.x))

	var out := PackedVector2Array()
	for i in range(n):
		var n_in: Vector2 = normals[(i - 1 + n) % n]
		var n_out: Vector2 = normals[i]
		var denom: float = 1.0 + n_in.dot(n_out)
		var miter: Vector2
		if denom < RoofConstants.ANTIPARALLEL_DENOM_EPS:
			miter = n_out
		else:
			miter = (n_in + n_out) / denom
		out.append(polygon[i] + miter * distance)
	return out


static func _compute_keep_regions(
	wall_poly: PackedVector2Array, clips: Array[PackedVector2Array], input: RoofInput
) -> Array[PackedVector2Array]:
	var keeps: Array[PackedVector2Array] = []
	if clips.is_empty():
		return keeps

	var exposed: Array[PackedVector2Array] = [wall_poly]
	for clip in clips:
		var next: Array[PackedVector2Array] = []
		for piece in exposed:
			next.append_array(_subtract_hole_safe(piece, clip, 0))
		exposed = next

	var expand: float = input.overhang + input.clip_keep_margin
	for piece in exposed:
		if piece.size() < 3 or absf(_signed_area(piece)) < RoofConstants.MIN_FACE_AREA:
			continue
		keeps.append_array(Geometry2D.offset_polygon(piece, expand, Geometry2D.JOIN_MITER))
	return keeps


static func _clip_plan_polygon(
	polygon: PackedVector2Array, keeps: Array[PackedVector2Array], clips: Array[PackedVector2Array]
) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = []
	if keeps.is_empty():
		pieces.append(polygon)
	else:
		var remaining: Array[PackedVector2Array] = [polygon]
		for keep in keeps:
			var next_remaining: Array[PackedVector2Array] = []
			for r in remaining:
				pieces.append_array(Geometry2D.intersect_polygons(r, keep))
				next_remaining.append_array(_subtract_hole_safe(r, keep, 0))
			remaining = next_remaining

	for clip in clips:
		var next_pieces: Array[PackedVector2Array] = []
		for piece in pieces:
			next_pieces.append_array(_subtract_hole_safe(piece, clip, 0))
		pieces = next_pieces

	var out: Array[PackedVector2Array] = []
	for piece in pieces:
		if piece.size() >= 3 and absf(_signed_area(piece)) >= RoofConstants.MIN_FACE_AREA:
			out.append(piece)
	return out


static func _subtract_hole_safe(
	subject: PackedVector2Array, clip: PackedVector2Array, depth: int
) -> Array[PackedVector2Array]:
	var results: Array[PackedVector2Array] = Geometry2D.clip_polygons(subject, clip)
	var has_hole := false
	for i in range(results.size()):
		if has_hole:
			break
		for j in range(results.size()):
			if i != j and results[i].size() > 0 and Geometry2D.is_point_in_polygon(results[i][0], results[j]):
				has_hole = true
				break
	if not has_hole or depth >= RoofConstants.MAX_HOLE_SPLIT_DEPTH:
		return results

	var centroid := Vector2.ZERO
	for p in clip:
		centroid += p
	centroid /= float(clip.size())

	var lo := subject[0]
	var hi := subject[0]
	for p in subject:
		lo = lo.min(p)
		hi = hi.max(p)
	lo -= Vector2.ONE * RoofConstants.CLIP_SPLIT_PADDING
	hi += Vector2.ONE * RoofConstants.CLIP_SPLIT_PADDING

	var out: Array[PackedVector2Array] = []
	for half in [
		PackedVector2Array([lo, Vector2(centroid.x, lo.y), Vector2(centroid.x, hi.y), Vector2(lo.x, hi.y)]),
		PackedVector2Array([Vector2(centroid.x, lo.y), Vector2(hi.x, lo.y), hi, Vector2(centroid.x, hi.y)]),
	]:
		for piece in Geometry2D.intersect_polygons(subject, half):
			out.append_array(_subtract_hole_safe(piece, clip, depth + 1))
	return out


static func _clip_plan_segment(
	a: Vector2, b: Vector2, keeps: Array[PackedVector2Array], clips: Array[PackedVector2Array]
) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = []
	var seed := PackedVector2Array([a, b])
	if keeps.is_empty():
		parts.append(seed)
	else:
		var remaining: Array[PackedVector2Array] = [seed]
		for keep in keeps:
			var next_remaining: Array[PackedVector2Array] = []
			for r in remaining:
				parts.append_array(Geometry2D.intersect_polyline_with_polygon(r, keep))
				next_remaining.append_array(Geometry2D.clip_polyline_with_polygon(r, keep))
			remaining = next_remaining

	for clip in clips:
		var next: Array[PackedVector2Array] = []
		for part in parts:
			next.append_array(Geometry2D.clip_polyline_with_polygon(part, clip))
		parts = next

	var out: Array[PackedVector2Array] = []
	for part in parts:
		for i in range(part.size() - 1):
			if part[i].distance_to(part[i + 1]) >= RoofConstants.MIN_EDGE_LENGTH:
				out.append(PackedVector2Array([part[i], part[i + 1]]))
	return out


static func _resolve_gable_edges(wall_poly: PackedVector2Array, segments: Array[PackedVector2Array]) -> Array[int]:
	var out: Array[int] = []
	for seg in segments:
		if seg.size() < 2:
			push_error("RoofGenerator: invalid gable wall - a segment needs 2 points, got %d." % seg.size())
			continue
		var index: int = match_wall_edge(wall_poly, seg[0], seg[1])
		if index == -1:
			push_error("RoofGenerator: invalid gable wall - segment %s - %s lies on no edge of the roof footprint." % [seg[0], seg[1]])
		elif not out.has(index):
			out.append(index)
	return out


static func match_wall_edge(polygon: PackedVector2Array, a: Vector2, b: Vector2) -> int:
	var n: int = polygon.size()
	for i in range(n):
		var p1: Vector2 = polygon[i]
		var p2: Vector2 = polygon[(i + 1) % n]
		var length: float = p1.distance_to(p2)
		if length < RoofConstants.MIN_EDGE_LENGTH:
			continue
		var dir: Vector2 = (p2 - p1) / length
		var normal := Vector2(dir.y, -dir.x)
		var line_const: float = p1.dot(normal)
		if absf(a.dot(normal) - line_const) > RoofConstants.GABLE_MATCH_EPS:
			continue
		if absf(b.dot(normal) - line_const) > RoofConstants.GABLE_MATCH_EPS:
			continue
		var ta: float = (a - p1).dot(dir)
		var tb: float = (b - p1).dot(dir)
		if minf(ta, tb) < -RoofConstants.GABLE_MATCH_EPS or maxf(ta, tb) > length + RoofConstants.GABLE_MATCH_EPS:
			continue
		return i
	return -1


static func _edge_weights(count: int, gable_indices: Array[int]) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	if gable_indices.is_empty():
		return weights
	weights.resize(count)
	weights.fill(1.0)
	for gi in gable_indices:
		weights[gi] = 0.0
	return weights


static func _extract_gable_ends(
	faces: Array[StraightSkeleton.Face], eave_poly: PackedVector2Array,
	wall_poly: PackedVector2Array, gable_indices: Array[int]
) -> Dictionary:
	var ends: Array[Dictionary] = []
	var failed: Array[int] = []
	var n: int = eave_poly.size()
	for gi in gable_indices:
		var a: Vector2 = eave_poly[gi]
		var b: Vector2 = eave_poly[(gi + 1) % n]
		var length: float = a.distance_to(b)
		var dir: Vector2 = (b - a) / length
		var normal := Vector2(dir.y, -dir.x)
		var line_const: float = a.dot(normal)
		var where: String = "wall %s - %s" % [a, b]

		var runs: Array[Dictionary] = []
		for face in faces:
			if face.edge_index == gi:
				continue
			runs.append_array(_face_runs_on_line(face, normal, line_const, a, dir, length))

		if runs.size() != 2:
			push_error("RoofGenerator: %s cannot be gabled - %d roof plane(s) border the wall where a gable needs exactly 2 (is an adjoining wall already gabled?)." % [where, runs.size()])
			failed.append(gi)
			continue
		runs.sort_custom(func(r1, r2): return r1["t0"] < r2["t0"])
		var lo: Dictionary = runs[0]
		var hi: Dictionary = runs[1]
		if absf(lo["t0"]) > RoofConstants.GABLE_LINE_EPS or absf(hi["t1"] - length) > RoofConstants.GABLE_LINE_EPS \
				or absf(lo["t1"] - hi["t0"]) > RoofConstants.GABLE_LINE_EPS:
			push_error("RoofGenerator: %s cannot be gabled - the adjoining roof planes do not span it corner to corner." % where)
			failed.append(gi)
			continue
		if absf(lo["o1"] - hi["o0"]) > RoofConstants.GABLE_APEX_OFFSET_EPS:
			push_error("RoofGenerator: %s cannot be gabled - the adjacent roof planes would meet it at different heights." % where)
			failed.append(gi)
			continue

		var apex_t: float = (lo["t1"] + hi["t0"]) * 0.5
		ends.append({
			"edge_index": gi, "a": a, "b": b, "dir": dir, "length": length,
			"normal": normal, "line_const": line_const,
			"wa": wall_poly[gi], "wb": wall_poly[(gi + 1) % n],
			"edge_a": lo["edge_index"], "edge_b": hi["edge_index"],
			"apex": a + dir * apex_t, "apex_offset": (lo["o1"] + hi["o0"]) * 0.5,
		})
	return {"ends": ends, "failed": failed}


static func _face_runs_on_line(
	face: StraightSkeleton.Face, normal: Vector2, line_const: float,
	a: Vector2, dir: Vector2, length: float
) -> Array[Dictionary]:
	var count: int = face.points.size()
	var on_line: Array[bool] = []
	var all_on := true
	for p in face.points:
		var hit: bool = absf(p.dot(normal) - line_const) <= RoofConstants.GABLE_LINE_EPS
		on_line.append(hit)
		all_on = all_on and hit
	if all_on:
		return []

	var out: Array[Dictionary] = []
	for i in range(count):
		if not on_line[i] or on_line[(i - 1 + count) % count]:
			continue
		var t0: float = (face.points[i] - a).dot(dir)
		var t1: float = t0
		var i0: int = i
		var i1: int = i
		var j: int = i
		while on_line[(j + 1) % count]:
			j = (j + 1) % count
			var t: float = (face.points[j] - a).dot(dir)
			if t < t0:
				t0 = t
				i0 = j
			if t > t1:
				t1 = t
				i1 = j
		if t1 - t0 < RoofConstants.MIN_EDGE_LENGTH:
			continue
		if t1 < RoofConstants.GABLE_LINE_EPS or t0 > length - RoofConstants.GABLE_LINE_EPS:
			continue
		out.append({
			"t0": t0, "t1": t1,
			"o0": face.offsets[i0], "o1": face.offsets[i1],
			"edge_index": face.edge_index,
		})
	return out


static func _edge_offset(eave_poly: PackedVector2Array, edge_index: int, point: Vector2) -> float:
	var p1: Vector2 = eave_poly[edge_index]
	var p2: Vector2 = eave_poly[(edge_index + 1) % eave_poly.size()]
	var dir: Vector2 = (p2 - p1).normalized()
	var normal := Vector2(dir.y, -dir.x)
	return p1.dot(normal) - point.dot(normal)


static func _on_gable_line(a: Vector2, b: Vector2, gable_ends: Array[Dictionary]) -> bool:
	for gable in gable_ends:
		var normal: Vector2 = gable["normal"]
		var line_const: float = gable["line_const"]
		if absf(a.dot(normal) - line_const) >= RoofConstants.GABLE_LINE_EPS:
			continue
		if absf(b.dot(normal) - line_const) >= RoofConstants.GABLE_LINE_EPS:
			continue
		var origin: Vector2 = gable["a"]
		var dir: Vector2 = gable["dir"]
		var ta: float = (a - origin).dot(dir)
		var tb: float = (b - origin).dot(dir)
		if minf(ta, tb) > -RoofConstants.GABLE_LINE_EPS and maxf(ta, tb) < gable["length"] + RoofConstants.GABLE_LINE_EPS:
			return true
	return false


static func _build_gable_ends(
	model: RoofModel, input: RoofInput, gable_ends: Array[Dictionary], eave_poly: PackedVector2Array,
	tan_pitch: float, drop_run: float, eave_y: float, has_overhang: bool,
	keeps: Array[PackedVector2Array], clips: Array[PackedVector2Array]
) -> void:
	for gable in gable_ends:
		var apex_y: float = input.base_y + (gable["apex_offset"] - drop_run) * tan_pitch
		if apex_y <= eave_y + RoofConstants.GABLE_LINE_EPS:
			continue
		_build_gable_wall(model, input, gable, eave_poly, tan_pitch, drop_run, keeps, clips)
		if not has_overhang:
			continue

		var a: Vector2 = gable["a"]
		var dir: Vector2 = gable["dir"]
		var apex_t: float = (gable["apex"] - a).dot(dir)
		var sides: Array[Dictionary] = [
			{"t0": 0.0, "y0": eave_y, "t1": apex_t, "y1": apex_y},
			{"t0": apex_t, "y0": apex_y, "t1": gable["length"], "y1": eave_y},
		]
		for side in sides:
			if side["t1"] - side["t0"] < RoofConstants.MIN_EDGE_LENGTH:
				continue
			_build_rake_board(model, input, gable, side, keeps, clips)
			_build_rake_soffit(model, input, gable, side, keeps, clips)


static func _build_gable_wall(
	model: RoofModel, input: RoofInput, gable: Dictionary, eave_poly: PackedVector2Array,
	tan_pitch: float, drop_run: float,
	keeps: Array[PackedVector2Array], clips: Array[PackedVector2Array]
) -> void:
	var wa: Vector2 = gable["wa"]
	var wb: Vector2 = gable["wb"]
	var dir: Vector2 = gable["dir"]
	var wall_len: float = wa.distance_to(wb)
	if wall_len < RoofConstants.MIN_EDGE_LENGTH:
		return
	var apex_t: float = (gable["apex"] - wa).dot(dir)
	var apex_w: Vector2 = wa + dir * apex_t
	var h_wa: float = _plane_height(eave_poly, gable["edge_a"], wa, input, drop_run, tan_pitch)
	var h_wb: float = _plane_height(eave_poly, gable["edge_b"], wb, input, drop_run, tan_pitch)
	var h_apex: float = 0.5 * (
		_plane_height(eave_poly, gable["edge_a"], apex_w, input, drop_run, tan_pitch)
		+ _plane_height(eave_poly, gable["edge_b"], apex_w, input, drop_run, tan_pitch))
	if h_apex <= input.base_y + RoofConstants.GABLE_LINE_EPS:
		return

	var outline := PackedVector2Array([Vector2(0, input.base_y)])
	if h_wa > input.base_y + RoofConstants.FACE_WELD_EPS:
		outline.append(Vector2(0, h_wa))
	outline.append(Vector2(apex_t, h_apex))
	if h_wb > input.base_y + RoofConstants.FACE_WELD_EPS:
		outline.append(Vector2(wall_len, h_wb))
	outline.append(Vector2(wall_len, input.base_y))

	for part in _clip_plan_segment(wa, wb, keeps, clips):
		var t0: float = minf((part[0] - wa).dot(dir), (part[1] - wa).dot(dir))
		var t1: float = maxf((part[0] - wa).dot(dir), (part[1] - wa).dot(dir))
		var strip := PackedVector2Array([
			Vector2(t0, input.base_y - 1.0), Vector2(t1, input.base_y - 1.0),
			Vector2(t1, h_apex + 1.0), Vector2(t0, h_apex + 1.0),
		])
		for piece in Geometry2D.intersect_polygons(outline, strip):
			var uvs := PackedVector2Array()
			for pt in piece:
				uvs.append(Vector2(pt.x, input.base_y - pt.y))
			_add_vertical_plane(model, input.slot_gable, input.gable_material, wa, dir, gable["normal"], piece, uvs)


static func _build_rake_board(
	model: RoofModel, input: RoofInput, gable: Dictionary, side: Dictionary,
	keeps: Array[PackedVector2Array], clips: Array[PackedVector2Array]
) -> void:
	if input.fascia_height <= 0.0:
		return
	var a: Vector2 = gable["a"]
	var dir: Vector2 = gable["dir"]
	var run: float = side["t1"] - side["t0"]
	var slope_scale: float = Vector2(run, side["y1"] - side["y0"]).length() / run
	var p0: Vector2 = a + dir * side["t0"]
	var p1: Vector2 = a + dir * side["t1"]

	for part in _clip_plan_segment(p0, p1, keeps, clips):
		var t0: float = minf((part[0] - a).dot(dir), (part[1] - a).dot(dir))
		var t1: float = maxf((part[0] - a).dot(dir), (part[1] - a).dot(dir))
		var y0: float = lerpf(side["y0"], side["y1"], (t0 - side["t0"]) / run)
		var y1: float = lerpf(side["y0"], side["y1"], (t1 - side["t0"]) / run)
		var u0: float = (t0 - side["t0"]) * slope_scale
		var u1: float = (t1 - side["t0"]) * slope_scale
		_add_vertical_plane(
			model, input.slot_fascia, input.fascia_material, a, dir, gable["normal"],
			PackedVector2Array([
				Vector2(t0, y0 - input.fascia_height), Vector2(t0, y0),
				Vector2(t1, y1), Vector2(t1, y1 - input.fascia_height),
			]),
			PackedVector2Array([
				Vector2(u0, input.fascia_height), Vector2(u0, 0),
				Vector2(u1, 0), Vector2(u1, input.fascia_height),
			]))


static func _build_rake_soffit(
	model: RoofModel, input: RoofInput, gable: Dictionary, side: Dictionary,
	keeps: Array[PackedVector2Array], clips: Array[PackedVector2Array]
) -> void:
	var a: Vector2 = gable["a"]
	var dir: Vector2 = gable["dir"]
	var normal: Vector2 = gable["normal"]
	var run: float = side["t1"] - side["t0"]
	var slope_scale: float = Vector2(run, side["y1"] - side["y0"]).length() / run
	var width: float = input.overhang + input.soffit_overlap
	var soffit_drop: float = input.fascia_height
	var p0: Vector2 = a + dir * side["t0"]
	var p1: Vector2 = a + dir * side["t1"]
	var quad := PackedVector2Array([p0, p1, p1 - normal * width, p0 - normal * width])

	var rise: float = (side["y1"] - side["y0"]) / run
	var along := Vector3(dir.x, rise, dir.y)
	var plane_normal: Vector3 = along.cross(Vector3(-normal.x, 0, -normal.y)).normalized()
	if plane_normal.y > 0.0:
		plane_normal = -plane_normal

	for piece in _clip_plan_polygon(quad, keeps, clips):
		var points := PackedVector3Array()
		var uvs := PackedVector2Array()
		for pt in piece:
			var t: float = clampf((pt - a).dot(dir), side["t0"], side["t1"])
			var y: float = lerpf(side["y0"], side["y1"], (t - side["t0"]) / run) - soffit_drop
			points.append(Vector3(pt.x, y, pt.y))
			uvs.append(Vector2((t - side["t0"]) * slope_scale, gable["line_const"] - pt.dot(normal)))
		_add_plane(model, input.slot_underlayment, input.underlayment_material, points, uvs, plane_normal, false)


static func _add_vertical_plane(
	model: RoofModel, slot: String, material: Material,
	origin: Vector2, dir: Vector2, normal: Vector2,
	pts_ty: PackedVector2Array, uvs: PackedVector2Array
) -> void:
	if pts_ty.size() < 3 or absf(_signed_area(pts_ty)) < RoofConstants.MIN_FACE_AREA:
		return
	if _signed_area(pts_ty) > 0.0:
		pts_ty = pts_ty.duplicate()
		pts_ty.reverse()
		uvs = uvs.duplicate()
		uvs.reverse()
	var points := PackedVector3Array()
	for pt in pts_ty:
		var pos: Vector2 = origin + dir * pt.x
		points.append(Vector3(pos.x, pt.y, pos.y))
	_add_plane(model, slot, material, points, uvs, Vector3(normal.x, 0, normal.y), true)


static func _add_plane(
	model: RoofModel, slot: String, material: Material,
	points: PackedVector3Array, uvs: PackedVector2Array, normal: Vector3, convex: bool
) -> void:
	if points.size() < 3:
		return
	var newell := Vector3.ZERO
	for i in range(points.size()):
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[(i + 1) % points.size()]
		newell += Vector3(
			(p1.y - p2.y) * (p1.z + p2.z),
			(p1.z - p2.z) * (p1.x + p2.x),
			(p1.x - p2.x) * (p1.y + p2.y))
	if newell.length_squared() < RoofConstants.MIN_FACE_AREA * RoofConstants.MIN_FACE_AREA:
		return
	if newell.dot(normal) < 0.0:
		points = points.duplicate()
		points.reverse()
		uvs = uvs.duplicate()
		uvs.reverse()
	var plane := RoofModel.RoofPlane.new()
	plane.slot = slot
	plane.material = material
	plane.normal = normal
	plane.convex = convex
	plane.points = points
	plane.uvs = uvs
	model.planes.append(plane)


static func _plane_height(
	eave_poly: PackedVector2Array, edge_index: int, p: Vector2,
	input: RoofInput, drop_run: float, tan_pitch: float
) -> float:
	return input.base_y + (_edge_offset(eave_poly, edge_index, p) - drop_run) * tan_pitch


static func _build_pitched_planes(
	model: RoofModel, input: RoofInput, eave_poly: PackedVector2Array,
	faces: Array[StraightSkeleton.Face], pitch_rad: float, drop_run: float,
	keeps: Array[PackedVector2Array], clips: Array[PackedVector2Array]
) -> void:
	var n: int = eave_poly.size()
	var tan_pitch: float = tan(pitch_rad)
	var sin_pitch: float = sin(pitch_rad)
	var cos_pitch: float = cos(pitch_rad)

	for face in faces:
		if face.points.size() < 3 or absf(_signed_area(face.points)) < RoofConstants.MIN_FACE_AREA:
			continue

		var p1: Vector2 = eave_poly[face.edge_index]
		var p2: Vector2 = eave_poly[(face.edge_index + 1) % n]
		var edge_dir: Vector2 = (p2 - p1).normalized()
		var normal2 := Vector2(edge_dir.y, -edge_dir.x)
		var line_const: float = p1.dot(normal2)

		for piece in _clip_plan_polygon(face.points, keeps, clips):
			if _signed_area(piece) > 0.0:
				piece.reverse()

			var plane := RoofModel.RoofPlane.new()
			plane.slot = input.slot_shingles
			plane.material = input.shingles_material
			plane.normal = Vector3(normal2.x, 0, normal2.y) * sin_pitch + Vector3.UP * cos_pitch
			plane.convex = false
			for pt in piece:
				var offset: float = line_const - pt.dot(normal2)
				plane.points.append(Vector3(pt.x, input.base_y + (offset - drop_run) * tan_pitch, pt.y))
				plane.uvs.append(Vector2((pt - p1).dot(edge_dir), offset / cos_pitch) * input.uv_scale)
			model.planes.append(plane)


static func _build_flat_cap(
	model: RoofModel, input: RoofInput, eave_poly: PackedVector2Array,
	keeps: Array[PackedVector2Array], clips: Array[PackedVector2Array]
) -> void:
	for piece in _clip_plan_polygon(eave_poly, keeps, clips):
		if _signed_area(piece) < 0.0:
			piece.reverse()
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(piece)
		for i in range(0, indices.size(), 3):
			var a: Vector2 = piece[indices[i]]
			var b: Vector2 = piece[indices[i + 1]]
			var c: Vector2 = piece[indices[i + 2]]
			var plane := RoofModel.RoofPlane.new()
			plane.slot = input.slot_shingles
			plane.material = input.shingles_material
			plane.normal = Vector3.UP
			plane.convex = true
			plane.points = PackedVector3Array([
				Vector3(b.x, input.base_y, b.y),
				Vector3(a.x, input.base_y, a.y),
				Vector3(c.x, input.base_y, c.y),
			])
			plane.uvs = PackedVector2Array([b * input.uv_scale, a * input.uv_scale, c * input.uv_scale])
			model.planes.append(plane)


static func _classify_edges(
	model: RoofModel, input: RoofInput, eave_poly: PackedVector2Array,
	faces: Array[StraightSkeleton.Face], tan_pitch: float, drop_run: float,
	keeps: Array[PackedVector2Array], clips: Array[PackedVector2Array],
	gable_ends: Array[Dictionary] = []
) -> void:
	var n: int = eave_poly.size()

	var face_centroids: Array[Vector2] = []
	var face_normals: Array[Vector2] = []
	for face in faces:
		var centroid := Vector2.ZERO
		for pt in face.points:
			centroid += pt
		face_centroids.append(centroid / maxf(1.0, float(face.points.size())))
		var p1: Vector2 = eave_poly[face.edge_index]
		var p2: Vector2 = eave_poly[(face.edge_index + 1) % n]
		var edge_dir: Vector2 = (p2 - p1).normalized()
		face_normals.append(Vector2(edge_dir.y, -edge_dir.x))

	var segments: Dictionary = {}
	for fi in range(faces.size()):
		var face: StraightSkeleton.Face = faces[fi]
		var count: int = face.points.size()
		for i in range(count):
			var j: int = (i + 1) % count
			var a: Vector2 = face.points[i]
			var b: Vector2 = face.points[j]
			if a.distance_to(b) < RoofConstants.MIN_EDGE_LENGTH:
				continue
			if face.offsets[i] < RoofConstants.EAVE_OFFSET_EPS and face.offsets[j] < RoofConstants.EAVE_OFFSET_EPS:
				continue
			var key: String = _segment_key(a, b)
			if segments.has(key):
				segments[key]["faces"].append(fi)
			else:
				segments[key] = {"a": a, "b": b, "oa": face.offsets[i], "ob": face.offsets[j], "faces": [fi]}

	for key in segments:
		var seg: Dictionary = segments[key]
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		var type: int
		if _on_gable_line(a, b, gable_ends):
			type = RoofModel.EdgeType.RAKE
		elif absf(seg["oa"] - seg["ob"]) < RoofConstants.RIDGE_OFFSET_EPS:
			type = RoofModel.EdgeType.RIDGE
		else:
			var dir: Vector2 = (b - a).normalized()
			var perp := Vector2(-dir.y, dir.x)
			var mid: Vector2 = (a + b) * 0.5
			var rises_on_all_sides := true
			for fi in seg["faces"]:
				var side: float = signf((face_centroids[fi] - mid).dot(perp))
				if -(face_normals[fi].dot(perp)) * side <= 0.0:
					rises_on_all_sides = false
			type = RoofModel.EdgeType.VALLEY if rises_on_all_sides else RoofModel.EdgeType.HIP

		var ya: float = input.base_y + (seg["oa"] - drop_run) * tan_pitch
		var yb: float = input.base_y + (seg["ob"] - drop_run) * tan_pitch
		var length: float = a.distance_to(b)
		var dirn: Vector2 = (b - a) / length
		for part in _clip_plan_segment(a, b, keeps, clips):
			var edge := RoofModel.RoofEdge.new()
			edge.type = type
			var ta: float = (part[0] - a).dot(dirn) / length
			var tb: float = (part[1] - a).dot(dirn) / length
			edge.a = Vector3(part[0].x, lerpf(ya, yb, ta), part[0].y)
			edge.b = Vector3(part[1].x, lerpf(ya, yb, tb), part[1].y)
			model.edges.append(edge)


static func _segment_key(a: Vector2, b: Vector2) -> String:
	var qa := Vector2i((a / RoofConstants.EDGE_KEY_QUANTUM).round())
	var qb := Vector2i((b / RoofConstants.EDGE_KEY_QUANTUM).round())
	if qa.x > qb.x or (qa.x == qb.x and qa.y > qb.y):
		var t := qa
		qa = qb
		qb = t
	return "%d,%d|%d,%d" % [qa.x, qa.y, qb.x, qb.y]


static func _eave_segments(
	eave_poly: PackedVector2Array, keeps: Array[PackedVector2Array], clips: Array[PackedVector2Array],
	gable_ends: Array[Dictionary] = []
) -> Array[Dictionary]:
	var gabled: Dictionary = {}
	for gable in gable_ends:
		gabled[gable["edge_index"]] = true

	var out: Array[Dictionary] = []
	var n: int = eave_poly.size()
	for i in range(n):
		if gabled.has(i):
			continue
		var a: Vector2 = eave_poly[i]
		var b: Vector2 = eave_poly[(i + 1) % n]
		for part in _clip_plan_segment(a, b, keeps, clips):
			var pa: Vector2 = part[0]
			var pb: Vector2 = part[1]
			if (pb - pa).dot(b - a) < 0.0:
				var t := pa
				pa = pb
				pb = t
			out.append({"a": pa, "b": pb, "index": i})
	return out


static func _build_fascia(
	model: RoofModel, input: RoofInput, eave_poly: PackedVector2Array,
	segments: Array[Dictionary], eave_y: float
) -> void:
	if input.fascia_height <= 0.0:
		return
	var bottom: float = eave_y - input.fascia_height
	for seg in segments:
		var a: Vector2 = seg["a"]
		var b: Vector2 = seg["b"]
		var dir: Vector2 = (b - a).normalized()
		var length: float = a.distance_to(b)

		var plane := RoofModel.RoofPlane.new()
		plane.slot = input.slot_fascia
		plane.material = input.fascia_material
		plane.normal = Vector3(dir.y, 0, -dir.x)
		plane.convex = true
		plane.points = PackedVector3Array([
			Vector3(a.x, bottom, a.y),
			Vector3(a.x, eave_y, a.y),
			Vector3(b.x, eave_y, b.y),
			Vector3(b.x, bottom, b.y),
		])
		plane.uvs = PackedVector2Array([
			Vector2(0, input.fascia_height), Vector2(0, 0),
			Vector2(length, 0), Vector2(length, input.fascia_height),
		])
		model.planes.append(plane)


static func _build_soffit(
	model: RoofModel, input: RoofInput, eave_poly: PackedVector2Array,
	segments: Array[Dictionary], keeps: Array[PackedVector2Array], clips: Array[PackedVector2Array],
	has_overhang: bool, eave_y: float
) -> void:
	if not has_overhang:
		return
	var n: int = eave_poly.size()
	var soffit_y: float = eave_y - input.fascia_height
	var inner_poly: PackedVector2Array = miter_offset(eave_poly, -(input.overhang + input.soffit_overlap))

	for seg in segments:
		var i: int = seg["index"]
		var j: int = (i + 1) % n
		var p1: Vector2 = eave_poly[i]
		var p2: Vector2 = eave_poly[j]
		var edge_len: float = p1.distance_to(p2)
		if edge_len < RoofConstants.MIN_EDGE_LENGTH:
			continue
		var edge_dir: Vector2 = (p2 - p1) / edge_len
		var normal2 := Vector2(edge_dir.y, -edge_dir.x)
		var line_const: float = p1.dot(normal2)

		var ta: float = clampf((seg["a"] - p1).dot(edge_dir) / edge_len, 0.0, 1.0)
		var tb: float = clampf((seg["b"] - p1).dot(edge_dir) / edge_len, 0.0, 1.0)
		var quad := PackedVector2Array([
			seg["a"], seg["b"],
			inner_poly[i].lerp(inner_poly[j], tb),
			inner_poly[i].lerp(inner_poly[j], ta),
		])

		for piece in _clip_plan_polygon(quad, keeps, clips):
			if _signed_area(piece) < 0.0:
				piece.reverse()

			var plane := RoofModel.RoofPlane.new()
			plane.slot = input.slot_underlayment
			plane.material = input.underlayment_material
			plane.normal = Vector3.DOWN
			plane.convex = false
			for pt in piece:
				plane.points.append(Vector3(pt.x, soffit_y, pt.y))
				plane.uvs.append(Vector2((pt - p1).dot(edge_dir), line_const - pt.dot(normal2)))
			model.planes.append(plane)


static func _areas_conserved(eave_poly: PackedVector2Array, faces: Array[StraightSkeleton.Face]) -> bool:
	var expected: float = absf(_signed_area(eave_poly))
	var total: float = 0.0
	for face in faces:
		total += absf(_signed_area(face.points))
	return absf(total - expected) < maxf(RoofConstants.AREA_TOLERANCE_ABS, expected * RoofConstants.AREA_TOLERANCE_REL)


static func _signed_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	var n: int = points.size()
	for i in range(n):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return area * 0.5
