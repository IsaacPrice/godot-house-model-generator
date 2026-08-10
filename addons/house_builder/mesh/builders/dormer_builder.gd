@tool
class_name DormerBuilder
extends RefCounted


const SLOT_SIDING := "siding"
const SLOT_ROOF := "roof"
const SLOT_UNDERLAYMENT := "roof_underlayment"
const SLOT_TRIM := "trim"


static func build(house: HouseData, floor_data: FloorData, roof_models: Array[Dictionary], accumulator: SurfaceAccumulator) -> void:
	if floor_data.dormers.is_empty():
		return
	if house.roof_pitch_degrees < DetailConstants.DORMER_MIN_PITCH_DEGREES:
		push_warning("House builder: dormers skipped - the roof pitch (%.1f°) is below the %.1f° minimum." % [house.roof_pitch_degrees, DetailConstants.DORMER_MIN_PITCH_DEGREES])
		return

	for dormer in floor_data.dormers:
		if not DetailRules.dormer_edge_valid(dormer, floor_data):
			push_warning("House builder: skipping dormer at %s - its edge is not on the floor boundary." % dormer.cell)
			continue
		_build_one(house, dormer, roof_models, accumulator)


static func _build_one(house: HouseData, dormer: DormerData, roof_models: Array[Dictionary], accumulator: SurfaceAccumulator) -> void:
	var normal: Vector2 = WallDetail.NORMALS[dormer.direction]
	var along: Vector2 = Vector2(-normal.y, normal.x)
	var inward: Vector2 = -normal
	var half_thickness: float = house.wall_thickness * 0.5

	var spanned: Array[Vector2i] = dormer.spanned_cells()
	var first_edge: PackedVector2Array = WallDetail.endpoints(spanned[0], dormer.direction, house.level_cell_size)
	var last_edge: PackedVector2Array = WallDetail.endpoints(spanned[spanned.size() - 1], dormer.direction, house.level_cell_size)
	var wall_face_mid: Vector2 = (first_edge[0] + last_edge[1]) * 0.5 + normal * half_thickness
	var front_center: Vector2 = wall_face_mid + inward * dormer.up_slope_offset

	var roof_y: float = RoofSurface.height_at(roof_models, front_center)
	if roof_y == -INF:
		push_warning("House builder: skipping dormer at %s - no roof surface above its front face." % dormer.cell)
		return

	var pitch: float = deg_to_rad(minf(house.roof_pitch_degrees, RoofConstants.MAX_PITCH_DEGREES))
	var tan_pitch: float = tan(pitch)
	var half_width: float = dormer.width * 0.5
	var base_y: float = roof_y - DetailConstants.DORMER_EMBED
	var eave_y: float = base_y + dormer.face_height
	var ridge_y: float = eave_y + half_width * tan_pitch

	var depth: float = minf(
		(ridge_y - roof_y) / tan_pitch + DetailConstants.DORMER_BACK_EXTRA,
		DetailConstants.DORMER_MAX_DEPTH
	)

	var a: Vector2 = front_center - along * half_width
	var b: Vector2 = front_center + along * half_width
	var a_back: Vector2 = a + inward * depth
	var b_back: Vector2 = b + inward * depth

	var openings: Array[Dictionary] = []
	var window: Dictionary = _window_opening(house, dormer, front_center, along, normal, base_y)
	if not window.is_empty():
		openings.append(window)
	PerforatedRing.build_segment(accumulator, SLOT_SIDING, house.siding_material, a, b, normal, half_thickness, base_y, eave_y, openings)
	if not window.is_empty():
		WindowBuilder.build(house, window, accumulator)

	var a_out: Vector2 = a + normal * half_thickness
	var b_out: Vector2 = b + normal * half_thickness
	var apex_out: Vector2 = front_center + normal * half_thickness
	_gable_triangle(accumulator, house, a_out, b_out, apex_out, eave_y, ridge_y, normal, dormer.width)
	var a_in: Vector2 = a - normal * half_thickness
	var b_in: Vector2 = b - normal * half_thickness
	var apex_in: Vector2 = front_center - normal * half_thickness
	_gable_triangle(accumulator, house, b_in, a_in, apex_in, eave_y, ridge_y, -normal, dormer.width)

	PlanPolygon.oriented_quad(
		accumulator, SLOT_SIDING, house.siding_material,
		Vector3(a.x, base_y, a.y), Vector3(a.x, eave_y, a.y),
		Vector3(a_back.x, eave_y, a_back.y), Vector3(a_back.x, base_y, a_back.y),
		Vector3(-along.x, 0, -along.y),
		Vector2(0, dormer.face_height), Vector2(0, 0), Vector2(depth, 0), Vector2(depth, dormer.face_height)
	)
	PlanPolygon.oriented_quad(
		accumulator, SLOT_SIDING, house.siding_material,
		Vector3(b.x, base_y, b.y), Vector3(b.x, eave_y, b.y),
		Vector3(b_back.x, eave_y, b_back.y), Vector3(b_back.x, base_y, b_back.y),
		Vector3(along.x, 0, along.y),
		Vector2(0, dormer.face_height), Vector2(0, 0), Vector2(depth, 0), Vector2(depth, dormer.face_height)
	)
	PlanPolygon.oriented_quad(
		accumulator, SLOT_SIDING, house.siding_material,
		Vector3(a_back.x, base_y, a_back.y), Vector3(a_back.x, ridge_y, a_back.y),
		Vector3(b_back.x, ridge_y, b_back.y), Vector3(b_back.x, base_y, b_back.y),
		Vector3(inward.x, 0, inward.y),
		Vector2(0, ridge_y - base_y), Vector2(0, 0), Vector2(dormer.width, 0), Vector2(dormer.width, ridge_y - base_y)
	)

	_emit_roof(house, accumulator, dormer, front_center, along, inward, normal, half_thickness, depth, ridge_y, pitch)


