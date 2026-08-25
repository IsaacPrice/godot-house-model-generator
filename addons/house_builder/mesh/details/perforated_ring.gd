@tool
class_name PerforatedRing
extends RefCounted


const POSITION_EPS := 1e-3
const STRIP_MIN := 1e-4


static func build(
	accumulator: SurfaceAccumulator, slot: String, material: Material, loop: BoundaryLoop,
	inward: float, outward: float, base_y: float, top_y: float,
	openings: Array[Dictionary],
	cap_bottom: bool = true, cap_top: bool = true,
	inner_visibility: int = SurfaceAccumulator.Visibility.EXTERIOR,
	cap_top_visibility: int = SurfaceAccumulator.Visibility.EXTERIOR,
	cap_bottom_visibility: int = SurfaceAccumulator.Visibility.EXTERIOR
) -> void:
	var n: int = loop.size()
	if n < 3:
		return

	var outer: PackedVector2Array = PackedVector2Array()
	var inner: PackedVector2Array = PackedVector2Array()
	for i in range(n):
		outer.append(loop.corner_offset(i, outward))
		inner.append(loop.corner_offset(i, -inward))

	for i in range(n):
		var j: int = (i + 1) % n
		var normal: Vector2 = loop.normals[i]
		var d: Vector2 = (loop.points[j] - loop.points[i]).normalized()
		var edge_openings: Array[Dictionary] = _openings_on_edge(openings, loop.points[i], loop.points[j], normal, base_y, top_y)

		var cursor: Vector2 = outer[i]
		for op in edge_openings:
			var xa: Vector2 = op["a"] + normal * outward
			var xb: Vector2 = op["b"] + normal * outward
			_wall_quad(accumulator, slot, material, cursor, xa, base_y, top_y, normal, outer[i], d, top_y)
			if op["bottom_y"] > base_y + POSITION_EPS:
				_wall_quad(accumulator, slot, material, xa, xb, base_y, op["bottom_y"], normal, outer[i], d, top_y)
			if op["top_y"] < top_y - POSITION_EPS:
				_wall_quad(accumulator, slot, material, xa, xb, op["top_y"], top_y, normal, outer[i], d, top_y)
			cursor = xb
		_wall_quad(accumulator, slot, material, cursor, outer[j], base_y, top_y, normal, outer[i], d, top_y)

		cursor = inner[j]
		for k in range(edge_openings.size() - 1, -1, -1):
			var op: Dictionary = edge_openings[k]
			var xb_in: Vector2 = op["b"] - normal * inward
			var xa_in: Vector2 = op["a"] - normal * inward
			_wall_quad(accumulator, slot, material, cursor, xb_in, base_y, top_y, -normal, inner[i], d, top_y, inner_visibility)
			if op["bottom_y"] > base_y + POSITION_EPS:
				_wall_quad(accumulator, slot, material, xb_in, xa_in, base_y, op["bottom_y"], -normal, inner[i], d, top_y, inner_visibility)
			if op["top_y"] < top_y - POSITION_EPS:
				_wall_quad(accumulator, slot, material, xb_in, xa_in, op["top_y"], top_y, -normal, inner[i], d, top_y, inner_visibility)
			cursor = xa_in
		_wall_quad(accumulator, slot, material, cursor, inner[i], base_y, top_y, -normal, inner[i], d, top_y, inner_visibility)

		for op in edge_openings:
			_emit_jambs(accumulator, slot, material, op, normal, d, inward, outward, base_y, top_y)

		if cap_top:
			_emit_cap_run(accumulator, slot, material, outer[i], outer[j], inner[i], inner[j], normal, d, inward, outward, top_y, true, edge_openings, base_y, top_y, cap_top_visibility)
		if cap_bottom:
			_emit_cap_run(accumulator, slot, material, outer[i], outer[j], inner[i], inner[j], normal, d, inward, outward, base_y, false, edge_openings, base_y, top_y, cap_bottom_visibility)


