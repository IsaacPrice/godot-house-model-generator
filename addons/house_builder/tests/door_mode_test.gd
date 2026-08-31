extends SceneTree


const EPS := 1e-3

const EXPORT_PATH := "user://door_mode_export.tscn"

var failures: int = 0


func _init() -> void:
	_test_none_leaves_an_empty_opening()
	_test_static_bakes_into_the_mesh()
	_test_animated_leaves_the_mesh()
	_test_door_swings_inward()
	_test_garage_tilts_up_and_in()
	_test_starts_open()
	_test_export_roundtrip()
	_test_defaults_follow_the_house()

	if failures == 0:
		print("ALL DOOR MODE TESTS PASSED")
		quit(0)
	else:
		print("%d DOOR MODE TEST FAILURE(S)" % failures)
		quit(1)


func _house(type: int, mode: int, starts_open: bool = false) -> HouseData:
	var house := HouseData.new()
	house.level_cell_size = 2.0
	house.wall_thickness = 0.2

	var floor_data := FloorData.new()
	floor_data.level = 0
	floor_data.height = 3.0
	for x in range(3):
		floor_data.add_cell(Vector2i(x, 0))
		floor_data.add_cell(Vector2i(x, 1))
	house.add_floor(floor_data)

	var detail := WallDetail.create(type, 0, house)
	detail.cell = Vector2i(1, 0)
	detail.direction = WallDetail.EdgeDir.NORTH
	detail.door_mode = mode
	detail.starts_open = starts_open
	floor_data.set_wall_detail(detail)
	return house


func _leaf_slot(type: int) -> String:
	return GarageDoorBuilder.SLOT_DOOR if type == WallDetail.DetailType.GARAGE_DOOR else DoorBuilder.SLOT_DOOR


func _test_none_leaves_an_empty_opening() -> void:
	for type in [WallDetail.DetailType.DOOR, WallDetail.DetailType.GARAGE_DOOR]:
		var house: HouseData = _house(type, WallDetail.DoorMode.NONE)
		var built: Dictionary = HouseMeshBuilder.build_with_roof_models(house)
		var mesh: ArrayMesh = built["mesh"]
		var label: String = WallDetail.DetailType.keys()[type]

		MeshChecks.check_windings("none_%s" % label, mesh, _check)
		_check("none", "%s leaves no leaf" % label, MeshChecks.find_surface(mesh, _leaf_slot(type)) < 0)
		_check("none", "%s keeps its casing" % label, MeshChecks.find_surface(mesh, DoorBuilder.SLOT_CASING) >= 0)
		_check("none", "%s rigs no node" % label, (built["doors"] as Array).is_empty())

		var reveal: float = MeshChecks.facing_area(
			mesh, InteriorBuilder.SLOT_WALL, Vector3(1, 0, 0),
			func(a: Vector3, b: Vector3, c: Vector3) -> bool: return a.z < 0.1 + EPS and a.y < 2.5)
		_check("none", "%s opening is still lined (%.3f)" % [label, reveal], reveal > 0.0)


func _test_static_bakes_into_the_mesh() -> void:
	for type in [WallDetail.DetailType.DOOR, WallDetail.DetailType.GARAGE_DOOR]:
		var house: HouseData = _house(type, WallDetail.DoorMode.STATIC)
		var built: Dictionary = HouseMeshBuilder.build_with_roof_models(house)
		var label: String = WallDetail.DetailType.keys()[type]

		_check("static", "%s leaf is baked in" % label,
			MeshChecks.find_surface(built["mesh"], _leaf_slot(type)) >= 0)
		_check("static", "%s rigs no node" % label, (built["doors"] as Array).is_empty())


func _test_animated_leaves_the_mesh() -> void:
	for type in [WallDetail.DetailType.DOOR, WallDetail.DetailType.GARAGE_DOOR]:
		var house: HouseData = _house(type, WallDetail.DoorMode.ANIMATED)
		var built: Dictionary = HouseMeshBuilder.build_with_roof_models(house)
		var label: String = WallDetail.DetailType.keys()[type]
		var rigs: Array = built["doors"]

		_check("animated", "%s leaf leaves the house mesh" % label,
			MeshChecks.find_surface(built["mesh"], _leaf_slot(type)) < 0)
		_check("animated", "%s produces one rig" % label, rigs.size() == 1)
		if rigs.is_empty():
			continue

		var rig: Dictionary = rigs[0]
		var leaf: ArrayMesh = rig["mesh"]
		_check("animated", "%s rig carries its own mesh" % label,
			MeshChecks.find_surface(leaf, _leaf_slot(type)) >= 0)
		_check("animated", "%s pivot basis is right-handed (%.3f)" % [label, (rig["transform"] as Transform3D).basis.determinant()],
			absf((rig["transform"] as Transform3D).basis.determinant() - 1.0) < EPS)


func _test_door_swings_inward() -> void:
	var house: HouseData = _house(WallDetail.DetailType.DOOR, WallDetail.DoorMode.ANIMATED)
	var rig: Dictionary = (HouseMeshBuilder.build_with_roof_models(house)["doors"] as Array)[0]
	var pivot: Transform3D = rig["transform"]

	var shut: Vector3 = pivot * Vector3((rig["shape_size"] as Vector3).x, 0.0, 0.0)
	var swung: Transform3D = pivot * Transform3D(Basis.from_euler(rig["open_rotation"]), Vector3.ZERO)
	var opened: Vector3 = swung * Vector3((rig["shape_size"] as Vector3).x, 0.0, 0.0)

	_check("swing", "shut leaf lies in the wall (z=%.3f)" % shut.z, absf(shut.z) < 0.15)
	_check("swing", "open leaf swings into the house (z=%.3f)" % opened.z, opened.z > 0.5)
	_check("swing", "hinge end stays put",
		(pivot.origin - swung.origin).length() < EPS)


