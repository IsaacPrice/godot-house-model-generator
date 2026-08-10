extends SceneTree


const EPS := 1e-3

var failures: int = 0


func _init() -> void:
	_test_combined_roundtrip()
	_test_legacy_tres_conversion()
	_test_not_a_house_scene()

	if failures == 0:
		print("ALL HOUSE FILE TESTS PASSED")
		quit(0)
	else:
		print("%d HOUSE FILE TEST FAILURE(S)" % failures)
		quit(1)


func _build_house() -> HouseData:
	var house := HouseData.new()
	house.porch_railing_style = HouseData.RailingStyle.CROSS
	house.roof_pitch_degrees = 42.0
	house.sidewalk_drop = 0.65
	house.foundation_mode = HouseData.FoundationMode.LOWER
	house.sidewalk_expand = 0.35

	var floor_data := FloorData.new()
	floor_data.level = 0
	floor_data.height = 3.0
	for x in range(3):
		floor_data.add_cell(Vector2i(x, 0))
	floor_data.add_porch_cell(Vector2i(0, 1))
	floor_data.add_sidewalk_cell(Vector2i(1, 1))
	floor_data.add_sidewalk_cell(Vector2i(2, 1))

	var window := WallDetail.create(WallDetail.DetailType.WINDOW, WallDetail.WindowStyle.WIDE)
	window.cell = Vector2i(0, 0)
	window.direction = WallDetail.EdgeDir.NORTH
	floor_data.set_wall_detail(window)

	var door := WallDetail.create(WallDetail.DetailType.DOOR)
	door.cell = Vector2i(1, 0)
	door.direction = WallDetail.EdgeDir.SOUTH
	floor_data.set_wall_detail(door)

	house.add_floor(floor_data)
	return house


func _check_loaded_matches(group: String, loaded: HouseData, original: HouseData) -> void:
	_check(group, "loaded house is HouseData", loaded != null)
	if loaded == null:
		return
	_check(group, "loaded house is a fresh instance", loaded != original)
	_check(group, "railing style preserved", loaded.porch_railing_style == HouseData.RailingStyle.CROSS)
	_check(group, "roof pitch preserved", absf(loaded.roof_pitch_degrees - 42.0) < EPS)
	_check(group, "floor count preserved", loaded.floors.size() == original.floors.size())
	if loaded.floors.size() == 0:
		return
	_check(group, "sidewalk drop preserved", absf(loaded.sidewalk_drop - 0.65) < EPS)
	_check(group, "foundation mode preserved", loaded.foundation_mode == HouseData.FoundationMode.LOWER)
	_check(group, "sidewalk expand preserved", absf(loaded.sidewalk_expand - 0.35) < EPS)
	var floor_data: FloorData = loaded.floors[0]
	_check(group, "cells preserved", floor_data.cells == original.floors[0].cells)
	_check(group, "porch cells preserved", floor_data.porch_cells == original.floors[0].porch_cells)
	_check(group, "sidewalk cells preserved", floor_data.sidewalk_cells == original.floors[0].sidewalk_cells)
	_check(group, "wall detail count preserved", floor_data.wall_details.size() == 2)
	var window: WallDetail = floor_data.get_wall_detail(Vector2i(0, 0), WallDetail.EdgeDir.NORTH)
	_check(group, "window style preserved", window != null and window.style == WallDetail.WindowStyle.WIDE)


func _test_combined_roundtrip() -> void:
	var house := _build_house()

	var material := StandardMaterial3D.new()
	var material_path := "user://house_file_test_mat.tres"
	_check("combined", "material saved", ResourceSaver.save(material, material_path) == OK)
	house.siding_material = ResourceLoader.load(material_path)

	var path_a := "user://house_file_test_a.tscn"
	_check("combined", "save succeeded", HouseFile.save_house(house, path_a) == OK)

	var text := FileAccess.get_file_as_string(path_a)
	_check("combined", "house data embedded (script sub_resource present)", text.contains("house_data.gd"))
	_check("combined", "root carries house_data metadata", text.contains("metadata/house_data"))
	_check("combined", "material stayed an external reference", text.contains("house_file_test_mat.tres"))
	_check("combined", "in-memory material path untouched", house.siding_material.resource_path == material_path)

	var loaded: HouseData = HouseFile.load_any(path_a)
	_check_loaded_matches("combined", loaded, house)
	if loaded == null:
		return

	var packed: PackedScene = ResourceLoader.load(path_a, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var building: Node3D = packed.instantiate()
	var mesh_instance: MeshInstance3D = building.get_node_or_null("HouseMesh")
	_check("combined", "scene has a mesh", mesh_instance != null and mesh_instance.mesh.get_surface_count() > 0)
	_check("combined", "scene has the separate sidewalk mesh", building.get_node_or_null("SidewalkMesh") != null)
	var static_body: StaticBody3D = building.get_node_or_null("StaticBody3D")
	_check("combined", "scene has collision shapes", static_body != null and static_body.get_child_count() > 0)
	building.free()

	var path_b := "user://house_file_test_b.tscn"
	_check("combined", "re-save of loaded house succeeded", HouseFile.save_house(loaded, path_b) == OK)
	var text_b := FileAccess.get_file_as_string(path_b)
	_check("combined", "re-save embeds data, not a reference to the first file", not text_b.contains("house_file_test_a.tscn"))
	_check_loaded_matches("combined re-load", HouseFile.load_any(path_b), house)


func _test_legacy_tres_conversion() -> void:
	var house := _build_house()
	var legacy_path := "user://house_file_test_legacy.tres"
	_check("legacy", "legacy save succeeded", ResourceSaver.save(house, legacy_path) == OK)

	var loaded: HouseData = HouseFile.load_any(legacy_path)
	_check_loaded_matches("legacy", loaded, house)
	if loaded == null:
		return

	var combined_path := "user://house_file_test_converted.tscn"
	_check("legacy", "conversion save succeeded", HouseFile.save_house(loaded, combined_path) == OK)
	var text := FileAccess.get_file_as_string(combined_path)
	_check("legacy", "converted file does not reference the legacy .tres", not text.contains("house_file_test_legacy.tres"))
	_check_loaded_matches("legacy re-load", HouseFile.load_any(combined_path), house)


func _test_not_a_house_scene() -> void:
	var node := Node3D.new()
	var packed := PackedScene.new()
	packed.pack(node)
	node.free()
	var path := "user://house_file_test_plain.tscn"
	ResourceSaver.save(packed, path)
	_check("reject", "plain scene loads as null", HouseFile.load_any(path) == null)


func _check(group: String, name: String, condition: bool) -> void:
	if condition:
		print("PASS [%s] %s" % [group, name])
	else:
		failures += 1
		printerr("FAIL [%s] %s" % [group, name])