static func _window_opening(house: HouseData, dormer: DormerData, front_center: Vector2, along: Vector2, normal: Vector2, base_y: float) -> Dictionary:
	var style_defaults: WallDetail = WallDetail.create(WallDetail.DetailType.WINDOW, dormer.window_style, house)
	var width: float = minf(style_defaults.width, dormer.width - 2.0 * DetailConstants.OPENING_EDGE_MARGIN)
	var sill_min: float = DetailConstants.DORMER_EMBED + DetailConstants.DORMER_SILL_CLEARANCE
	var available: float = dormer.face_height - sill_min - DetailConstants.HEADER_MIN
	var height: float = minf(style_defaults.height, available)
	if width < 0.2 or height < 0.2:
		return {}
	var sill: float = clampf(style_defaults.sill_height, sill_min, dormer.face_height - DetailConstants.HEADER_MIN - height)

	return {
		"detail": style_defaults,
		"a": front_center - along * (width * 0.5),
		"b": front_center + along * (width * 0.5),
		"normal": normal,
		"bottom_y": base_y + sill,
		"top_y": base_y + sill + height,
	}


static func _gable_triangle(
	accumulator: SurfaceAccumulator, house: HouseData,
	left: Vector2, right: Vector2, apex: Vector2, eave_y: float, ridge_y: float,
	normal: Vector2, width: float
) -> void:
	var points := PackedVector3Array([
		Vector3(left.x, eave_y, left.y),
		Vector3(apex.x, ridge_y, apex.y),
		Vector3(right.x, eave_y, right.y),
	])
	var uvs := PackedVector2Array([
		Vector2(0, ridge_y - eave_y), Vector2(width * 0.5, 0), Vector2(width, ridge_y - eave_y),
	])
	var normal3 := Vector3(normal.x, 0, normal.y)
	var geometric: Vector3 = (points[2] - points[0]).cross(points[1] - points[0])
	if geometric.dot(normal3) > 0.0:
		points.reverse()
		uvs.reverse()
	accumulator.add_polygon(SLOT_SIDING, house.siding_material, points, normal3, uvs)


