@tool
class_name HouseWindowLights
extends Node3D


const LIGHTS_NODE_NAME := "WindowLights"
const GLASS_SURFACE_NAME := "glass"

## The real-time switch: regular glass with the lights hidden, or lit glass
## plus visible AreaLight3Ds. Togglable from the editor inspector (@tool)
## and at runtime.
@export var windows_lit: bool = false:
	set(value):
		windows_lit = value
		if is_node_ready():
			_apply()

## Optional material overriding the "glass" surface while lit (typically an
## emissive variant of the regular glass). Populated from
## HouseData.lit_glass_material at export.
@export var lit_glass_material: Material


func set_windows_lit(lit: bool) -> void:
	windows_lit = lit


func _ready() -> void:
	_apply()


func _apply() -> void:
	var lights: Node = get_node_or_null(NodePath(LIGHTS_NODE_NAME))
	if lights != null:
		for child in lights.get_children():
			if child is Node3D:
				child.visible = windows_lit

	var mesh_instance: MeshInstance3D = _find_mesh_instance()
	if mesh_instance == null:
		return
	var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
	if mesh == null:
		return
	var surface: int = _find_glass_surface(mesh)
	if surface < 0:
		return
	mesh_instance.set_surface_override_material(
		surface, lit_glass_material if windows_lit else null
	)


static func _find_glass_surface(mesh: ArrayMesh) -> int:
	for i in range(mesh.get_surface_count()):
		if mesh.surface_get_name(i) == GLASS_SURFACE_NAME:
			return i
	return -1


func _find_mesh_instance() -> MeshInstance3D:
	var named := get_node_or_null(^"HouseMesh") as MeshInstance3D
	if named != null:
		return named
	named = get_node_or_null(^"MeshInstance3D") as MeshInstance3D
	if named != null:
		return named
	for child in get_children():
		if child is MeshInstance3D:
			return child
	return null
