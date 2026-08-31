@tool
class_name WindowBuilder
extends RefCounted


const SLOT_FRAME := "window_frame"
const SLOT_GLASS := "glass"


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
	var frame_material: Material = house.window_frame_material

	var lining: int = BoxBuilder.Face.TOP | BoxBuilder.Face.BOTTOM
	var jamb_ends: int = BoxBuilder.face_toward(along) | BoxBuilder.face_toward(-along)
	var inward: int = BoxBuilder.face_toward(-normal)

	_box(accumulator, frame_material, a, along, normal, 0.0, frame, depth_in, depth_out, bottom_y, top_y, BoxBuilder.Face.BOTTOM, inward)
	_box(accumulator, frame_material, a, along, normal, width - frame, width, depth_in, depth_out, bottom_y, top_y, BoxBuilder.Face.BOTTOM, inward)
	_box(accumulator, frame_material, a, along, normal, frame, width - frame, depth_in, depth_out, top_y - frame, top_y, jamb_ends, inward)
	_box(accumulator, frame_material, a, along, normal, frame, width - frame, depth_in, depth_out, bottom_y, bottom_y + frame, BoxBuilder.Face.BOTTOM | jamb_ends, inward)

	_box(
		accumulator, frame_material, a, along, normal,
		-DetailConstants.SILL_SIDE_EXTEND, width + DetailConstants.SILL_SIDE_EXTEND,
		0.0, depth_out + DetailConstants.SILL_PROJECTION,
		bottom_y - DetailConstants.SILL_THICKNESS, bottom_y,
		inward
	)

	var glass_a: Vector2 = a + along * frame
	var glass_b: Vector2 = a + along * (width - frame)
	var glass_bottom: float = bottom_y + frame
	var glass_top: float = top_y - frame
	_pane(accumulator, house.glass_material, glass_a, glass_b, normal, glass_bottom, glass_top)

	var glass_width: float = width - 2.0 * frame
	var half_bar: float = DetailConstants.MUNTIN_WIDTH * 0.5
	var bar_out: float = DetailConstants.MUNTIN_DEPTH
	match opening["detail"].style:
		WallDetail.WindowStyle.SINGLE:
			var mid_y: float = (glass_bottom + glass_top) * 0.5
			_box(accumulator, frame_material, a, along, normal, frame, width - frame, -bar_out, bar_out, mid_y - half_bar, mid_y + half_bar, jamb_ends, inward)
		WallDetail.WindowStyle.WIDE:
			var mid_y: float = (glass_bottom + glass_top) * 0.5
			_box(accumulator, frame_material, a, along, normal, frame, width - frame, -bar_out, bar_out, mid_y - half_bar, mid_y + half_bar, jamb_ends, inward)
			for third in [1.0, 2.0]:
				var s: float = frame + glass_width * third / 3.0
				_box(accumulator, frame_material, a, along, normal, s - half_bar, s + half_bar, -bar_out, bar_out, glass_bottom, glass_top, lining, inward)


static func _box(
	accumulator: SurfaceAccumulator, material: Material,
	origin: Vector2, along: Vector2, normal: Vector2,
	s0: float, s1: float, d0: float, d1: float, y0: float, y1: float,
	buried_faces: int = 0, interior_faces: int = 0,
	slot: String = SLOT_FRAME
) -> void:
	var p0: Vector2 = origin + along * s0 + normal * d0
	var p1: Vector2 = origin + along * s1 + normal * d1
	BoxBuilder.build(accumulator, slot, material, p0, p1, y0, y1, buried_faces, interior_faces)


static func _pane(
	accumulator: SurfaceAccumulator, material: Material,
	a: Vector2, b: Vector2, normal: Vector2, y0: float, y1: float
) -> void:
	var width: float = a.distance_to(b)
	var height: float = y1 - y0
	var half: float = DetailConstants.GLASS_THICKNESS * 0.5
	var a_out: Vector2 = a + normal * half
	var b_out: Vector2 = b + normal * half
	var a_in: Vector2 = a - normal * half
	var b_in: Vector2 = b - normal * half
	accumulator.add_quad(
		SLOT_GLASS, material,
		Vector3(a_out.x, y0, a_out.y),
		Vector3(a_out.x, y1, a_out.y),
		Vector3(b_out.x, y1, b_out.y),
		Vector3(b_out.x, y0, b_out.y),
		Vector3(normal.x, 0, normal.y),
		Vector2(0, height), Vector2(0, 0), Vector2(width, 0), Vector2(width, height)
	)
	accumulator.add_quad(
		SLOT_GLASS, material,
		Vector3(b_in.x, y0, b_in.y),
		Vector3(b_in.x, y1, b_in.y),
		Vector3(a_in.x, y1, a_in.y),
		Vector3(a_in.x, y0, a_in.y),
		Vector3(-normal.x, 0, -normal.y),
		Vector2(width, height), Vector2(width, 0), Vector2(0, 0), Vector2(0, height),
		SurfaceAccumulator.Visibility.INTERIOR
	)
