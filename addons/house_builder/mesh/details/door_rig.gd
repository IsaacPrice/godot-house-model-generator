@tool
class_name DoorRig
extends RefCounted


const GARAGE_TILT_DEGREES := 90.0


static func leaf_span(house: HouseData, opening: Dictionary) -> Dictionary:
	var frame: float = DetailConstants.FRAME_WIDTH
	var width: float = (opening["a"] as Vector2).distance_to(opening["b"])
	var half_thickness: float = house.wall_thickness * 0.5
	var slab_out: float = half_thickness - DetailConstants.DOOR_SLAB_INSET
	return {
		"s0": frame,
		"s1": width - frame,
		"base_y": opening["bottom_y"],
		"head_y": (opening["top_y"] as float) - frame,
		"depth": slab_out - DetailConstants.DOOR_SLAB_THICKNESS * 0.5,
		"thickness": DetailConstants.DOOR_SLAB_THICKNESS,
	}


static func build(house: HouseData, opening: Dictionary, index: int) -> Dictionary:
	var detail: WallDetail = opening["detail"]
	var span: Dictionary = leaf_span(house, opening)
	var leaf_width: float = span["s1"] - span["s0"]
	var leaf_height: float = span["head_y"] - span["base_y"]
	if leaf_width <= 0.0 or leaf_height <= 0.0:
		return {}

	var a: Vector2 = opening["a"]
	var along: Vector2 = (opening["b"] as Vector2 - a).normalized()
	var normal: Vector2 = opening["normal"]
	var is_garage: bool = detail.type == WallDetail.DetailType.GARAGE_DOOR

	var accumulator := SurfaceAccumulator.new()
	if is_garage:
		GarageDoorBuilder.build_leaf(house, opening, accumulator)
	else:
		DoorBuilder.build_leaf(house, opening, accumulator)
	var mesh: ArrayMesh = accumulator.commit()
	if mesh.get_surface_count() == 0:
		return {}

	var hinge_s: float = leaf_width * 0.5 + span["s0"] if is_garage else span["s0"]
	var hinge_y: float = span["head_y"] if is_garage else span["base_y"]
	var hinge: Vector2 = a + along * hinge_s + normal * span["depth"]

	var basis := Basis(
		Vector3(along.x, 0.0, along.y),
		Vector3.UP,
		Vector3(-normal.x, 0.0, -normal.y))
	var pivot := Transform3D(basis, Vector3(hinge.x, hinge_y, hinge.y))

	var open_rotation: Vector3
	var shape_center: Vector3
	if is_garage:
		open_rotation = Vector3(-deg_to_rad(GARAGE_TILT_DEGREES), 0.0, 0.0)
		shape_center = Vector3(0.0, -leaf_height * 0.5, 0.0)
	else:
		open_rotation = Vector3(0.0, -deg_to_rad(house.door_swing_degrees), 0.0)
		shape_center = Vector3(leaf_width * 0.5, leaf_height * 0.5, 0.0)

	return {
		"name": "%s_%d" % ["GarageDoor" if is_garage else "Door", index],
		"mesh": mesh,
		"transform": pivot,
		"open_rotation": open_rotation,
		"starts_open": detail.starts_open,
		"shape_size": Vector3(leaf_width, leaf_height, span["thickness"]),
		"shape_center": shape_center,
	}
