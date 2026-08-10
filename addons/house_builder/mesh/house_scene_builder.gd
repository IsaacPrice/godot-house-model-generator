@tool
class_name HouseSceneBuilder
extends RefCounted


const RUNTIME_SCRIPT := preload("res://addons/house_builder/runtime/house_window_lights.gd")

const GLASS_SURFACE_NAME := "glass"


static func build(house: HouseData) -> Node3D:
	var building := Node3D.new()
	building.name = "House"

	var built: Dictionary = HouseMeshBuilder.build_with_roof_models(house)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "HouseMesh"
	mesh_instance.mesh = built["mesh"]
	building.add_child(mesh_instance)
	mesh_instance.owner = building

	var sidewalk_instance: MeshInstance3D = null
	var sidewalk_mesh: ArrayMesh = SidewalkBuilder.build(house)
	if sidewalk_mesh != null and sidewalk_mesh.get_surface_count() > 0:
		sidewalk_instance = MeshInstance3D.new()
		sidewalk_instance.name = "SidewalkMesh"
		sidewalk_instance.mesh = sidewalk_mesh
		building.add_child(sidewalk_instance)
		sidewalk_instance.owner = building

	var static_body := StaticBody3D.new()
	static_body.name = "StaticBody3D"
	building.add_child(static_body)
	static_body.owner = building

	var shape_entries: Array[Dictionary] = HouseCollisionBuilder.build(house, built["roof_models"])
	for i in range(shape_entries.size()):
		var entry: Dictionary = shape_entries[i]
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "%s_%d" % [entry["name"], i]
		collision_shape.shape = entry["shape"]
		collision_shape.transform = entry["transform"]
		static_body.add_child(collision_shape)
		collision_shape.owner = building

	if house.window_glow_enabled and _has_glass(mesh_instance.mesh):
		building.set_script(RUNTIME_SCRIPT)
		building.set("lit_glass_material", _lit_material(house))

	var aabb: AABB = mesh_instance.mesh.get_aabb()
	var center := Vector3(aabb.position.x + aabb.size.x * 0.5, 0.0, aabb.position.z + aabb.size.z * 0.5)
	mesh_instance.position = -center
	static_body.position = -center
	if sidewalk_instance != null:
		sidewalk_instance.position = -center

	return building


static func _has_glass(mesh: ArrayMesh) -> bool:
	for i in range(mesh.get_surface_count()):
		if mesh.surface_get_name(i) == GLASS_SURFACE_NAME:
			return true
	return false


static func _lit_material(house: HouseData) -> Material:
	if house.lit_glass_material != null:
		return house.lit_glass_material

	if house.glass_material is BaseMaterial3D:
		var lit: BaseMaterial3D = house.glass_material.duplicate() as BaseMaterial3D
		lit.emission_enabled = true
		lit.emission = house.window_glow_color
		lit.emission_energy_multiplier = house.window_glow_energy
		return lit

	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(0.1, 0.1, 0.1)
	lit.emission_enabled = true
	lit.emission = house.window_glow_color
	lit.emission_energy_multiplier = house.window_glow_energy
	return lit
