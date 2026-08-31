@tool
class_name GarageDoorBuilder
extends RefCounted


const SLOT_CASING := "window_frame"
const SLOT_DOOR := "garage_door"


static func build(house: HouseData, opening: Dictionary, accumulator: SurfaceAccumulator) -> void:
	var a: Vector2 = opening["a"]
	var along: Vector2 = (opening["b"] as Vector2 - a).normalized()
	var normal: Vector2 = opening["normal"]
	var width: float = a.distance_to(opening["b"])
	var bottom_y: float = opening["bottom_y"]
	var top_y: float = opening["top_y"]

	var frame: float = DetailConstants.FRAME_WIDTH
	var half_thickness: float = house.wall_thickness * 0.5
	var depth_in: float = -half_thickness
	var depth_out: float = half_thickness + DetailConstants.FRAME_DEPTH

	var casing_interior: int = BoxBuilder.face_toward(-normal)
	_box(accumulator, SLOT_CASING, house.window_frame_material, a, along, normal, 0.0, frame, depth_in, depth_out, bottom_y, top_y, casing_interior)
	_box(accumulator, SLOT_CASING, house.window_frame_material, a, along, normal, width - frame, width, depth_in, depth_out, bottom_y, top_y, casing_interior)
	_box(accumulator, SLOT_CASING, house.window_frame_material, a, along, normal, frame, width - frame, depth_in, depth_out, top_y - frame, top_y, casing_interior)

	if (opening["detail"] as WallDetail).door_mode == WallDetail.DoorMode.STATIC:
		build_leaf(house, opening, accumulator)


static func build_leaf(house: HouseData, opening: Dictionary, accumulator: SurfaceAccumulator) -> void:
	var a: Vector2 = opening["a"]
	var along: Vector2 = (opening["b"] as Vector2 - a).normalized()
	var normal: Vector2 = opening["normal"]
	var width: float = a.distance_to(opening["b"])
	var frame: float = DetailConstants.FRAME_WIDTH
	var animated: bool = (opening["detail"] as WallDetail).is_animated()
	_emit_panels(house, accumulator, a, along, normal, frame, width - frame, opening["bottom_y"], (opening["top_y"] as float) - frame, animated)


static func _emit_panels(
	house: HouseData, accumulator: SurfaceAccumulator,
	origin: Vector2, along: Vector2, normal: Vector2,
	s0: float, s1: float, base_y: float, head_y: float, animated: bool = false
) -> void:
	var slab_out: float = house.wall_thickness * 0.5 - DetailConstants.DOOR_SLAB_INSET
	var slab_in: float = slab_out - DetailConstants.DOOR_SLAB_THICKNESS
	var count: int = DetailConstants.GARAGE_PANEL_COUNT
	var gap: float = DetailConstants.GARAGE_PANEL_GAP
	var panel_height: float = (head_y - base_y - (count - 1) * gap) / count
	if panel_height <= 0.0 or s1 <= s0:
		return

	var material: Material = house.garage_door_material
	var back: int = SurfaceAccumulator.Visibility.EXTERIOR if animated else SurfaceAccumulator.Visibility.INTERIOR
	_face_vertical(accumulator, SLOT_DOOR, material, origin, along, normal, s0, s1, slab_in, base_y, head_y, -1.0, back)

	for k in range(count):
		var y0: float = base_y + k * (panel_height + gap)
		var y1: float = y0 + panel_height

		_face_vertical(accumulator, SLOT_DOOR, material, origin, along, normal, s0, s1, slab_out, y0, y1, 1.0)

		if k > 0:
			_face_horizontal(accumulator, SLOT_DOOR, material, origin, along, normal, s0, s1, slab_in, slab_out, y0, false)
		if k < count - 1:
			_face_horizontal(accumulator, SLOT_DOOR, material, origin, along, normal, s0, s1, slab_in, slab_out, y1, true)
			_face_vertical(accumulator, SLOT_DOOR, material, origin, along, normal, s0, s1, slab_in, y1, y1 + gap, 1.0)


static func _face_vertical(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	origin: Vector2, along: Vector2, normal: Vector2,
	s0: float, s1: float, depth: float, y0: float, y1: float, facing: float,
	visibility: int = SurfaceAccumulator.Visibility.EXTERIOR
) -> void:
	var p0: Vector2 = origin + along * s0 + normal * depth
	var p1: Vector2 = origin + along * s1 + normal * depth
	var run: float = s1 - s0
	var rise: float = y1 - y0
	PlanPolygon.oriented_quad(
		accumulator, slot, material,
		Vector3(p0.x, y0, p0.y), Vector3(p1.x, y0, p1.y),
		Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y),
		Vector3(normal.x * facing, 0.0, normal.y * facing),
		Vector2(0, rise), Vector2(run, rise), Vector2(run, 0), Vector2(0, 0),
		visibility
	)


static func _face_horizontal(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	origin: Vector2, along: Vector2, normal: Vector2,
	s0: float, s1: float, d0: float, d1: float, y: float, facing_up: bool
) -> void:
	var run: float = s1 - s0
	var depth: float = d1 - d0
	var a: Vector2 = origin + along * s0 + normal * d0
	var b: Vector2 = origin + along * s1 + normal * d0
	var c: Vector2 = origin + along * s1 + normal * d1
	var d: Vector2 = origin + along * s0 + normal * d1
	PlanPolygon.oriented_quad(
		accumulator, slot, material,
		Vector3(a.x, y, a.y), Vector3(b.x, y, b.y),
		Vector3(c.x, y, c.y), Vector3(d.x, y, d.y),
		Vector3.UP if facing_up else Vector3.DOWN,
		Vector2(0, 0), Vector2(run, 0), Vector2(run, depth), Vector2(0, depth)
	)


static func _box(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	origin: Vector2, along: Vector2, normal: Vector2,
	s0: float, s1: float, d0: float, d1: float, y0: float, y1: float,
	interior_faces: int = 0
) -> void:
	var p0: Vector2 = origin + along * s0 + normal * d0
	var p1: Vector2 = origin + along * s1 + normal * d1
	BoxBuilder.build(accumulator, slot, material, p0, p1, y0, y1, 0, interior_faces)
