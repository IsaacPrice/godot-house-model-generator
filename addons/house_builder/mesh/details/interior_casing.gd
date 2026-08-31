@tool
class_name InteriorCasing
extends RefCounted


static func build(house: HouseData, opening: Dictionary, accumulator: SurfaceAccumulator) -> void:
	var casing: float = house.interior_casing_width
	var depth: float = house.interior_casing_depth
	if casing <= 0.0 or depth <= 0.0:
		return

	var a: Vector2 = opening["a"]
	var along: Vector2 = (opening["b"] as Vector2 - a).normalized()
	var normal: Vector2 = opening["normal"]
	var width: float = a.distance_to(opening["b"])
	var bottom_y: float = opening["bottom_y"]
	var top_y: float = opening["top_y"]

	var face: float = -house.wall_thickness * 0.5
	var back: float = face - depth
	var is_window: bool = (opening["detail"] as WallDetail).type == WallDetail.DetailType.WINDOW

	if is_window:
		_stool(house, accumulator, a, along, normal, width, casing, face, bottom_y)

	_band(house, accumulator, a, along, normal, -casing, 0.0, back, face, bottom_y, top_y)
	_band(house, accumulator, a, along, normal, width, width + casing, back, face, bottom_y, top_y)
	_band(house, accumulator, a, along, normal, -casing, width + casing, back, face, top_y, top_y + casing)


static func _stool(
	house: HouseData, accumulator: SurfaceAccumulator,
	a: Vector2, along: Vector2, normal: Vector2, width: float, casing: float,
	face: float, bottom_y: float
) -> void:
	_band(
		house, accumulator, a, along, normal,
		-casing - DetailConstants.SILL_SIDE_EXTEND, width + casing + DetailConstants.SILL_SIDE_EXTEND,
		face - house.interior_casing_depth - DetailConstants.SILL_PROJECTION, 0.0,
		bottom_y - DetailConstants.SILL_THICKNESS, bottom_y
	)


static func _band(
	house: HouseData, accumulator: SurfaceAccumulator,
	origin: Vector2, along: Vector2, normal: Vector2,
	s0: float, s1: float, d0: float, d1: float, y0: float, y1: float
) -> void:
	if s1 - s0 <= 0.0 or y1 - y0 <= 0.0:
		return
	var p0: Vector2 = origin + along * s0 + normal * d0
	var p1: Vector2 = origin + along * s1 + normal * d1
	var buried: int = BoxBuilder.face_toward(normal)
	BoxBuilder.build(
		accumulator, InteriorBuilder.SLOT_TRIM, house.interior_trim_material,
		p0, p1, y0, y1, buried, InteriorBuilder.ALL_FACES & ~buried
	)