func _test_garage_tilts_up_and_in() -> void:
	var house: HouseData = _house(WallDetail.DetailType.GARAGE_DOOR, WallDetail.DoorMode.ANIMATED)
	var rig: Dictionary = (HouseMeshBuilder.build_with_roof_models(house)["doors"] as Array)[0]
	var pivot: Transform3D = rig["transform"]
	var height: float = (rig["shape_size"] as Vector3).y

	var shut: Vector3 = pivot * Vector3(0.0, -height, 0.0)
	var swung: Transform3D = pivot * Transform3D(Basis.from_euler(rig["open_rotation"]), Vector3.ZERO)
	var opened: Vector3 = swung * Vector3(0.0, -height, 0.0)

	_check("garage", "shut leaf hangs below the head (%.3f)" % shut.y, shut.y < pivot.origin.y - 1.0)
	_check("garage", "open leaf is level with the head (%.3f)" % opened.y, absf(opened.y - pivot.origin.y) < EPS)
	_check("garage", "open leaf lies inside the garage (z=%.3f)" % opened.z, opened.z > 1.0)


func _test_starts_open() -> void:
	var house: HouseData = _house(WallDetail.DetailType.DOOR, WallDetail.DoorMode.ANIMATED, true)
	var building: Node3D = HouseSceneBuilder.build(house)
	var doors: Node3D = building.get_node_or_null(^"Doors")
	_check("starts_open", "export has a Doors node", doors != null)
	if doors != null:
		var pivot: Node3D = doors.get_child(0)
		_check("starts_open", "pivot is pre-rotated open",
			pivot.rotation.is_equal_approx(pivot.get_meta(HouseDoors.META_OPEN_ROTATION)))
		_check("starts_open", "pivot records its start state", bool(pivot.get_meta(HouseDoors.META_STARTS_OPEN)))
	building.free()


func _test_export_roundtrip() -> void:
	var house: HouseData = _house(WallDetail.DetailType.GARAGE_DOOR, WallDetail.DoorMode.ANIMATED)
	var second := WallDetail.create(WallDetail.DetailType.DOOR, 0, house)
	second.cell = Vector2i(0, 0)
	second.direction = WallDetail.EdgeDir.WEST
	second.door_mode = WallDetail.DoorMode.ANIMATED
	house.floors[0].set_wall_detail(second)

	_check("roundtrip", "saves", HouseFile.save_house(house, EXPORT_PATH) == OK)

	var packed: PackedScene = ResourceLoader.load(EXPORT_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	_check("roundtrip", "loads back as a scene", packed != null)
	if packed == null:
		return

	var building: Node3D = packed.instantiate()
	var doors: Node3D = building.get_node_or_null(^"Doors")
	_check("roundtrip", "Doors node survives packing", doors != null)
	if doors == null:
		building.free()
		return

	_check("roundtrip", "both doors survive", doors.get_child_count() == 2)
	_check("roundtrip", "Doors carries the runtime script", doors is HouseDoors)

	for i in range(doors.get_child_count()):
		var pivot: Node3D = doors.get_child(i)
		_check("roundtrip", "%s keeps its leaf" % pivot.name, pivot.get_node_or_null(^"Leaf") != null)
		_check("roundtrip", "%s keeps its collision" % pivot.name,
			pivot.get_node_or_null(^"StaticBody3D/CollisionShape3D") != null)
		var player: AnimationPlayer = pivot.get_node_or_null(^"AnimationPlayer")
		_check("roundtrip", "%s keeps its animation" % pivot.name,
			player != null and player.has_animation(HouseDoors.ANIMATION_NAME))
		if player != null and player.has_animation(HouseDoors.ANIMATION_NAME):
			var animation: Animation = player.get_animation(HouseDoors.ANIMATION_NAME)
			_check("roundtrip", "%s animation runs the configured duration" % pivot.name,
				absf(animation.length - house.door_open_duration) < EPS)
			_check("roundtrip", "%s animation drives the pivot rotation" % pivot.name,
				animation.get_track_count() == 1 and animation.track_get_path(0) == NodePath(".:rotation"))

	var leaf: MeshInstance3D = doors.get_child(0).get_node(^"Leaf")
	var shut_world: Transform3D = doors.get_child(0).transform * leaf.transform
	_check("roundtrip", "a shut leaf sits where the mesh built it",
		shut_world.is_equal_approx(Transform3D.IDENTITY))

	building.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(EXPORT_PATH))


func _test_defaults_follow_the_house() -> void:
	var house := HouseData.new()
	house.door_default_mode = WallDetail.DoorMode.ANIMATED
	house.garage_door_default_mode = WallDetail.DoorMode.NONE

	var door := WallDetail.create(WallDetail.DetailType.DOOR, 0, house)
	var garage := WallDetail.create(WallDetail.DetailType.GARAGE_DOOR, 0, house)
	var window := WallDetail.create(WallDetail.DetailType.WINDOW, 0, house)

	_check("defaults", "new door takes the house's door mode", door.door_mode == WallDetail.DoorMode.ANIMATED)
	_check("defaults", "new garage takes the house's garage mode", garage.door_mode == WallDetail.DoorMode.NONE)
	_check("defaults", "a window is not a door", not window.is_door() and not window.is_animated())
	_check("defaults", "an empty opening has no leaf", not garage.has_leaf())


func _check(group: String, name: String, condition: bool) -> void:
	if condition:
		print("PASS [%s] %s" % [group, name])
	else:
		failures += 1
		printerr("FAIL [%s] %s" % [group, name])
