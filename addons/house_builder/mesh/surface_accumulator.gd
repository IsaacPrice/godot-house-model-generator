@tool
class_name SurfaceAccumulator
extends RefCounted


var _surface_tools: Dictionary = {}
var _materials: Dictionary = {}


func add_quad(
	slot: String, material: Material,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3,
	uv_a: Vector2 = Vector2(0, 1), uv_b: Vector2 = Vector2(1, 1),
	uv_c: Vector2 = Vector2(1, 0), uv_d: Vector2 = Vector2(0, 0)
) -> void:
	var st: SurfaceTool = _get_tool(slot, material)

	st.set_normal(normal)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_c)
	st.add_vertex(c)
	st.set_uv(uv_b)
	st.add_vertex(b)

	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_d)
	st.add_vertex(d)
	st.set_uv(uv_c)
	st.add_vertex(c)


func add_polygon(
	slot: String, material: Material,
	points: PackedVector3Array, normal: Vector3, uvs: PackedVector2Array
) -> void:
	var st: SurfaceTool = _get_tool(slot, material)
	st.set_normal(normal)
	for i in range(1, points.size() - 1):
		st.set_uv(uvs[0])
		st.add_vertex(points[0])
		st.set_uv(uvs[i + 1])
		st.add_vertex(points[i + 1])
		st.set_uv(uvs[i])
		st.add_vertex(points[i])


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for slot in _surface_tools:
		var st: SurfaceTool = _surface_tools[slot]
		st.index()
		st.generate_tangents()
		var surface_index: int = mesh.get_surface_count()
		mesh = st.commit(mesh)
		mesh.surface_set_name(surface_index, slot)

		var material: Material = _materials[slot]
		if material != null:
			mesh.surface_set_material(surface_index, material)

	return mesh


func _get_tool(slot: String, material: Material) -> SurfaceTool:
	if not _surface_tools.has(slot):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surface_tools[slot] = st
		_materials[slot] = material
	return _surface_tools[slot]
