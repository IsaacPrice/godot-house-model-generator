@tool
class_name SidewalkBuilder
extends RefCounted


const SLOT_SIDEWALK := "sidewalk"

const EPS := 1e-4
const MIN_AREA := 1e-3
const CLIP_SPLIT_PADDING := 1.0
const MAX_HOLE_SPLIT_DEPTH := 4


static func build(house: HouseData) -> ArrayMesh:
	if house.floors.is_empty():
		return null
	var cells: Array[Vector2i] = valid_cells(house.floors[0])
	if cells.is_empty():
		return null

	var regions: Dictionary = _regions(house, cells)
	var caps: Array[PackedVector2Array] = _cap_polys(regions)
	if caps.is_empty():
		return null

	var accumulator: SurfaceAccumulator = house.accumulator()
	var top_y: float = house.grade_y()
	var bottom_y: float = top_y - house.sidewalk_thickness

	for poly in caps:
		PlanPolygon.emit_horizontal(accumulator, SLOT_SIDEWALK, house.sidewalk_material, poly, top_y, true)
		PlanPolygon.emit_horizontal(accumulator, SLOT_SIDEWALK, house.sidewalk_material, poly, bottom_y, false, 1.0, SurfaceAccumulator.Visibility.BURIED)

	for poly in regions["outers"]:
		_emit_skirt(accumulator, house, poly, bottom_y, top_y, false)
	for poly in regions["holes"]:
		_emit_skirt(accumulator, house, poly, bottom_y, top_y, true)

	return accumulator.commit()


static func valid_cells(floor_data: FloorData) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in floor_data.sidewalk_cells:
		if floor_data.cells.has(cell):
			push_warning("House builder: sidewalk cell %s overlaps the house footprint; skipped." % cell)
			continue
		if floor_data.porch_cells.has(cell):
			push_warning("House builder: sidewalk cell %s overlaps the porch; skipped." % cell)
			continue
		result.append(cell)
	return result


static func plan_polys(house: HouseData, cells: Array[Vector2i]) -> Array[PackedVector2Array]:
	return _cap_polys(_regions(house, cells))


static func _regions(house: HouseData, cells: Array[Vector2i]) -> Dictionary:
	var outers: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []
	for loop in Footprint.trace_loops(cells, house.level_cell_size):
		if loop.size() < 3:
			continue
		if _is_hole(loop):
			holes.append(loop.points)
		else:
			outers.append(loop.points)

	var expand: float = house.sidewalk_expand
	if absf(expand) > EPS:
		outers = _offset_all(outers, expand)
		holes = _offset_all(holes, -expand)
		if expand > 0.0:
			outers = _merge_outers(outers, holes)
	return {"outers": outers, "holes": holes}


static func _is_hole(loop: BoundaryLoop) -> bool:
	var d: Vector2 = (loop.points[1] - loop.points[0]).normalized()
	return not Vector2(d.y, -d.x).is_equal_approx(loop.normals[0])