static func build_segment(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	a: Vector2, b: Vector2, normal: Vector2, half_thickness: float,
	base_y: float, top_y: float, openings: Array[Dictionary]
) -> void:
	var d: Vector2 = (b - a).normalized()
	var a_out: Vector2 = a + normal * half_thickness
	var b_out: Vector2 = b + normal * half_thickness
	var a_in: Vector2 = a - normal * half_thickness
	var b_in: Vector2 = b - normal * half_thickness
	var edge_openings: Array[Dictionary] = _openings_on_edge(openings, a, b, normal, base_y, top_y)

	var cursor: Vector2 = a_out
	for op in edge_openings:
		var xa: Vector2 = op["a"] + normal * half_thickness
		var xb: Vector2 = op["b"] + normal * half_thickness
		_wall_quad(accumulator, slot, material, cursor, xa, base_y, top_y, normal, a_out, d, top_y)
		if op["bottom_y"] > base_y + POSITION_EPS:
			_wall_quad(accumulator, slot, material, xa, xb, base_y, op["bottom_y"], normal, a_out, d, top_y)
		if op["top_y"] < top_y - POSITION_EPS:
			_wall_quad(accumulator, slot, material, xa, xb, op["top_y"], top_y, normal, a_out, d, top_y)
		cursor = xb
	_wall_quad(accumulator, slot, material, cursor, b_out, base_y, top_y, normal, a_out, d, top_y)

	cursor = b_in
	for k in range(edge_openings.size() - 1, -1, -1):
		var op: Dictionary = edge_openings[k]
		var xb_in: Vector2 = op["b"] - normal * half_thickness
		var xa_in: Vector2 = op["a"] - normal * half_thickness
		_wall_quad(accumulator, slot, material, cursor, xb_in, base_y, top_y, -normal, a_in, d, top_y)
		if op["bottom_y"] > base_y + POSITION_EPS:
			_wall_quad(accumulator, slot, material, xb_in, xa_in, base_y, op["bottom_y"], -normal, a_in, d, top_y)
		if op["top_y"] < top_y - POSITION_EPS:
			_wall_quad(accumulator, slot, material, xb_in, xa_in, op["top_y"], top_y, -normal, a_in, d, top_y)
		cursor = xa_in
	_wall_quad(accumulator, slot, material, cursor, a_in, base_y, top_y, -normal, a_in, d, top_y)

	for op in edge_openings:
		_emit_jambs(accumulator, slot, material, op, normal, d, half_thickness, half_thickness, base_y, top_y)

	_wall_quad(accumulator, slot, material, a_in, a_out, base_y, top_y, -d, a_in, normal, top_y)
	_wall_quad(accumulator, slot, material, b_out, b_in, base_y, top_y, d, b_out, -normal, top_y)


static func _openings_on_edge(openings: Array[Dictionary], p_i: Vector2, p_j: Vector2, normal: Vector2, base_y: float, top_y: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var length: float = p_i.distance_to(p_j)
	if length < STRIP_MIN:
		return result
	var d: Vector2 = (p_j - p_i) / length

	for op in openings:
		if not op["normal"].is_equal_approx(normal):
			continue
		var mid: Vector2 = (op["a"] + op["b"]) * 0.5
		var t: float = (mid - p_i).dot(d)
		if t < -POSITION_EPS or t > length + POSITION_EPS:
			continue
		if (mid - (p_i + d * t)).length() > POSITION_EPS:
			continue

		var entry: Dictionary = op.duplicate()
		entry["bottom_y"] = maxf(op["bottom_y"], base_y)
		entry["top_y"] = minf(op["top_y"], top_y)
		if entry["top_y"] - entry["bottom_y"] <= STRIP_MIN:
			continue
		if (op["a"] - p_i).dot(d) > (op["b"] - p_i).dot(d):
			entry["a"] = op["b"]
			entry["b"] = op["a"]
		result.append(entry)

	result.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return (x["a"] - p_i).dot(d) < (y["a"] - p_i).dot(d)
	)
	return result


static func _wall_quad(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	x0: Vector2, x1: Vector2, y0: float, y1: float, normal: Vector2,
	u_origin: Vector2, u_dir: Vector2, v_ref: float,
	visibility: int = SurfaceAccumulator.Visibility.EXTERIOR
) -> void:
	if x0.distance_to(x1) < STRIP_MIN or y1 - y0 < STRIP_MIN:
		return
	var u0: float = (x0 - u_origin).dot(u_dir)
	var u1: float = (x1 - u_origin).dot(u_dir)
	accumulator.add_quad(
		slot, material,
		Vector3(x0.x, y0, x0.y),
		Vector3(x0.x, y1, x0.y),
		Vector3(x1.x, y1, x1.y),
		Vector3(x1.x, y0, x1.y),
		Vector3(normal.x, 0, normal.y),
		Vector2(u0, v_ref - y0), Vector2(u0, v_ref - y1), Vector2(u1, v_ref - y1), Vector2(u1, v_ref - y0),
		visibility
	)


