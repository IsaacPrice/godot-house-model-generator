extends SceneTree


const EPS := 1e-3

var failures: int = 0


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_test_export_structure()
	_test_gating()
	_test_lit_material_fallback()
	_test_runtime_toggle()
	_test_pack_roundtrip()

	if failures == 0:
		print("ALL WINDOW GLOW TESTS PASSED")
		quit(0)
	else:
		print("%d WINDOW GLOW TEST FAILURE(S)" % failures)
		quit(1)


func _test_export_structure() -> void:
	var house := _bar_house()
	_add_window(house, Vector2i(1, 0), WallDetail.EdgeDir.NORTH)
	var building: Node3D = HouseSceneBuilder.build(house)

	_check("export", "runtime script attached", building is HouseWindowLights)
	_check("export", "windows start unlit", building.get("windows_lit") == false)
	_check("export", "a lit material is always provided", building.get("lit_glass_material") is Material)
	_check("export", "no light nodes exist", building.get_node_or_null("WindowLights") == null)
	_check("export", "mesh + collision intact", building.get_node_or_null("HouseMesh") != null and building.get_node_or_null("StaticBody3D") != null)
	building.free()


func _test_gating() -> void:
	var house := _bar_house()
	_add_window(house, Vector2i(1, 0), WallDetail.EdgeDir.NORTH)
	house.window_glow_enabled = false
	var disabled: Node3D = HouseSceneBuilder.build(house)
	_check("gating", "glow disabled leaves no script", disabled.get_script() == null)
	disabled.free()

	var windowless: Node3D = HouseSceneBuilder.build(_bar_house())
	_check("gating", "windowless house gets no script", windowless.get_script() == null)
	_check("gating", "windowless house keeps mesh + collision", windowless.get_node_or_null("HouseMesh") != null and windowless.get_node_or_null("StaticBody3D") != null)
	windowless.free()


func _test_lit_material_fallback() -> void:
	var house := _bar_house()
	_add_window(house, Vector2i(1, 0), WallDetail.EdgeDir.NORTH)
	var explicit := StandardMaterial3D.new()
	house.lit_glass_material = explicit
	var building: Node3D = HouseSceneBuilder.build(house)
	_check("lit_material", "explicit lit material used as-is", building.get("lit_glass_material") == explicit)
	building.free()

	house.lit_glass_material = null
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.2, 0.4, 0.9)
	house.glass_material = glass
	var derived_building: Node3D = HouseSceneBuilder.build(house)
	var derived: Material = derived_building.get("lit_glass_material")
	_check("lit_material", "derived material is a new resource", derived != null and derived != glass)
	if derived is StandardMaterial3D:
		_check("lit_material", "derived material glows", derived.emission_enabled)
		_check("lit_material", "derived emission uses the glow color", derived.emission.is_equal_approx(house.window_glow_color))
		_check("lit_material", "derived emission uses the glow energy", absf(derived.emission_energy_multiplier - house.window_glow_energy) < EPS)
		_check("lit_material", "derived material keeps the glass albedo", derived.albedo_color.is_equal_approx(glass.albedo_color))
	else:
		_check("lit_material", "derived material is a StandardMaterial3D", false)
	_check("lit_material", "source glass material untouched", not glass.emission_enabled)
	derived_building.free()

	house.glass_material = null
	var bare_building: Node3D = HouseSceneBuilder.build(house)
	var bare: Material = bare_building.get("lit_glass_material")
	_check("lit_material", "from-scratch fallback glows", bare is StandardMaterial3D and (bare as StandardMaterial3D).emission_enabled)
	bare_building.free()


func _test_runtime_toggle() -> void:
	var house := _bar_house()
	_add_window(house, Vector2i(1, 0), WallDetail.EdgeDir.NORTH)
	_add_window(house, Vector2i(0, 0), WallDetail.EdgeDir.WEST)
	var lit_material := StandardMaterial3D.new()
	house.lit_glass_material = lit_material

	var building: Node3D = HouseSceneBuilder.build(house)
	root.add_child(building)

	var mesh_instance: MeshInstance3D = building.get_node("HouseMesh")
	var glass: int = MeshChecks.find_surface(mesh_instance.mesh, "glass")
	_check("toggle", "glass surface found by name", glass >= 0)
	_check("toggle", "unlit: no glass override", mesh_instance.get_surface_override_material(glass) == null)

	building.set("windows_lit", true)
	_check("toggle", "lit: glass override applied", mesh_instance.get_surface_override_material(glass) == lit_material)

	building.call("set_windows_lit", false)
	_check("toggle", "unlit again: override cleared", mesh_instance.get_surface_override_material(glass) == null)

	root.remove_child(building)
	building.free()


func _test_pack_roundtrip() -> void:
	var export_path := "user://window_glow_export_test.tscn"

	var house := _bar_house()
	_add_window(house, Vector2i(1, 0), WallDetail.EdgeDir.NORTH)
	house.glass_material = StandardMaterial3D.new()

	var building: Node3D = HouseSceneBuilder.build(house)
	var packed := PackedScene.new()
	_check("roundtrip", "export packs", packed.pack(building) == OK)
	_check("roundtrip", "export saved", ResourceSaver.save(packed, export_path) == OK)
	building.free()

	var reloaded: PackedScene = ResourceLoader.load(export_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	_check("roundtrip", "export reloads", reloaded != null)
	if reloaded != null:
		var instance: Node3D = reloaded.instantiate()
		root.add_child(instance)

		_check("roundtrip", "script survives the roundtrip", instance.get("windows_lit") == false)
		var lit: Material = instance.get("lit_glass_material")
		_check("roundtrip", "baked lit material survives", lit is StandardMaterial3D and (lit as StandardMaterial3D).emission_enabled)
		_check("roundtrip", "still no light nodes", instance.get_node_or_null("WindowLights") == null)

		var mesh_instance: MeshInstance3D = instance.get_node("HouseMesh")
		var glass: int = MeshChecks.find_surface(mesh_instance.mesh, "glass")
		instance.set("windows_lit", true)
		_check("roundtrip", "toggle works after reload", mesh_instance.get_surface_override_material(glass) == lit)

		root.remove_child(instance)
		instance.free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(export_path))


func _bar_house() -> HouseData:
	var house := HouseData.new()
	house.level_cell_size = 2.0
	var floor_data := FloorData.new()
	floor_data.level = 0
	floor_data.height = 3.0
	for x in range(3):
		floor_data.add_cell(Vector2i(x, 0))
	house.add_floor(floor_data)
	return house


func _add_window(house: HouseData, cell: Vector2i, direction: int, style: int = WallDetail.WindowStyle.SINGLE) -> void:
	var window := WallDetail.create(WallDetail.DetailType.WINDOW)
	window.cell = cell
	window.direction = direction
	window.style = style
	house.floors[0].set_wall_detail(window)


func _check(shape: String, what: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("FAIL [%s] %s" % [shape, what])
