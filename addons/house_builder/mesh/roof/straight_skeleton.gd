@tool
class_name StraightSkeleton
extends RefCounted


class Face extends RefCounted:
	var edge_index: int = -1
	var points := PackedVector2Array()
	var offsets := PackedFloat32Array()


class Result extends RefCounted:
	var faces: Array[Face] = []
	var completed: bool = true


class SkelVertex extends RefCounted:
	var pos0 := Vector2.ZERO
	var created_d: float = 0.0
	var velocity := Vector2.ZERO
	var reflex: bool = false
	var edge_in = null
	var edge_out = null

	func pos_at(d: float) -> Vector2:
		return pos0 + velocity * (d - created_d)


class SkelEdge extends RefCounted:
	var v_start = null
	var v_end = null
	var normal := Vector2.ZERO
	var direction := Vector2.ZERO
	var line_const: float = 0.0
	var weight: float = 1.0
	var edge_index: int = -1
	var closed: bool = false
	var left_points := PackedVector2Array()
	var left_offsets := PackedFloat32Array()
	var right_points := PackedVector2Array()
	var right_offsets := PackedFloat32Array()


static func compute(points: PackedVector2Array, weights := PackedFloat32Array()) -> Result:
	var result := Result.new()
	var n: int = points.size()
	if n < 3:
		return result
	var weighted: bool = weights.size() == n

	var normals: Array[Vector2] = []
	for i in range(n):
		var dir: Vector2 = (points[(i + 1) % n] - points[i]).normalized()
		normals.append(Vector2(dir.y, -dir.x))

	var vertices: Array[SkelVertex] = []
	for i in range(n):
		var prev: int = (i - 1 + n) % n
		vertices.append(_make_vertex(
			points[i], 0.0, normals[prev], normals[i],
			weights[prev] if weighted else 1.0, weights[i] if weighted else 1.0))

	var edges: Array[SkelEdge] = []
	for i in range(n):
		var e := SkelEdge.new()
		e.v_start = vertices[i]
		e.v_end = vertices[(i + 1) % n]
		e.normal = normals[i]
		e.direction = Vector2(-normals[i].y, normals[i].x)
		e.line_const = points[i].dot(normals[i])
		e.weight = weights[i] if weighted else 1.0
		e.edge_index = i
		e.left_points.append(points[i])
		e.left_offsets.append(0.0)
		e.right_points.append(points[(i + 1) % n])
		e.right_offsets.append(0.0)
		edges.append(e)

	for i in range(n):
		vertices[i].edge_in = edges[(i - 1 + n) % n]
		vertices[i].edge_out = edges[i]

	var current_d: float = 0.0
	var max_iterations: int = RoofConstants.ITERATION_CAP_QUADRATIC * n * n + RoofConstants.ITERATION_CAP_BASE
	var iterations: int = 0

	var raw_faces: Array[Face] = []
	while edges.size() > 0 and iterations < max_iterations:
		iterations += 1
		var best: Dictionary = _find_next_event(edges, current_d)
		if best.is_empty():
			break
		current_d = best["d"]
		if best["type"] == "edge":
			_close_edge(best["edge"], best["point"], best["d"], edges, raw_faces)
		else:
			_resolve_split_event(best, edges, raw_faces)

	if iterations >= max_iterations:
		result.completed = false
		push_warning("StraightSkeleton: hit iteration cap with %d edge(s) still active." % edges.size())

	for e in edges:
		raw_faces.append(_force_close(e))

	result.faces = _stitch_split_faces(raw_faces)
	return result


static func _stitch_split_faces(raw: Array[Face]) -> Array[Face]:
	var by_edge: Dictionary = {}
	for face in raw:
		if face.points.size() < 2:
			continue
		if not by_edge.has(face.edge_index):
			by_edge[face.edge_index] = []
		by_edge[face.edge_index].append(face)

	var out: Array[Face] = []
	for edge_index in by_edge:
		var pieces: Array = by_edge[edge_index]
		while not pieces.is_empty():
			var chain: Face = _take_chain_start(pieces)
			var extended := true
			while extended and not pieces.is_empty():
				extended = false
				var tail: Vector2 = chain.points[chain.points.size() - 1]
				for i in range(pieces.size()):
					var piece: Face = pieces[i]
					if piece.points[0].distance_to(tail) < RoofConstants.FACE_WELD_EPS:
						for k in range(1, piece.points.size()):
							chain.points.append(piece.points[k])
							chain.offsets.append(piece.offsets[k])
						pieces.remove_at(i)
						extended = true
						break
			if chain.points.size() >= 3:
				out.append(chain)
	return out


static func _take_chain_start(pieces: Array) -> Face:
	for i in range(pieces.size()):
		var candidate: Face = pieces[i]
		var is_start := true
		for other in pieces:
			if other == candidate:
				continue
			var other_face: Face = other
			var other_tail: Vector2 = other_face.points[other_face.points.size() - 1]
			if other_tail.distance_to(candidate.points[0]) < RoofConstants.FACE_WELD_EPS:
				is_start = false
				break
		if is_start:
			pieces.remove_at(i)
			return candidate
	var fallback: Face = pieces[0]
	pieces.remove_at(0)
	return fallback