static func _offset_all(polys: Array[PackedVector2Array], delta: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for poly in polys:
		for piece in Geometry2D.offset_polygon(poly, delta, Geometry2D.JOIN_MITER):
			var normalized: PackedVector2Array = _positive_area(piece)
			if normalized.size() >= 3 and _signed_area(normalized) >= MIN_AREA:
				result.append(normalized)
	return result


static func _merge_outers(polys: Array[PackedVector2Array], holes: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for poly in polys:
		var current: PackedVector2Array = poly
		var i: int = 0
		while i < result.size():
			var pieces: Array[PackedVector2Array] = Geometry2D.merge_polygons(result[i], current)
			var solids: Array[PackedVector2Array] = []
			for piece in pieces:
				if piece.size() < 3 or absf(_signed_area(piece)) < MIN_AREA:
					continue
				if _signed_area(piece) < 0.0:
					holes.append(_positive_area(piece))
				else:
					solids.append(piece)
			if solids.size() == 1:
				current = solids[0]
				result.remove_at(i)
				i = 0
			else:
				i += 1
		result.append(current)
	return result


static func _cap_polys(regions: Dictionary) -> Array[PackedVector2Array]:
	var caps: Array[PackedVector2Array] = []
	for outer in regions["outers"]:
		caps.append(outer)

	for hole in regions["holes"]:
		for i in range(caps.size()):
			if not Geometry2D.is_point_in_polygon(hole[0], caps[i]):
				continue
			var pieces: Array[PackedVector2Array] = _subtract_hole_safe(caps[i], hole, 0)
			caps.remove_at(i)
			for piece in pieces:
				var normalized: PackedVector2Array = _positive_area(piece)
				if normalized.size() >= 3 and _signed_area(normalized) >= MIN_AREA:
					caps.append(normalized)
			break
	return caps


static func _subtract_hole_safe(subject: PackedVector2Array, clip: PackedVector2Array, depth: int) -> Array[PackedVector2Array]:
	var results: Array[PackedVector2Array] = Geometry2D.clip_polygons(subject, clip)
	var has_hole := false
	for i in range(results.size()):
		if has_hole:
			break
		for j in range(results.size()):
			if i != j and results[i].size() > 0 and Geometry2D.is_point_in_polygon(results[i][0], results[j]):
				has_hole = true
				break
	if not has_hole or depth >= MAX_HOLE_SPLIT_DEPTH:
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
	lo -= Vector2.ONE * CLIP_SPLIT_PADDING
	hi += Vector2.ONE * CLIP_SPLIT_PADDING

	var out: Array[PackedVector2Array] = []
	for half in [
		PackedVector2Array([lo, Vector2(centroid.x, lo.y), Vector2(centroid.x, hi.y), Vector2(lo.x, hi.y)]),
		PackedVector2Array([Vector2(centroid.x, lo.y), Vector2(hi.x, lo.y), hi, Vector2(centroid.x, hi.y)]),
	]:
		for piece in Geometry2D.intersect_polygons(subject, half):
			out.append_array(_subtract_hole_safe(piece, clip, depth + 1))
	return out


static func _emit_skirt(accumulator: SurfaceAccumulator, house: HouseData, poly: PackedVector2Array, bottom_y: float, top_y: float, is_hole: bool) -> void:
	var n: int = poly.size()
	for i in range(n):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		if a.distance_to(b) < EPS:
			continue
		var d: Vector2 = (b - a).normalized()
		var normal: Vector2 = Vector2(d.y, -d.x)
		if is_hole:
			_skirt_quad(accumulator, house.sidewalk_material, b, a, bottom_y, top_y, -normal)
		else:
			_skirt_quad(accumulator, house.sidewalk_material, a, b, bottom_y, top_y, normal)


static func _skirt_quad(accumulator: SurfaceAccumulator, material: Material, x0: Vector2, x1: Vector2, y0: float, y1: float, normal: Vector2) -> void:
	var length: float = x0.distance_to(x1)
	if length < EPS or y1 - y0 < EPS:
		return
	accumulator.add_quad(
		SLOT_SIDEWALK, material,
		Vector3(x0.x, y0, x0.y),
		Vector3(x0.x, y1, x0.y),
		Vector3(x1.x, y1, x1.y),
		Vector3(x1.x, y0, x1.y),
		Vector3(normal.x, 0, normal.y),
		Vector2(0, y1 - y0), Vector2(0, 0), Vector2(length, 0), Vector2(length, y1 - y0)
	)


static func _signed_area(poly: PackedVector2Array) -> float:
	var area: float = 0.0
	for i in range(poly.size()):
		var j: int = (i + 1) % poly.size()
		area += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return area * 0.5


static func _positive_area(poly: PackedVector2Array) -> PackedVector2Array:
	if _signed_area(poly) >= 0.0:
		return poly
	var reversed := poly.duplicate()
	reversed.reverse()
	return reversed
