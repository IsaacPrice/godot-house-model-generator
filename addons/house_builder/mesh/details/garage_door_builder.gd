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

	_box(accumulator, SLOT_CASING, house.window_frame_material, a, along, normal, 0.0, frame, depth_in, depth_out, bottom_y, top_y)
	_box(accumulator, SLOT_CASING, house.window_frame_material, a, along, normal, width - frame, width, depth_in, depth_out, bottom_y, top_y)
	_box(accumulator, SLOT_CASING, house.window_frame_material, a, along, normal, frame, width - frame, depth_in, depth_out, top_y - frame, top_y)

	var slab_out: float = half_thickness - DetailConstants.DOOR_SLAB_INSET
	var slab_in: float = slab_out - DetailConstants.DOOR_SLAB_THICKNESS
	var count: int = DetailConstants.GARAGE_PANEL_COUNT
	var gap: float = DetailConstants.GARAGE_PANEL_GAP
	var area_height: float = top_y - frame - bottom_y
	var panel_height: float = (area_height - (count - 1) * gap) / count

	for k in range(count):
		var y0: float = bottom_y + k * (panel_height + gap)
		_box(
			accumulator, SLOT_DOOR, house.garage_door_material, a, along, normal,
			frame, width - frame, slab_in, slab_out, y0, y0 + panel_height
		)


static func _box(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	origin: Vector2, along: Vector2, normal: Vector2,
	s0: float, s1: float, d0: float, d1: float, y0: float, y1: float
) -> void:
	var p0: Vector2 = origin + along * s0 + normal * d0
	var p1: Vector2 = origin + along * s1 + normal * d1
	BoxBuilder.build(accumulator, slot, material, p0, p1, y0, y1)
