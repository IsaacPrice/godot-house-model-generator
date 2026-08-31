@tool
class_name DoorBuilder
extends RefCounted


const SLOT_CASING := "window_frame"
const SLOT_DOOR := "door"


static func build(house: HouseData, opening: Dictionary, accumulator: SurfaceAccumulator) -> void:
	_build_casing(house, opening, accumulator)
	if (opening["detail"] as WallDetail).door_mode == WallDetail.DoorMode.STATIC:
		build_leaf(house, opening, accumulator)


static func _build_casing(house: HouseData, opening: Dictionary, accumulator: SurfaceAccumulator) -> void:
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
	_box(accumulator, SLOT_CASING, house.window_frame_material, a, along, normal, 0.0, frame, depth_in, depth_out, bottom_y, top_y, 0, casing_interior)
	_box(accumulator, SLOT_CASING, house.window_frame_material, a, along, normal, width - frame, width, depth_in, depth_out, bottom_y, top_y, 0, casing_interior)
	_box(accumulator, SLOT_CASING, house.window_frame_material, a, along, normal, frame, width - frame, depth_in, depth_out, top_y - frame, top_y, 0, casing_interior)


static func build_leaf(house: HouseData, opening: Dictionary, accumulator: SurfaceAccumulator) -> void:
	var a: Vector2 = opening["a"]
	var along: Vector2 = (opening["b"] as Vector2 - a).normalized()
	var normal: Vector2 = opening["normal"]
	var width: float = a.distance_to(opening["b"])
	var bottom_y: float = opening["bottom_y"]
	var top_y: float = opening["top_y"]

	var frame: float = DetailConstants.FRAME_WIDTH
	var half_thickness: float = house.wall_thickness * 0.5
	var slab_out: float = half_thickness - DetailConstants.DOOR_SLAB_INSET
	var slab_in: float = slab_out - DetailConstants.DOOR_SLAB_THICKNESS
	var buried: int = 0
	var interior: int = 0
	if not (opening["detail"] as WallDetail).is_animated():
		buried = BoxBuilder.face_toward(along) | BoxBuilder.face_toward(-along) | BoxBuilder.Face.TOP
		interior = BoxBuilder.face_toward(-normal)

	_box(
		accumulator, SLOT_DOOR, house.door_material, a, along, normal,
		frame, width - frame, slab_in, slab_out, bottom_y, top_y - frame,
		buried, interior
	)

	if opening["detail"].style == WallDetail.DoorStyle.PANELED:
		_emit_panels(accumulator, house, opening, a, along, normal, frame, width - frame, slab_out, bottom_y, top_y - frame)


static func _emit_panels(
	accumulator: SurfaceAccumulator, house: HouseData, opening: Dictionary,
	a: Vector2, along: Vector2, normal: Vector2,
	s0: float, s1: float, slab_out: float, y0: float, y1: float
) -> void:
	var margin: float = DetailConstants.DOOR_PANEL_MARGIN
	var gap: float = DetailConstants.DOOR_PANEL_GAP
	var panel_width: float = (s1 - s0 - 2.0 * margin - gap) * 0.5
	var panel_height: float = (y1 - y0 - 2.0 * margin - gap) * 0.5
	if panel_width < DetailConstants.DOOR_PANEL_GAP or panel_height < DetailConstants.DOOR_PANEL_GAP:
		return

	var interior: int = 0 if (opening["detail"] as WallDetail).is_animated() else BoxBuilder.face_toward(-normal)

	for column in range(2):
		for row in range(2):
			var ps: float = s0 + margin + column * (panel_width + gap)
			var py: float = y0 + margin + row * (panel_height + gap)
			_box(
				accumulator, SLOT_DOOR, house.door_material, a, along, normal,
				ps, ps + panel_width, slab_out, slab_out + DetailConstants.DOOR_PANEL_RELIEF,
				py, py + panel_height,
				0, interior
			)


static func _box(
	accumulator: SurfaceAccumulator, slot: String, material: Material,
	origin: Vector2, along: Vector2, normal: Vector2,
	s0: float, s1: float, d0: float, d1: float, y0: float, y1: float,
	buried_faces: int = 0, interior_faces: int = 0
) -> void:
	var p0: Vector2 = origin + along * s0 + normal * d0
	var p1: Vector2 = origin + along * s1 + normal * d1
	BoxBuilder.build(accumulator, slot, material, p0, p1, y0, y1, buried_faces, interior_faces)