static func _make_vertex(
	pos: Vector2, d: float, n_left: Vector2, n_right: Vector2,
	w_left: float = 1.0, w_right: float = 1.0
) -> SkelVertex:
	var v := SkelVertex.new()
	v.pos0 = pos
	v.created_d = d
	v.velocity = _bisector_velocity(n_left, n_right, w_left, w_right)
	v.reflex = n_left.cross(n_right) < -RoofConstants.REFLEX_CROSS_EPS
	return v


static func _bisector_velocity(n_left: Vector2, n_right: Vector2, w_left: float, w_right: float) -> Vector2:
	if absf(w_left - w_right) < RoofConstants.VELOCITY_MATCH_EPS:
		var denom: float = 1.0 + n_left.dot(n_right)
		if denom < RoofConstants.ANTIPARALLEL_DENOM_EPS:
			return Vector2.ZERO
		return -(n_left + n_right) / denom * w_left
	var cross: float = n_left.cross(n_right)
	if absf(cross) < RoofConstants.REFLEX_CROSS_EPS:
		return Vector2.ZERO
	return Vector2(
		(-w_left * n_right.y + w_right * n_left.y) / cross,
		(w_left * n_right.x - w_right * n_left.x) / cross)


static func _find_next_event(edges: Array[SkelEdge], current_d: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF

	for e in edges:
		var d = _solve_edge_collapse(e)
		if d != null and d > current_d - RoofConstants.EVENT_EPS and d < best_d:
			best_d = d
			best = {"type": "edge", "d": d, "edge": e, "point": e.v_start.pos_at(d)}

	var seen: Dictionary = {}
	var reflex_vertices: Array[SkelVertex] = []
	for e in edges:
		for v in [e.v_start, e.v_end]:
			if not seen.has(v):
				seen[v] = true
				if v.reflex:
					reflex_vertices.append(v)

	for r in reflex_vertices:
		for e in edges:
			if e == r.edge_in or e == r.edge_out:
				continue
			var res = _solve_split(r, e)
			if res != null and res["d"] > current_d - RoofConstants.EVENT_EPS and res["d"] < best_d:
				best_d = res["d"]
				best = {"type": "split", "d": res["d"], "edge": e, "vertex": r, "point": res["point"]}

	return best


static func _solve_edge_collapse(e: SkelEdge):
	var dir: Vector2 = e.direction
	var vA: float = e.v_start.velocity.dot(dir)
	var vB: float = e.v_end.velocity.dot(dir)
	if vA - vB <= RoofConstants.COLLAPSE_SPEED_EPS:
		return null
	var a0: float = e.v_start.pos0.dot(dir) - vA * e.v_start.created_d
	var b0: float = e.v_end.pos0.dot(dir) - vB * e.v_end.created_d
	return (b0 - a0) / (vA - vB)


static func _solve_split(r: SkelVertex, e: SkelEdge):
	var k: float = r.velocity.dot(e.normal)
	if k + e.weight < RoofConstants.SPLIT_APPROACH_EPS:
		return null
	var d: float = (e.line_const - r.pos0.dot(e.normal) + k * r.created_d) / (k + e.weight)
	var x: Vector2 = r.pos_at(d)
	var xs: float = e.v_start.pos_at(d).dot(e.direction)
	var xe: float = e.v_end.pos_at(d).dot(e.direction)
	var xr: float = x.dot(e.direction)
	if xr < minf(xs, xe) - RoofConstants.EVENT_EPS or xr > maxf(xs, xe) + RoofConstants.EVENT_EPS:
		return null
	return {"d": d, "point": x}


static func _close_edge(m: SkelEdge, apex: Vector2, d: float, edges: Array[SkelEdge], faces: Array[Face]) -> void:
	if m.closed:
		return
	m.closed = true

	m.left_points.append(apex)
	m.left_offsets.append(m.weight * d)
	m.right_points.append(apex)
	m.right_offsets.append(m.weight * d)
	var face := _build_face(m)
	if face.points.size() >= 2:
		faces.append(face)
	edges.erase(m)

	var a: SkelVertex = m.v_start
	var b: SkelVertex = m.v_end
	var l: SkelEdge = a.edge_in
	var next_edge: SkelEdge = b.edge_out

	if l == null or next_edge == null or l == m or next_edge == m or l.closed or next_edge.closed:
		return

	if l == next_edge:
		_close_edge(l, apex, d, edges, faces)
		return

	var c := _make_vertex(apex, d, l.normal, next_edge.normal, l.weight, next_edge.weight)
	c.edge_in = l
	c.edge_out = next_edge

	l.v_end = c
	l.right_points.append(apex)
	l.right_offsets.append(l.weight * d)

	next_edge.v_start = c
	next_edge.left_points.append(apex)
	next_edge.left_offsets.append(next_edge.weight * d)

	_maybe_close_degenerate(l, d, edges, faces)
	_maybe_close_degenerate(next_edge, d, edges, faces)


static func _maybe_close_degenerate(e: SkelEdge, d: float, edges: Array[SkelEdge], faces: Array[Face]) -> bool:
	if e.closed:
		return true
	var length: float = e.v_end.pos_at(d).distance_to(e.v_start.pos_at(d))
	var diverging: bool = e.v_start.velocity.distance_to(e.v_end.velocity) > RoofConstants.VELOCITY_MATCH_EPS
	if length < RoofConstants.COINCIDENT_POINT_EPS and not diverging:
		_close_edge(e, e.v_start.pos_at(d), d, edges, faces)
		return true
	return false


static func _resolve_split_event(ev: Dictionary, edges: Array[SkelEdge], faces: Array[Face]) -> void:
	var r: SkelVertex = ev["vertex"]
	var e: SkelEdge = ev["edge"]
	var x: Vector2 = ev["point"]
	var d: float = ev["d"]

	var l: SkelEdge = r.edge_in
	var n: SkelEdge = r.edge_out
	if l == null or n == null:
		return

	var xa := _make_vertex(x, d, l.normal, e.normal, l.weight, e.weight)
	xa.edge_in = l
	var xb := _make_vertex(x, d, e.normal, n.normal, e.weight, n.weight)
	xb.edge_out = n

	var e1 := SkelEdge.new()
	e1.v_start = e.v_start
	e1.v_end = xb
	e1.normal = e.normal
	e1.direction = e.direction
	e1.line_const = e.line_const
	e1.weight = e.weight
	e1.edge_index = e.edge_index
	e1.left_points = e.left_points.duplicate()
	e1.left_offsets = e.left_offsets.duplicate()
	e1.right_points = PackedVector2Array([x])
	e1.right_offsets = PackedFloat32Array([e.weight * d])
	xb.edge_in = e1
	e.v_start.edge_out = e1

	var e2 := SkelEdge.new()
	e2.v_start = xa
	e2.v_end = e.v_end
	e2.normal = e.normal
	e2.direction = e.direction
	e2.line_const = e.line_const
	e2.weight = e.weight
	e2.edge_index = e.edge_index
	e2.left_points = PackedVector2Array([x])
	e2.left_offsets = PackedFloat32Array([e.weight * d])
	e2.right_points = e.right_points.duplicate()
	e2.right_offsets = e.right_offsets.duplicate()
	xa.edge_out = e2
	e.v_end.edge_in = e2

	if e.v_start.pos_at(d).distance_to(x) < RoofConstants.COINCIDENT_POINT_EPS:
		e2.left_points = e.left_points.duplicate()
		e2.left_offsets = e.left_offsets.duplicate()
		e2.left_points.append(x)
		e2.left_offsets.append(e.weight * d)
	if e.v_end.pos_at(d).distance_to(x) < RoofConstants.COINCIDENT_POINT_EPS:
		e1.right_points = e.right_points.duplicate()
		e1.right_offsets = e.right_offsets.duplicate()
		e1.right_points.append(x)
		e1.right_offsets.append(e.weight * d)

	l.v_end = xa
	l.right_points.append(x)
	l.right_offsets.append(l.weight * d)

	n.v_start = xb
	n.left_points.append(x)
	n.left_offsets.append(n.weight * d)

	_maybe_close_degenerate(l, d, edges, faces)
	_maybe_close_degenerate(n, d, edges, faces)

	e.closed = true
	edges.erase(e)
	if not _maybe_close_degenerate(e1, d, edges, faces):
		edges.append(e1)
	if not _maybe_close_degenerate(e2, d, edges, faces):
		edges.append(e2)


static func _build_face(e: SkelEdge) -> Face:
	var face := Face.new()
	face.edge_index = e.edge_index
	for i in range(e.left_points.size()):
		face.points.append(e.left_points[i])
		face.offsets.append(e.left_offsets[i])
	for i in range(e.right_points.size() - 1, -1, -1):
		face.points.append(e.right_points[i])
		face.offsets.append(e.right_offsets[i])
	_dedupe(face)
	return face


static func _force_close(e: SkelEdge) -> Face:
	e.left_points.append(e.v_start.pos0)
	e.left_offsets.append(e.weight * e.v_start.created_d)
	e.right_points.append(e.v_end.pos0)
	e.right_offsets.append(e.weight * e.v_end.created_d)
	return _build_face(e)


static func _dedupe(face: Face) -> void:
	var weld_sq: float = RoofConstants.FACE_WELD_EPS * RoofConstants.FACE_WELD_EPS
	var pts := PackedVector2Array()
	var offs := PackedFloat32Array()
	for i in range(face.points.size()):
		if pts.size() > 0 and pts[pts.size() - 1].distance_squared_to(face.points[i]) < weld_sq:
			continue
		pts.append(face.points[i])
		offs.append(face.offsets[i])
	if pts.size() > 1 and pts[0].distance_squared_to(pts[pts.size() - 1]) < weld_sq:
		pts.remove_at(pts.size() - 1)
		offs.remove_at(offs.size() - 1)
	face.points = pts
	face.offsets = offs
