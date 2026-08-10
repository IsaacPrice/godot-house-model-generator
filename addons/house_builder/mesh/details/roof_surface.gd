@tool
class_name RoofSurface
extends RefCounted


const SLOT_SHINGLES := "roof"

const SLOT_GABLE := "siding"

const PROBE_OFFSET := 1e-3

const PROBES: Array[Vector2] = [
	Vector2.ZERO,
	Vector2(PROBE_OFFSET, 0), Vector2(-PROBE_OFFSET, 0),
	Vector2(0, PROBE_OFFSET), Vector2(0, -PROBE_OFFSET),
]


const ANY_LEVEL := -2147483648


static func height_at(models: Array[Dictionary], p: Vector2, floor_level: int = ANY_LEVEL) -> float:
	var best: float = -INF
	for entry in models:
		if floor_level != ANY_LEVEL and entry["floor_level"] != floor_level:
			continue
		var model: RoofModel = entry["model"]
		for plane in model.planes:
			if plane.slot != SLOT_SHINGLES:
				continue
			if absf(plane.normal.y) < 1e-6:
				continue

			var plan := PackedVector2Array()
			for point in plane.points:
				plan.append(Vector2(point.x, point.z))

			var contains: bool = false
			for probe in PROBES:
				if Geometry2D.is_point_in_polygon(p + probe, plan):
					contains = true
					break
			if not contains:
				continue

			var normal: Vector3 = plane.normal
			var d: float = normal.dot(plane.points[0])
			best = maxf(best, (d - normal.x * p.x - normal.z * p.y) / normal.y)
	return best


static func min_height_over_region(models: Array[Dictionary], region: PackedVector2Array, floor_level: int = ANY_LEVEL) -> float:
	var best: float = INF
	for entry in models:
		if floor_level != ANY_LEVEL and entry["floor_level"] != floor_level:
			continue
		var model: RoofModel = entry["model"]
		for plane in model.planes:
			if plane.slot != SLOT_SHINGLES:
				continue
			if absf(plane.normal.y) < 1e-6:
				continue

			var plan := PackedVector2Array()
			for point in plane.points:
				plan.append(Vector2(point.x, point.z))

			var normal: Vector3 = plane.normal
			var d: float = normal.dot(plane.points[0])
			for piece in Geometry2D.intersect_polygons(plan, region):
				for p in piece:
					best = minf(best, (d - normal.x * p.x - normal.z * p.y) / normal.y)
	return best