static func _emit_cap_run(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	outer_a: Vector2, outer_b: Vector2, inner_a: Vector2, inner_b: Vector2,
	normal: Vector2, d: Vector2, inward: float, outward: float,
	cap_y: float, is_top: bool, edge_openings: Array[Dictionary],
	base_y: float, top_y: float, visibility: int = SurfaceAccumulator.Visibility.EXTERIOR
) -> void:
	var cursor_out: Vector2 = outer_a
	var cursor_in: Vector2 = inner_a
	for op in edge_openings:
		var reaches_cap: bool = op["top_y"] >= top_y - POSITION_EPS if is_top else op["bottom_y"] <= base_y + POSITION_EPS
		if not reaches_cap:
			continue
		_cap_quad(
			accumulator, slot, material,
			cursor_out, op["a"] + normal * outward, cursor_in, op["a"] - normal * inward,
			outer_a, d, inward + outward, cap_y, is_top, visibility
		)
		cursor_out = op["b"] + normal * outward
		cursor_in = op["b"] - normal * inward
	_cap_quad(accumulator, slot, material, cursor_out, outer_b, cursor_in, inner_b, outer_a, d, inward + outward, cap_y, is_top, visibility)


static func _cap_quad(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	out0: Vector2, out1: Vector2, in0: Vector2, in1: Vector2,
	u_origin: Vector2, u_dir: Vector2, ring_width: float, y: float, is_top: bool,
	visibility: int = SurfaceAccumulator.Visibility.EXTERIOR
) -> void:
	if out0.distance_to(out1) < STRIP_MIN:
		return
	var u0: float = (out0 - u_origin).dot(u_dir)
	var u1: float = (out1 - u_origin).dot(u_dir)
	if is_top:
		accumulator.add_quad(
			slot, material,
			Vector3(out0.x, y, out0.y),
			Vector3(in0.x, y, in0.y),
			Vector3(in1.x, y, in1.y),
			Vector3(out1.x, y, out1.y),
			Vector3(0, 1, 0),
			Vector2(u0, 0), Vector2(u0, ring_width), Vector2(u1, ring_width), Vector2(u1, 0),
			visibility
		)
	else:
		accumulator.add_quad(
			slot, material,
			Vector3(out1.x, y, out1.y),
			Vector3(in1.x, y, in1.y),
			Vector3(in0.x, y, in0.y),
			Vector3(out0.x, y, out0.y),
			Vector3(0, -1, 0),
			Vector2(u1, 0), Vector2(u1, ring_width), Vector2(u0, ring_width), Vector2(u0, 0),
			visibility
		)


static func _emit_jambs(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	op: Dictionary, normal: Vector2, d: Vector2, inward: float, outward: float, base_y: float, ring_top: float
) -> void:
	var a: Vector2 = op["a"]
	var b: Vector2 = op["b"]
	var bottom_y: float = op["bottom_y"]
	var top_y: float = op["top_y"]
	var a_out: Vector2 = a + normal * outward
	var a_in: Vector2 = a - normal * inward
	var b_out: Vector2 = b + normal * outward
	var b_in: Vector2 = b - normal * inward
	var thickness: float = inward + outward
	var opening_width: float = a.distance_to(b)

	_wall_quad(accumulator, slot, material, a_out, a_in, bottom_y, top_y, d, a_out, -normal, top_y)
	_wall_quad(accumulator, slot, material, b_in, b_out, bottom_y, top_y, -d, b_in, normal, top_y)

	if top_y < ring_top - POSITION_EPS:
		accumulator.add_quad(
			slot, material,
			Vector3(b_out.x, top_y, b_out.y),
			Vector3(b_in.x, top_y, b_in.y),
			Vector3(a_in.x, top_y, a_in.y),
			Vector3(a_out.x, top_y, a_out.y),
			Vector3(0, -1, 0),
			Vector2(opening_width, 0), Vector2(opening_width, thickness), Vector2(0, thickness), Vector2(0, 0)
		)

	if bottom_y > base_y + POSITION_EPS:
		accumulator.add_quad(
			slot, material,
			Vector3(a_out.x, bottom_y, a_out.y),
			Vector3(a_in.x, bottom_y, a_in.y),
			Vector3(b_in.x, bottom_y, b_in.y),
			Vector3(b_out.x, bottom_y, b_out.y),
			Vector3(0, 1, 0),
			Vector2(0, 0), Vector2(0, thickness), Vector2(opening_width, thickness), Vector2(opening_width, 0)
		)
