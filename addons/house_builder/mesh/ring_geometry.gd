@tool
class_name RingGeometry
extends RefCounted

static func build(
	accumulator: SurfaceAccumulator, slot: String, material: Material, loop: BoundaryLoop,
	inward: float, outward: float, base_y: float, top_y: float,
	cap_bottom: bool = true, cap_top: bool = true,
	inner_visibility: int = SurfaceAccumulator.Visibility.EXTERIOR,
	cap_top_visibility: int = SurfaceAccumulator.Visibility.EXTERIOR,
	cap_bottom_visibility: int = SurfaceAccumulator.Visibility.EXTERIOR,
	inner_slot: String = "", inner_material: Material = null
) -> void:
	var n: int = loop.size()
	if n < 3:
		return

	if inner_slot.is_empty():
		inner_slot = slot
		inner_material = material

	var outer: PackedVector2Array = PackedVector2Array()
	var inner: PackedVector2Array = PackedVector2Array()
	for i in range(n):
		outer.append(loop.corner_offset(i, outward))
		inner.append(loop.corner_offset(i, -inward))

	var height: float = top_y - base_y

	for i in range(n):
		var j: int = (i + 1) % n
		var normal3 := Vector3(loop.normals[i].x, 0, loop.normals[i].y)

		var outer_len: float = outer[i].distance_to(outer[j])
		accumulator.add_quad(
			slot, material,
			Vector3(outer[i].x, base_y, outer[i].y),
			Vector3(outer[i].x, top_y, outer[i].y),
			Vector3(outer[j].x, top_y, outer[j].y),
			Vector3(outer[j].x, base_y, outer[j].y),
			normal3,
			Vector2(0, height), Vector2(0, 0), Vector2(outer_len, 0), Vector2(outer_len, height)
		)

		var inner_len: float = inner[i].distance_to(inner[j])
		accumulator.add_quad(
			inner_slot, inner_material,
			Vector3(inner[j].x, base_y, inner[j].y),
			Vector3(inner[j].x, top_y, inner[j].y),
			Vector3(inner[i].x, top_y, inner[i].y),
			Vector3(inner[i].x, base_y, inner[i].y),
			-normal3,
			Vector2(inner_len, height), Vector2(inner_len, 0), Vector2(0, 0), Vector2(0, height),
			inner_visibility
		)

		var ring_width: float = inward + outward

		if cap_top:
			accumulator.add_quad(
				slot, material,
				Vector3(outer[i].x, top_y, outer[i].y),
				Vector3(inner[i].x, top_y, inner[i].y),
				Vector3(inner[j].x, top_y, inner[j].y),
				Vector3(outer[j].x, top_y, outer[j].y),
				Vector3(0, 1, 0),
				Vector2(0, 0), Vector2(0, ring_width), Vector2(outer_len, ring_width), Vector2(outer_len, 0),
				cap_top_visibility
			)

		if cap_bottom:
			accumulator.add_quad(
				slot, material,
				Vector3(outer[j].x, base_y, outer[j].y),
				Vector3(inner[j].x, base_y, inner[j].y),
				Vector3(inner[i].x, base_y, inner[i].y),
				Vector3(outer[i].x, base_y, outer[i].y),
				Vector3(0, -1, 0),
				Vector2(outer_len, 0), Vector2(outer_len, ring_width), Vector2(0, ring_width), Vector2(0, 0),
				cap_bottom_visibility
			)