static func _emit_roof(
	house: HouseData, accumulator: SurfaceAccumulator, dormer: DormerData,
	front_center: Vector2, along: Vector2, inward: Vector2, normal: Vector2,
	half_thickness: float, depth: float, ridge_y: float, pitch: float
) -> void:
	var overhang: float = DetailConstants.DORMER_ROOF_OVERHANG
	var eave_half: float = dormer.width * 0.5 + overhang
	var eave_drop: float = eave_half * tan(pitch)
	var eave_y: float = ridge_y - eave_drop
	var ridge_front: Vector2 = front_center + normal * (half_thickness + overhang)
	var ridge_back: Vector2 = front_center + inward * depth
	var along3 := Vector3(along.x, 0, along.y)
	var cos_pitch: float = cos(pitch)
	var sin_pitch: float = sin(pitch)
	var slope_len: float = eave_half / cos_pitch
	var plan_len: float = ridge_front.distance_to(ridge_back)
	var thickness: float = DetailConstants.DORMER_ROOF_THICKNESS

	for side in [-1.0, 1.0]:
		var side_offset: Vector2 = along * (eave_half * side)
		var plane_normal: Vector3 = Vector3.UP * cos_pitch - along3 * side * sin_pitch

		var top_points := PackedVector3Array([
			Vector3(ridge_front.x, ridge_y, ridge_front.y),
			Vector3(ridge_back.x, ridge_y, ridge_back.y),
			Vector3(ridge_back.x + side_offset.x, eave_y, ridge_back.y + side_offset.y),
			Vector3(ridge_front.x + side_offset.x, eave_y, ridge_front.y + side_offset.y),
		])
		var uvs := PackedVector2Array([
			Vector2(0, 0), Vector2(plan_len, 0), Vector2(plan_len, slope_len), Vector2(0, slope_len),
		])
		for k in range(uvs.size()):
			uvs[k] *= house.roof_uv_scale
		PlanPolygon.emit(accumulator, SLOT_ROOF, house.roofing_shingles_material, top_points, uvs, plane_normal)

		var bottom_points := PackedVector3Array()
		for p in top_points:
			bottom_points.append(p - Vector3(0, thickness, 0))
		PlanPolygon.emit(accumulator, SLOT_UNDERLAYMENT, house.roof_underlayment_material, bottom_points, uvs, -plane_normal)

		var front_hi: Vector3 = top_points[0]
		var front_lo: Vector3 = top_points[3]
		PlanPolygon.oriented_quad(
			accumulator, SLOT_TRIM, house.trim_material,
			front_hi - Vector3(0, DetailConstants.DORMER_FASCIA, 0), front_hi, front_lo, front_lo - Vector3(0, DetailConstants.DORMER_FASCIA, 0),
			Vector3(normal.x, 0, normal.y),
			Vector2(0, DetailConstants.DORMER_FASCIA), Vector2(0, 0), Vector2(slope_len, 0), Vector2(slope_len, DetailConstants.DORMER_FASCIA)
		)

		var eave_front: Vector3 = top_points[3]
		var eave_back: Vector3 = top_points[2]
		PlanPolygon.oriented_quad(
			accumulator, SLOT_TRIM, house.trim_material,
			eave_front - Vector3(0, DetailConstants.DORMER_FASCIA, 0), eave_front, eave_back, eave_back - Vector3(0, DetailConstants.DORMER_FASCIA, 0),
			along3 * side,
			Vector2(0, DetailConstants.DORMER_FASCIA), Vector2(0, 0), Vector2(plan_len, 0), Vector2(plan_len, DetailConstants.DORMER_FASCIA)
		)
