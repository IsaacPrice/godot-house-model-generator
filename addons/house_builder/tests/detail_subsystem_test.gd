extends SceneTree


const EPS := 1e-3

var failures: int = 0


func _init() -> void:
	_test_edge_conventions()
	_test_wall_detail_addressing()
	_test_rules()
	_test_roundtrip()
	_test_window_mesh()
	_test_door_and_garage_mesh()
	_test_invalid_details_skipped()
	_test_oversized_opening_clamped()
	_test_porch_mesh()
	_test_porch_stairs_mesh()
	_test_porch_stairs_railing_mesh()
	_test_porch_post_plan()
	_test_porch_reflex_corner_post()
	_test_porch_post_bases()
	_test_porch_railing_infill()
	_test_porch_overhang_mesh()
	_test_porch_stairs_overhang_mesh()
	_test_porch_roof_mesh()
	_test_chimney_mesh()
	_test_dormer_mesh()
	_test_all_details_end_to_end()

	if failures == 0:
		print("ALL DETAIL TESTS PASSED")
		quit(0)
	else:
		print("%d DETAIL TEST FAILURE(S)" % failures)
		quit(1)


func _test_edge_conventions() -> void:
	var cell_size := 2.0
	var loops: Array[BoundaryLoop] = Footprint.trace_loops([Vector2i(0, 0)], cell_size)
	_check("edges", "single cell traces one loop", loops.size() == 1)
	var loop: BoundaryLoop = loops[0]

	for direction in WallDetail.EdgeDir.values():
		var segment: PackedVector2Array = WallDetail.endpoints(Vector2i(0, 0), direction, cell_size)
		var normal: Vector2 = WallDetail.NORMALS[direction]
		var found := false
		for i in range(loop.size()):
			if not loop.normals[i].is_equal_approx(normal):
				continue
			var a: Vector2 = loop.points[i]
			var b: Vector2 = loop.points[(i + 1) % loop.size()]
			var matches_forward: bool = a.is_equal_approx(segment[0]) and b.is_equal_approx(segment[1])
			var matches_reverse: bool = a.is_equal_approx(segment[1]) and b.is_equal_approx(segment[0])
			if matches_forward or matches_reverse:
				found = true
		_check("edges", "direction %d segment+normal appears in traced loop" % direction, found)

	for direction in WallDetail.EdgeDir.values():
		var here: PackedVector2Array = WallDetail.endpoints(Vector2i(1, 1), direction, cell_size)
		var next: PackedVector2Array = WallDetail.endpoints(Vector2i(1, 1) + WallDetail.SPAN_STEP[direction], direction, cell_size)
		_check("edges", "direction %d span edges are contiguous" % direction, here[1].is_equal_approx(next[0]))
		var dir_here: Vector2 = (here[1] - here[0]).normalized()
		var dir_next: Vector2 = (next[1] - next[0]).normalized()
		_check("edges", "direction %d span edges are colinear" % direction, dir_here.is_equal_approx(dir_next))


func _test_wall_detail_addressing() -> void:
	var floor_data := FloorData.new()
	floor_data.height = 3.0
	for x in range(3):
		floor_data.add_cell(Vector2i(x, 0))

	var window := WallDetail.create(WallDetail.DetailType.WINDOW)
	window.cell = Vector2i(0, 0)
	window.direction = WallDetail.EdgeDir.NORTH
	floor_data.set_wall_detail(window)
	_check("addressing", "detail found at its own edge", floor_data.get_wall_detail(Vector2i(0, 0), WallDetail.EdgeDir.NORTH) == window)
	_check("addressing", "detail absent from other edges", floor_data.get_wall_detail(Vector2i(0, 0), WallDetail.EdgeDir.SOUTH) == null)

	var garage := WallDetail.create(WallDetail.DetailType.GARAGE_DOOR)
	garage.cell = Vector2i(0, 0)
	garage.direction = WallDetail.EdgeDir.NORTH
	garage.span = 2
	garage.apply_span_defaults()
	_check("addressing", "span-2 garage default width", absf(garage.width - 3.6) < EPS)
	floor_data.set_wall_detail(garage)
	_check("addressing", "garage replaced the overlapped window", not floor_data.wall_details.has(window))
	_check("addressing", "garage found at its second edge", floor_data.get_wall_detail(Vector2i(1, 0), WallDetail.EdgeDir.NORTH) == garage)

	floor_data.remove_wall_detail(Vector2i(1, 0), WallDetail.EdgeDir.NORTH)
	_check("addressing", "removal through the second edge removes the garage", floor_data.wall_details.is_empty())

	var wide_window := WallDetail.create(WallDetail.DetailType.WINDOW)
	wide_window.cell = Vector2i(0, 0)
	wide_window.direction = WallDetail.EdgeDir.SOUTH
	wide_window.span = 3
	_check("addressing", "span-3 window covers all three cells", wide_window.spanned_cells() == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	_check("addressing", "span-3 max width follows the span formula", absf(DetailRules.max_opening_width(2.0, 3) - 5.6) < EPS)


func _test_rules() -> void:
	var cell_size := 2.0
	var floor_data := FloorData.new()
	floor_data.height = 3.0
	for x in range(3):
		floor_data.add_cell(Vector2i(x, 0))
	floor_data.add_cell(Vector2i(1, 1))

	_check("rules", "exposed edge is boundary", DetailRules.is_boundary_edge(floor_data.cells, Vector2i(0, 0), WallDetail.EdgeDir.NORTH))
	_check("rules", "shared edge is not boundary", not DetailRules.is_boundary_edge(floor_data.cells, Vector2i(1, 0), WallDetail.EdgeDir.SOUTH))
	_check("rules", "empty cell has no boundary edge", not DetailRules.is_boundary_edge(floor_data.cells, Vector2i(0, 1), WallDetail.EdgeDir.NORTH))

	var window := WallDetail.create(WallDetail.DetailType.WINDOW)
	window.cell = Vector2i(0, 0)
	window.direction = WallDetail.EdgeDir.NORTH
	floor_data.set_wall_detail(window)
	_check("rules", "default window is valid", DetailRules.wall_detail_valid(window, floor_data, true))

	floor_data.remove_cell(Vector2i(0, 0))
	_check("rules", "orphaned window is invalid", not DetailRules.wall_detail_valid(window, floor_data, true))
	floor_data.add_cell(Vector2i(0, 0))

	var house := HouseData.new()
	house.level_cell_size = cell_size
	window.width = DetailRules.max_opening_width(cell_size, 1) + 0.5
	_check("rules", "oversized window is still valid, not rejected", DetailRules.wall_detail_valid(window, floor_data, true))
	var openings: Array[Dictionary] = WallOpenings.collect(house, floor_data, 0.0, true)
	var opening_width: float = (openings[0]["a"] as Vector2).distance_to(openings[0]["b"])
	_check("rules", "oversized window's opening clamps to fit its run", opening_width <= DetailRules.max_opening_width(cell_size, 1) + EPS)
	window.width = 1.2

	window.sill_height = floor_data.height - window.height
	_check("rules", "window without header room is still valid, not rejected", DetailRules.wall_detail_valid(window, floor_data, true))
	openings = WallOpenings.collect(house, floor_data, 0.0, true)
	_check("rules", "window without header room clamps its top under the ceiling", (openings[0]["top_y"] as float) <= DetailRules.max_opening_top(floor_data.height) + EPS)
	window.sill_height = 0.9

	var door := WallDetail.create(WallDetail.DetailType.DOOR)
	door.cell = Vector2i(1, 1)
	door.direction = WallDetail.EdgeDir.SOUTH
	floor_data.set_wall_detail(door)
	_check("rules", "door valid on lowest floor", DetailRules.wall_detail_valid(door, floor_data, true))
	_check("rules", "door invalid on upper floor", not DetailRules.wall_detail_valid(door, floor_data, false))

	var garage := WallDetail.create(WallDetail.DetailType.GARAGE_DOOR)
	garage.cell = Vector2i(1, 0)
	garage.direction = WallDetail.EdgeDir.NORTH
	garage.span = 2
	garage.apply_span_defaults()
	floor_data.set_wall_detail(garage)
	_check("rules", "span-2 garage valid on a straight run", DetailRules.wall_detail_valid(garage, floor_data, true))
	garage.cell = Vector2i(2, 0)
	_check("rules", "span-2 garage invalid past the footprint end", not DetailRules.wall_detail_valid(garage, floor_data, true))
	garage.cell = Vector2i(1, 0)

	var second := WallDetail.create(WallDetail.DetailType.WINDOW)
	second.cell = Vector2i(2, 0)
	second.direction = WallDetail.EdgeDir.NORTH
	floor_data.wall_details.append(second)
	_check("rules", "overlapping details are invalid", not DetailRules.wall_detail_valid(second, floor_data, true))

	_check("rules", "porch cell refused under the house", not DetailRules.can_paint_porch_cell(floor_data, Vector2i(1, 0)))
	_check("rules", "porch cell allowed beside the house", DetailRules.can_paint_porch_cell(floor_data, Vector2i(0, 1)))
	floor_data.add_porch_cell(Vector2i(0, 1))
	var stairs := WallDetail.create(WallDetail.DetailType.STAIRS)
	stairs.cell = Vector2i(0, 1)
	stairs.direction = WallDetail.EdgeDir.WEST
	floor_data.set_wall_detail(stairs)
	_check("rules", "stairs valid on a porch boundary edge", DetailRules.wall_detail_valid(stairs, floor_data, true))
	stairs.cell = Vector2i(1, 1)
	_check("rules", "stairs invalid off the porch", not DetailRules.wall_detail_valid(stairs, floor_data, true))

	var dormer := DormerData.new()
	dormer.cell = Vector2i(1, 1)
	dormer.direction = WallDetail.EdgeDir.SOUTH
	_check("rules", "dormer valid on boundary edge", DetailRules.dormer_edge_valid(dormer, floor_data))
	dormer.direction = WallDetail.EdgeDir.NORTH
	_check("rules", "dormer invalid on interior edge", not DetailRules.dormer_edge_valid(dormer, floor_data))

	var wide_dormer := DormerData.new()
	wide_dormer.cell = Vector2i(0, 0)
	wide_dormer.direction = WallDetail.EdgeDir.NORTH
	wide_dormer.span = 2
	_check("rules", "span-2 dormer valid on a straight run", DetailRules.dormer_edge_valid(wide_dormer, floor_data))
	wide_dormer.cell = Vector2i(2, 0)
	_check("rules", "span-2 dormer invalid past the footprint end", not DetailRules.dormer_edge_valid(wide_dormer, floor_data))

	var chimney := ChimneyData.new()
	chimney.cell = Vector2i(1, 0)
	_check("rules", "chimney valid on occupied cell", DetailRules.chimney_cell_valid(chimney, floor_data))
	chimney.cell = Vector2i(2, 2)
	_check("rules", "chimney invalid on empty cell", not DetailRules.chimney_cell_valid(chimney, floor_data))


func _test_roundtrip() -> void:
	var house := HouseData.new()
	house.porch_railing_style = HouseData.RailingStyle.CROSS
	house.porch_has_roof = false
	house.porch_post_base_mode = HouseData.PostBaseMode.ENDS_AND_CORNERS
	house.porch_post_base_height = 0.7
	house.porch_baluster_spacing = 0.09
	house.porch_horizontal_rail_count = 5

	var floor_data := FloorData.new()
	floor_data.level = 0
	floor_data.height = 3.0
	for x in range(3):
		floor_data.add_cell(Vector2i(x, 0))
	floor_data.add_porch_cell(Vector2i(0, 1))

	var window := WallDetail.create(WallDetail.DetailType.WINDOW, WallDetail.WindowStyle.WIDE)
	window.cell = Vector2i(0, 0)
	window.direction = WallDetail.EdgeDir.NORTH
	floor_data.set_wall_detail(window)

	var garage := WallDetail.create(WallDetail.DetailType.GARAGE_DOOR)
	garage.cell = Vector2i(1, 0)
	garage.direction = WallDetail.EdgeDir.NORTH
	garage.span = 2
	garage.apply_span_defaults()
	floor_data.set_wall_detail(garage)

	var stairs := WallDetail.create(WallDetail.DetailType.STAIRS)
	stairs.cell = Vector2i(0, 1)
	stairs.direction = WallDetail.EdgeDir.WEST
	stairs.stair_step_height = 0.2
	stairs.stair_has_railing = true
	floor_data.set_wall_detail(stairs)

	var dormer := DormerData.new()
	dormer.cell = Vector2i(1, 0)
	dormer.direction = WallDetail.EdgeDir.SOUTH
	dormer.width = 2.0
	dormer.window_style = WallDetail.WindowStyle.SINGLE
	floor_data.dormers.append(dormer)

	var chimney := ChimneyData.new()
	chimney.cell = Vector2i(2, 0)
	chimney.extra_height = 1.1
	floor_data.chimneys.append(chimney)

	house.add_floor(floor_data)

	var path := "user://detail_roundtrip_test.tres"
	var save_error: int = ResourceSaver.save(house, path)
	_check("roundtrip", "save succeeded", save_error == OK)

	var loaded: HouseData = ResourceLoader.load(path, "HouseData", ResourceLoader.CACHE_MODE_IGNORE)
	_check("roundtrip", "load succeeded", loaded != null)
	if loaded == null:
		return

	_check("roundtrip", "railing style preserved", loaded.porch_railing_style == HouseData.RailingStyle.CROSS)
	_check("roundtrip", "porch roof flag preserved", loaded.porch_has_roof == false)
	_check("roundtrip", "post base mode preserved", loaded.porch_post_base_mode == HouseData.PostBaseMode.ENDS_AND_CORNERS)
	_check("roundtrip", "post base height preserved", absf(loaded.porch_post_base_height - 0.7) < EPS)
	_check("roundtrip", "baluster spacing preserved", absf(loaded.porch_baluster_spacing - 0.09) < EPS)
	_check("roundtrip", "horizontal rail count preserved", loaded.porch_horizontal_rail_count == 5)

	var loaded_floor: FloorData = loaded.floors[0]
	_check("roundtrip", "cells preserved", loaded_floor.cells == floor_data.cells)
	_check("roundtrip", "porch cells preserved", loaded_floor.porch_cells == floor_data.porch_cells)
	_check("roundtrip", "wall detail count preserved", loaded_floor.wall_details.size() == 3)
	_check("roundtrip", "dormer count preserved", loaded_floor.dormers.size() == 1)
	_check("roundtrip", "chimney count preserved", loaded_floor.chimneys.size() == 1)

	var loaded_window: WallDetail = loaded_floor.get_wall_detail(Vector2i(0, 0), WallDetail.EdgeDir.NORTH)
	_check("roundtrip", "window found after load", loaded_window != null)
	if loaded_window != null:
		_check("roundtrip", "window type preserved", loaded_window.type == WallDetail.DetailType.WINDOW)
		_check("roundtrip", "window style preserved", loaded_window.style == WallDetail.WindowStyle.WIDE)
		_check("roundtrip", "window width preserved", absf(loaded_window.width - 1.5) < EPS)

	var loaded_garage: WallDetail = loaded_floor.get_wall_detail(Vector2i(2, 0), WallDetail.EdgeDir.NORTH)
	_check("roundtrip", "garage found through its span after load", loaded_garage != null and loaded_garage.type == WallDetail.DetailType.GARAGE_DOOR)
	if loaded_garage != null:
		_check("roundtrip", "garage span preserved", loaded_garage.span == 2)

	var loaded_stairs: WallDetail = loaded_floor.get_wall_detail(Vector2i(0, 1), WallDetail.EdgeDir.WEST)
	_check("roundtrip", "stairs found after load", loaded_stairs != null and loaded_stairs.type == WallDetail.DetailType.STAIRS)
	if loaded_stairs != null:
		_check("roundtrip", "stairs step height preserved", absf(loaded_stairs.stair_step_height - 0.2) < EPS)
		_check("roundtrip", "stairs railing flag preserved", loaded_stairs.stair_has_railing == true)

	var loaded_dormer: DormerData = loaded_floor.dormers[0]
	_check("roundtrip", "dormer fields preserved", loaded_dormer.cell == Vector2i(1, 0) and loaded_dormer.direction == WallDetail.EdgeDir.SOUTH and absf(loaded_dormer.width - 2.0) < EPS and loaded_dormer.window_style == WallDetail.WindowStyle.SINGLE)

	var loaded_chimney: ChimneyData = loaded_floor.chimneys[0]
	_check("roundtrip", "chimney fields preserved", loaded_chimney.cell == Vector2i(2, 0) and absf(loaded_chimney.extra_height - 1.1) < EPS)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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


func _test_window_mesh() -> void:
	var house := _bar_house()
	var floor_data: FloorData = house.floors[0]
	var window := WallDetail.create(WallDetail.DetailType.WINDOW)
	window.cell = Vector2i(1, 0)
	window.direction = WallDetail.EdgeDir.NORTH
	floor_data.set_wall_detail(window)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("window_mesh", mesh, _check)

	var north_face := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z + 0.1) < EPS and absf(b.z + 0.1) < EPS and absf(c.z + 0.1) < EPS
	var face_area: float = MeshChecks.facing_area(mesh, "siding", Vector3(0, 0, -1), north_face)
	var expected: float = 6.2 * 3.0 - 1.2 * 1.4
	_check("window_mesh", "outer face area %.3f == %.3f" % [face_area, expected], absf(face_area - expected) < 1e-2)

	var left_jamb := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.x - 2.4) < EPS and absf(b.x - 2.4) < EPS and absf(c.x - 2.4) < EPS
	var jamb_area: float = MeshChecks.facing_area(mesh, "siding", Vector3(1, 0, 0), left_jamb)
	_check("window_mesh", "left jamb area %.3f" % jamb_area, absf(jamb_area - 0.2 * 1.4) < 1e-3)

	var arrays: Array = MeshChecks.surface_arrays(mesh, "siding")
	var intruder := false
	for v in arrays[Mesh.ARRAY_VERTEX]:
		if v.x > 2.4 + EPS and v.x < 3.6 - EPS and v.y > 0.9 + EPS and v.y < 2.3 - EPS and absf(v.z) < 0.1 + EPS:
			intruder = true
	_check("window_mesh", "no siding inside the opening", not intruder)

	var glass: Array = MeshChecks.surface_arrays(mesh, "glass")
	_check("window_mesh", "glass pane is two quads", not glass.is_empty() and glass[Mesh.ARRAY_INDEX].size() == 12)
	_check("window_mesh", "frame surface present", MeshChecks.find_surface(mesh, "window_frame") >= 0)


func _test_door_and_garage_mesh() -> void:
	var house := _bar_house()
	var floor_data: FloorData = house.floors[0]

	var door := WallDetail.create(WallDetail.DetailType.DOOR, WallDetail.DoorStyle.PANELED)
	door.cell = Vector2i(0, 0)
	door.direction = WallDetail.EdgeDir.SOUTH
	floor_data.set_wall_detail(door)

	var garage := WallDetail.create(WallDetail.DetailType.GARAGE_DOOR)
	garage.cell = Vector2i(1, 0)
	garage.direction = WallDetail.EdgeDir.SOUTH
	garage.span = 2
	garage.apply_span_defaults()
	floor_data.set_wall_detail(garage)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("door_garage_mesh", mesh, _check)

	_check("door_garage_mesh", "door slab and panels face outward", MeshChecks.facing_triangle_count(mesh, "door", Vector3(0, 0, 1)) == 2 + 4 * 2)

	_check("door_garage_mesh", "garage panel fronts", MeshChecks.facing_triangle_count(mesh, "garage_door", Vector3(0, 0, 1)) == DetailConstants.GARAGE_PANEL_COUNT * 2)

	var arrays: Array = MeshChecks.surface_arrays(mesh, "siding")
	var intruder := false
	for v in arrays[Mesh.ARRAY_VERTEX]:
		if absf(v.z - 2.0) > 0.1 + EPS:
			continue
		if v.x > 2.2 + EPS and v.x < 5.8 - EPS and v.y > EPS and v.y < 2.2 - EPS:
			intruder = true
		if v.x > 0.5 + EPS and v.x < 1.5 - EPS and v.y > EPS and v.y < 2.1 - EPS:
			intruder = true
	_check("door_garage_mesh", "openings cut clean through the south wall", not intruder)


func _test_invalid_details_skipped() -> void:
	var house := _bar_house()
	var floor_data: FloorData = house.floors[0]

	var orphan := WallDetail.create(WallDetail.DetailType.WINDOW)
	orphan.cell = Vector2i(5, 5)
	orphan.direction = WallDetail.EdgeDir.NORTH
	floor_data.wall_details.append(orphan)

	var garage := WallDetail.create(WallDetail.DetailType.GARAGE_DOOR)
	garage.cell = Vector2i(0, 0)
	garage.direction = WallDetail.EdgeDir.SOUTH
	garage.span = 2
	garage.apply_span_defaults()
	floor_data.wall_details.append(garage)
	var window := WallDetail.create(WallDetail.DetailType.WINDOW)
	window.cell = Vector2i(1, 0)
	window.direction = WallDetail.EdgeDir.SOUTH
	floor_data.wall_details.append(window)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("invalid_details", mesh, _check)
	_check("invalid_details", "no glass emitted", MeshChecks.find_surface(mesh, "glass") == -1)
	_check("invalid_details", "no garage door emitted", MeshChecks.find_surface(mesh, "garage_door") == -1)

	var north_face := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z + 0.1) < EPS and absf(b.z + 0.1) < EPS and absf(c.z + 0.1) < EPS
	var face_area: float = MeshChecks.facing_area(mesh, "siding", Vector3(0, 0, -1), north_face)
	_check("invalid_details", "north wall stays solid", absf(face_area - 6.2 * 3.0) < 1e-2)


func _test_oversized_opening_clamped() -> void:
	var house := _bar_house()
	var floor_data: FloorData = house.floors[0]
	var window := WallDetail.create(WallDetail.DetailType.WINDOW)
	window.cell = Vector2i(1, 0)
	window.direction = WallDetail.EdgeDir.NORTH
	window.width = 1.9
	floor_data.set_wall_detail(window)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("oversized_clamped", mesh, _check)

	var north_face := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z + 0.1) < EPS and absf(b.z + 0.1) < EPS and absf(c.z + 0.1) < EPS
	var face_area: float = MeshChecks.facing_area(mesh, "siding", Vector3(0, 0, -1), north_face)
	var expected: float = 6.2 * 3.0 - 1.6 * 1.4
	_check("oversized_clamped", "outer face area %.3f == %.3f (clamped to 1.6 m wide)" % [face_area, expected], absf(face_area - expected) < 1e-2)

	var glass: Array = MeshChecks.surface_arrays(mesh, "glass")
	_check("oversized_clamped", "glass still emitted despite the oversized width", not glass.is_empty())


func _porch_house() -> HouseData:
	var house := _bar_house()
	house.sidewalk_drop = house.foundation_height
	var floor_data: FloorData = house.floors[0]
	floor_data.add_porch_cell(Vector2i(0, 1))
	floor_data.add_porch_cell(Vector2i(1, 1))
	return house


func _test_porch_mesh() -> void:
	var house := _porch_house()
	house.porch_has_roof = false
	house.porch_floor_overhang = 0.0
	var floor_data: FloorData = house.floors[0]
	floor_data.porch_cells.append(Vector2i(1, 0))
	var stairs := WallDetail.create(WallDetail.DetailType.STAIRS)
	stairs.cell = Vector2i(0, 1)
	stairs.direction = WallDetail.EdgeDir.SOUTH
	floor_data.set_wall_detail(stairs)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("porch_mesh", mesh, _check)

	var deck_top: float = -DetailConstants.PORCH_DROP

	var deck_filter := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.y - deck_top) < EPS and absf(b.y - deck_top) < EPS and absf(c.y - deck_top) < EPS
	var deck_area: float = MeshChecks.facing_area(mesh, "porch_floor", Vector3.UP, deck_filter)
	_check("porch_mesh", "deck area %.3f == 8" % deck_area, absf(deck_area - 8.0) < 1e-2)

	var south_face := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z - 4.0) < EPS and absf(b.z - 4.0) < EPS and absf(c.z - 4.0) < EPS and a.x > 1.9 and b.x > 1.9 and c.x > 1.9
	var slab_band: float = MeshChecks.facing_area(mesh, "porch_floor", Vector3(0, 0, 1), south_face)
	_check("porch_mesh", "deck slab skirt band %.3f" % slab_band, absf(slab_band - 2.0 * house.porch_floor_thickness) < 1e-3)
	var foundation_band: float = MeshChecks.facing_area(mesh, "foundation", Vector3(0, 0, 1), south_face)
	var expected_band: float = 2.0 * (house.foundation_height - DetailConstants.PORCH_DROP - house.porch_floor_thickness)
	_check("porch_mesh", "foundation skirt band %.3f == %.3f" % [foundation_band, expected_band], absf(foundation_band - expected_band) < 1e-3)

	var adjacent_face := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z - 2.0) < EPS and a.y < 0.0 and b.y < 0.0 and c.y < 0.0
	_check("porch_mesh", "no skirt against the house wall", MeshChecks.facing_area(mesh, "porch_floor", Vector3(0, 0, -1), adjacent_face) < EPS)

	_check("porch_mesh", "post surface exists", MeshChecks.find_surface(mesh, "porch_post") >= 0)
	_check("porch_mesh", "baluster surface exists", MeshChecks.find_surface(mesh, "porch_baluster") >= 0)

	var railing: Array = MeshChecks.surface_arrays(mesh, "porch_railing")
	_check("porch_mesh", "railing surface exists", not railing.is_empty())
	var in_stairs := false
	var on_railed_side := false
	if not railing.is_empty():
		for v in railing[Mesh.ARRAY_VERTEX]:
			if v.z > 3.5 and v.y > deck_top + EPS:
				if v.x > 0.3 and v.x < 1.7:
					in_stairs = true
				elif v.x > 1.9:
					on_railed_side = true
	_check("porch_mesh", "railing crosses the railed section", on_railed_side)
	_check("porch_mesh", "no railing across the stairs (railing disabled on this detail)", not in_stairs)

	var max_rail_y: float = -INF
	if not railing.is_empty():
		for v in railing[Mesh.ARRAY_VERTEX]:
			max_rail_y = maxf(max_rail_y, v.y)
	_check("porch_mesh", "roofless porch tops at railing height", absf(max_rail_y - (deck_top + house.porch_railing_height)) < EPS)


func _test_porch_stairs_mesh() -> void:
	var house := _porch_house()
	house.porch_has_roof = false
	house.porch_floor_overhang = 0.0
	var floor_data: FloorData = house.floors[0]
	var stairs := WallDetail.create(WallDetail.DetailType.STAIRS)
	stairs.cell = Vector2i(0, 1)
	stairs.direction = WallDetail.EdgeDir.SOUTH
	floor_data.set_wall_detail(stairs)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("porch_stairs_mesh", mesh, _check)

	var deck_top: float = -DetailConstants.PORCH_DROP
	var grade: float = -house.foundation_height
	var step1_y: float = MeshChecks.surface_height_at(mesh, "porch_floor", Vector2(1.0, 4.15), 1.0)
	var step2_y: float = MeshChecks.surface_height_at(mesh, "porch_floor", Vector2(1.0, 4.45), 1.0)
	_check("porch_stairs_mesh", "step 1 tread at %.4f == %.4f" % [step1_y, deck_top - 0.175], absf(step1_y - (deck_top - 0.175)) < EPS)
	_check("porch_stairs_mesh", "no step 2 tread on grade %.4f - the ground is that step (probe %.4f)" % [grade, step2_y], step2_y < grade - EPS)

	var step1_front := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z - 4.3) < EPS and absf(b.z - 4.3) < EPS and absf(c.z - 4.3) < EPS
	var tread_face: float = MeshChecks.facing_area(mesh, "porch_floor", Vector3(0, 0, 1), step1_front)
	_check("porch_stairs_mesh", "tread cube front face %.3f" % tread_face, absf(tread_face - 2.0 * house.porch_floor_thickness) < 1e-3)
	var riser_face: float = MeshChecks.facing_area(mesh, "foundation", Vector3(0, 0, 1), step1_front)
	_check("porch_stairs_mesh", "bottom riser rises from the ground to the tread %.4f" % riser_face, absf(riser_face - 2.0 * (0.175 - house.porch_floor_thickness)) < 1e-3)

	var min_y: float = INF
	for slot in ["porch_floor", "foundation"]:
		var arrays: Array = MeshChecks.surface_arrays(mesh, slot)
		if not arrays.is_empty():
			for v in arrays[Mesh.ARRAY_VERTEX]:
				min_y = minf(min_y, v.y)
	_check("porch_stairs_mesh", "nothing sinks below grade %.4f" % min_y, min_y > grade - EPS)

	_check("porch_stairs_mesh", "no post reaches into the stairs region without stair_has_railing", not _has_vertex_near(mesh, "porch_post", func(v: Vector3) -> bool: return v.x < 2.1 and v.z > 4.05))


func _test_porch_stairs_railing_mesh() -> void:
	var house := _porch_house()
	house.porch_has_roof = false
	house.porch_floor_overhang = 0.0
	var floor_data: FloorData = house.floors[0]
	var stairs := WallDetail.create(WallDetail.DetailType.STAIRS)
	stairs.cell = Vector2i(0, 1)
	stairs.direction = WallDetail.EdgeDir.SOUTH
	stairs.stair_has_railing = true
	floor_data.set_wall_detail(stairs)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("porch_stairs_railing_mesh", mesh, _check)

	var grade: float = -house.foundation_height
	var in_stairs := func(v: Vector3) -> bool: return v.x < 2.1 and v.z > 3.95
	var lowest_post: float = INF
	var lowest_rail: float = INF
	for v in MeshChecks.surface_arrays(mesh, "porch_post")[Mesh.ARRAY_VERTEX]:
		if in_stairs.call(v):
			lowest_post = minf(lowest_post, v.y)
	for v in MeshChecks.surface_arrays(mesh, "porch_railing")[Mesh.ARRAY_VERTEX]:
		if in_stairs.call(v):
			lowest_rail = minf(lowest_rail, v.y)
	_check("porch_stairs_railing_mesh", "a post reaches down to grade %.4f (got %.4f)" % [grade, lowest_post], absf(lowest_post - grade) < EPS)
	_check("porch_stairs_railing_mesh", "the bottom rail slopes down near grade (got %.4f)" % lowest_rail, lowest_rail < grade + 0.2)


func _has_vertex_near(mesh: ArrayMesh, slot: String, predicate: Callable) -> bool:
	var arrays: Array = MeshChecks.surface_arrays(mesh, slot)
	if arrays.is_empty():
		return false
	for v in arrays[Mesh.ARRAY_VERTEX]:
		if predicate.call(v):
			return true
	return false


func _test_porch_post_plan() -> void:
	var house := _porch_house()
	house.porch_has_roof = false
	house.porch_floor_overhang = 0.0
	var floor_data: FloorData = house.floors[0]
	var stairs := WallDetail.create(WallDetail.DetailType.STAIRS)
	stairs.cell = Vector2i(0, 1)
	stairs.direction = WallDetail.EdgeDir.SOUTH
	stairs.stair_has_railing = true
	floor_data.set_wall_detail(stairs)

	var plan: Array[Dictionary] = PorchBuilder.post_plan(house, floor_data)
	_check("porch_post_plan", "five posts, got %d" % plan.size(), plan.size() == 5)

	var min_gap: float = INF
	for i in range(plan.size()):
		for j in range(i + 1, plan.size()):
			min_gap = minf(min_gap, plan[i]["center"].distance_to(plan[j]["center"]))
	_check("porch_post_plan", "no two posts within a post width (closest %.3f)" % min_gap, min_gap >= house.porch_post_width)

	_check("porch_post_plan", "deck corner at the stairs opening", _post_role_at(plan, Vector2(0.06, 3.94)) == PorchBuilder.PostRole.CORNER)
	_check("porch_post_plan", "end post at the stairs opening", _post_role_at(plan, Vector2(2.0, 3.94)) == PorchBuilder.PostRole.END)
	_check("porch_post_plan", "south/east deck corner", _post_role_at(plan, Vector2(3.94, 3.94)) == PorchBuilder.PostRole.CORNER)
	_check("porch_post_plan", "west run's wall end is a plain post", _post_role_at(plan, Vector2(0.06, 2.06)) == PorchBuilder.PostRole.INTERMEDIATE)
	_check("porch_post_plan", "east run's wall end is a plain post", _post_role_at(plan, Vector2(3.94, 2.06)) == PorchBuilder.PostRole.INTERMEDIATE)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	var deck_top: float = -DetailConstants.PORCH_DROP
	var on_deck := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.y - deck_top) < EPS and absf(b.y - deck_top) < EPS and absf(c.y - deck_top) < EPS
	var footprint: float = house.porch_post_width * house.porch_post_width
	var bottoms: float = MeshChecks.facing_area(mesh, "porch_post", Vector3.DOWN, on_deck)
	_check("porch_post_plan", "five post bottoms on the deck (%.4f == %.4f)" % [bottoms, 5.0 * footprint], absf(bottoms - 5.0 * footprint) < 1e-4)


func _test_porch_reflex_corner_post() -> void:
	var house := _porch_house()
	house.porch_has_roof = false
	var floor_data: FloorData = house.floors[0]
	floor_data.add_porch_cell(Vector2i(2, 1))
	floor_data.add_porch_cell(Vector2i(2, 2))

	var plan: Array[Dictionary] = PorchBuilder.post_plan(house, floor_data)
	_check("porch_reflex", "eight posts, got %d" % plan.size(), plan.size() == 8)

	var min_gap: float = INF
	for i in range(plan.size()):
		for j in range(i + 1, plan.size()):
			min_gap = minf(min_gap, plan[i]["center"].distance_to(plan[j]["center"]))
	_check("porch_reflex", "no two posts within a post width (closest %.3f)" % min_gap, min_gap >= house.porch_post_width)

	_check("porch_reflex", "one post at the inside corner", _post_role_at(plan, Vector2(4.06, 3.94)) == PorchBuilder.PostRole.CORNER)
	for corner in [Vector2(0.06, 3.94), Vector2(4.06, 5.94), Vector2(5.94, 5.94)]:
		_check("porch_reflex", "outside corner post at %v" % corner, _post_role_at(plan, corner) == PorchBuilder.PostRole.CORNER)


func _post_role_at(plan: Array[Dictionary], center: Vector2) -> int:
	for entry in plan:
		if entry["center"].distance_to(center) < EPS:
			return entry["role"]
	return -1


func _test_porch_post_bases() -> void:
	var house := _porch_house()
	house.porch_has_roof = false
	house.porch_floor_overhang = 0.0
	var floor_data: FloorData = house.floors[0]

	var deck_top: float = -DetailConstants.PORCH_DROP
	var pier_top: float = deck_top + house.porch_post_base_height
	var trim_top: float = pier_top + house.porch_post_base_trim_height
	var pier_face: float = house.porch_post_base_width * house.porch_post_base_width
	var trim_width: float = house.porch_post_base_width + 2.0 * house.porch_post_base_trim_overhang
	var at_pier_top := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.y - pier_top) < EPS and absf(b.y - pier_top) < EPS and absf(c.y - pier_top) < EPS

	_check("porch_post_bases", "five posts planned", PorchBuilder.post_plan(house, floor_data).size() == 5)

	for expected in [[HouseData.PostBaseMode.NONE, 0], [HouseData.PostBaseMode.ENDS_AND_CORNERS, 2], [HouseData.PostBaseMode.ALL, 5]]:
		house.porch_post_base_mode = expected[0]
		var count: int = expected[1]
		var mesh: ArrayMesh = HouseMeshBuilder.build(house)
		MeshChecks.check_windings("porch_post_bases", mesh, _check)
		var shafts: float = MeshChecks.facing_area(mesh, "foundation", Vector3.UP, at_pier_top)
		var bands: float = MeshChecks.facing_area(mesh, "trim", Vector3.DOWN, at_pier_top)
		_check("porch_post_bases", "mode %d: %d pier shafts (%.4f)" % [expected[0], count, shafts], absf(shafts - count * pier_face) < 1e-4)
		_check("porch_post_bases", "mode %d: %d trim bands (%.4f)" % [expected[0], count, bands], absf(bands - count * trim_width * trim_width) < 1e-4)

	house.porch_post_base_mode = HouseData.PostBaseMode.ALL
	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	var lowest_post: float = INF
	for v in MeshChecks.surface_arrays(mesh, "porch_post")[Mesh.ARRAY_VERTEX]:
		lowest_post = minf(lowest_post, v.y)
	_check("porch_post_bases", "posts carry on from the trim band at %.4f (got %.4f)" % [trim_top, lowest_post], absf(lowest_post - trim_top) < EPS)

	var pier_east := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		var face_x: float = 2.0 + house.porch_post_base_width * 0.5
		return absf(a.x - face_x) < EPS and absf(b.x - face_x) < EPS and absf(c.x - face_x) < EPS
	var side: float = MeshChecks.facing_area(mesh, "foundation", Vector3(1, 0, 0), pier_east)
	var expected_side: float = house.porch_post_base_width * (pier_top - house.foundation_base_y())
	_check("porch_post_bases", "pier runs unbroken to the foundation base (%.4f == %.4f)" % [side, expected_side], absf(side - expected_side) < 1e-4)


func _test_porch_railing_infill() -> void:
	var house := _porch_house()
	house.porch_has_roof = false
	house.porch_floor_overhang = 0.0

	var infill_top: float = -DetailConstants.PORCH_DROP + house.porch_railing_height - DetailConstants.TOP_RAIL_HEIGHT
	var at_infill_top := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.y - infill_top) < EPS and absf(b.y - infill_top) < EPS and absf(c.y - infill_top) < EPS
	var caps: float = MeshChecks.facing_area(HouseMeshBuilder.build(house), "porch_baluster", Vector3.UP, at_infill_top)
	var picket_face: float = house.porch_baluster_width * house.porch_baluster_width
	_check("porch_infill", "57 default pickets (%.4f == %.4f)" % [caps, 57.0 * picket_face], absf(caps - 57.0 * picket_face) < 1e-4)

	house.porch_baluster_spacing = 0.07
	house.porch_baluster_width = 0.08
	caps = MeshChecks.facing_area(HouseMeshBuilder.build(house), "porch_baluster", Vector3.UP, at_infill_top)
	picket_face = house.porch_baluster_width * house.porch_baluster_width
	_check("porch_infill", "115 dense pickets (%.4f == %.4f)" % [caps, 115.0 * picket_face], absf(caps - 115.0 * picket_face) < 1e-4)

	house.porch_railing_style = HouseData.RailingStyle.HORIZONTAL
	house.porch_horizontal_rail_count = 4
	house.porch_horizontal_rail_height = 0.05
	var levels: Dictionary = {}
	for v in MeshChecks.surface_arrays(HouseMeshBuilder.build(house), "porch_baluster")[Mesh.ARRAY_VERTEX]:
		levels[snappedf(v.y, 1e-4)] = true
	var heights: Array = levels.keys()
	heights.sort()
	_check("porch_infill", "four rails => eight distinct heights, got %d" % heights.size(), heights.size() == 8)
	if heights.size() == 8:
		_check("porch_infill", "rail thickness %.4f" % (heights[1] - heights[0]), absf((heights[1] - heights[0]) - house.porch_horizontal_rail_height) < EPS)


func _test_porch_overhang_mesh() -> void:
	var house := _porch_house()
	house.porch_has_roof = false
	house.porch_floor_overhang = 0.1

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("porch_overhang_mesh", mesh, _check)

	var deck_top: float = -DetailConstants.PORCH_DROP
	var deck_filter := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.y - deck_top) < EPS and absf(b.y - deck_top) < EPS and absf(c.y - deck_top) < EPS
	var deck_area: float = MeshChecks.facing_area(mesh, "porch_floor", Vector3.UP, deck_filter)
	_check("porch_overhang_mesh", "overhung deck area %.3f == 8.82" % deck_area, absf(deck_area - 8.82) < 1e-2)

	var at_offset_edge := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z - 4.1) < EPS and absf(b.z - 4.1) < EPS and absf(c.z - 4.1) < EPS
	var at_structural_edge := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z - 4.0) < EPS and absf(b.z - 4.0) < EPS and absf(c.z - 4.0) < EPS
	_check("porch_overhang_mesh", "skirt present at the overhung edge", MeshChecks.facing_area(mesh, "porch_floor", Vector3(0, 0, 1), at_offset_edge) > EPS)
	_check("porch_overhang_mesh", "no skirt left at the old structural edge", MeshChecks.facing_area(mesh, "porch_floor", Vector3(0, 0, 1), at_structural_edge) < EPS)

	_check("porch_overhang_mesh", "foundation stays on the structural line", MeshChecks.facing_area(mesh, "foundation", Vector3(0, 0, 1), at_structural_edge) > EPS)
	_check("porch_overhang_mesh", "no foundation follows the slab out to the overhung edge", MeshChecks.facing_area(mesh, "foundation", Vector3(0, 0, 1), at_offset_edge) < EPS)

	var railing: Array = MeshChecks.surface_arrays(mesh, "porch_railing")
	var railing_at_structural_line := false
	for v in railing[Mesh.ARRAY_VERTEX]:
		if absf(v.z - 4.0) < EPS:
			railing_at_structural_line = true
	_check("porch_overhang_mesh", "railing stays on the structural line despite the overhang", railing_at_structural_line)

	var slab_bottom: float = deck_top - house.porch_floor_thickness
	var under_strip := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.y - slab_bottom) < EPS and absf(b.y - slab_bottom) < EPS and absf(c.y - slab_bottom) < EPS
	var under_area: float = MeshChecks.facing_area(mesh, "porch_floor", Vector3.DOWN, under_strip)
	_check("porch_overhang_mesh", "overhang underside closed %.3f == 0.82" % under_area, absf(under_area - 0.82) < 1e-2)


func _test_porch_stairs_overhang_mesh() -> void:
	var house := _porch_house()
	house.porch_has_roof = false
	house.porch_floor_overhang = 0.1
	var floor_data: FloorData = house.floors[0]
	var stairs := WallDetail.create(WallDetail.DetailType.STAIRS)
	stairs.cell = Vector2i(0, 1)
	stairs.direction = WallDetail.EdgeDir.SOUTH
	floor_data.set_wall_detail(stairs)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("porch_stairs_overhang_mesh", mesh, _check)

	var deck_top: float = -DetailConstants.PORCH_DROP
	var slab_bottom: float = deck_top - house.porch_floor_thickness
	var step1_top: float = deck_top - 0.175

	var flap_probe: float = MeshChecks.surface_height_at(mesh, "porch_floor", Vector2(1.0, 4.05), 1.0)
	_check("porch_stairs_overhang_mesh", "deck overhangs over the stairs opening (%.4f == %.4f)" % [flap_probe, deck_top], absf(flap_probe - deck_top) < EPS)
	var under_stairs_flap := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.y - slab_bottom) < EPS and absf(b.y - slab_bottom) < EPS and absf(c.y - slab_bottom) < EPS \
			and a.z > 3.99 and b.z > 3.99 and c.z > 3.99 and a.x < 2.01 and b.x < 2.01 and c.x < 2.01
	var under_area: float = MeshChecks.facing_area(mesh, "porch_floor", Vector3.DOWN, under_stairs_flap)
	_check("porch_stairs_overhang_mesh", "deck overhang underside closed over the stairs %.3f == 0.205" % under_area, absf(under_area - 0.205) < 1e-3)

	var front_probe: float = MeshChecks.surface_height_at(mesh, "porch_floor", Vector2(1.0, 4.35), 1.0)
	_check("porch_stairs_overhang_mesh", "tread overhangs its foundation front (%.4f == %.4f)" % [front_probe, step1_top], absf(front_probe - step1_top) < EPS)
	var side_probe: float = MeshChecks.surface_height_at(mesh, "porch_floor", Vector2(2.05, 4.2), 1.0)
	_check("porch_stairs_overhang_mesh", "tread overhangs its foundation side (%.4f == %.4f)" % [side_probe, step1_top], absf(side_probe - step1_top) < EPS)

	var tread_front := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z - 4.4) < EPS and absf(b.z - 4.4) < EPS and absf(c.z - 4.4) < EPS
	var tread_front_area: float = MeshChecks.facing_area(mesh, "porch_floor", Vector3(0, 0, 1), tread_front)
	_check("porch_stairs_overhang_mesh", "overhung tread front face %.3f == 0.33" % tread_front_area, absf(tread_front_area - 2.2 * house.porch_floor_thickness) < 1e-3)
	var at_step2_riser := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z - 4.3) < EPS and absf(b.z - 4.3) < EPS and absf(c.z - 4.3) < EPS
	var at_band_line := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return absf(a.z - 4.1) < EPS and absf(b.z - 4.1) < EPS and absf(c.z - 4.1) < EPS
	_check("porch_stairs_overhang_mesh", "foundation riser stays on the structural line", MeshChecks.facing_area(mesh, "foundation", Vector3(0, 0, 1), at_step2_riser) > EPS)
	_check("porch_stairs_overhang_mesh", "no foundation at the overhung tread front", MeshChecks.facing_area(mesh, "foundation", Vector3(0, 0, 1), tread_front) < EPS)
	_check("porch_stairs_overhang_mesh", "no foundation at the overhung deck band", MeshChecks.facing_area(mesh, "foundation", Vector3(0, 0, 1), at_band_line) < EPS)


func _test_porch_roof_mesh() -> void:
	var house := _porch_house()
	house.porch_has_roof = true
	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("porch_roof", mesh, _check)

	var samples: Array[Vector2] = [Vector2(2.2, 3.4), Vector2(2.0, 4.0), Vector2(1.0, 3.9)]
	var covered := true
	var worst: float = 0.0
	for sample in samples:
		var y: float = MeshChecks.surface_height_at(mesh, "roof", sample, 1.0)
		if y == -INF:
			covered = false
			continue
		worst = maxf(worst, absf(y - _roof_height_at_offset(house, 4.5 - sample.y, 3.0)))
	_check("porch_roof", "roof covers the porch", covered)
	_check("porch_roof", "porch roof is the plain house roof (worst %.4f)" % worst, worst < EPS)

	var roof_arrays: Array = MeshChecks.surface_arrays(mesh, "roof")
	var max_z: float = -INF
	for v in roof_arrays[Mesh.ARRAY_VERTEX]:
		max_z = maxf(max_z, v.z)
	_check("porch_roof", "eave overhangs the porch outline", absf(max_z - (4.0 + house.wall_thickness * 0.5 + house.roof_overhang)) < EPS)

	var floor_data: FloorData = house.floors[0]
	var probe_accumulator := SurfaceAccumulator.new()
	var probe_infos: Array[Dictionary] = [{
		"floor_data": floor_data, "base_y": 0.0, "top_y": floor_data.height,
		"roof_cells": PorchBuilder.roof_cells(house, floor_data),
	}]
	var models: Array[Dictionary] = RoofBuilder.build(house, probe_infos, probe_accumulator)
	var region_offset: float = house.wall_thickness * 0.5 - RoofConstants.WALL_CLIP_EMBED
	var expected_min_y: float = INF
	for loop in Footprint.trace_loops(floor_data.porch_cells, house.level_cell_size):
		for region in Geometry2D.offset_polygon(loop.points, region_offset, Geometry2D.JOIN_MITER):
			expected_min_y = minf(expected_min_y, RoofSurface.min_height_over_region(models, region, floor_data.level))
	var expected_ceiling_y: float = expected_min_y - DetailConstants.PORCH_CEILING_DROP

	var ceiling_samples: Array[Vector2] = [Vector2(2.2, 3.4), Vector2(2.0, 3.0), Vector2(1.0, 3.5), Vector2(0.3, 2.3)]
	var ceiling_exists := true
	var ceiling_worst: float = 0.0
	var clears_roof := true
	for sample in ceiling_samples:
		var ceiling_y: float = MeshChecks.surface_height_at(mesh, "roof_underlayment", sample, -1.0)
		if ceiling_y == -INF:
			ceiling_exists = false
			continue
		ceiling_worst = maxf(ceiling_worst, absf(ceiling_y - expected_ceiling_y))
		var roof_y: float = MeshChecks.surface_height_at(mesh, "roof", sample, 1.0)
		if roof_y != -INF and ceiling_y > roof_y - EPS:
			clears_roof = false
	_check("porch_roof", "porch ceiling exists", ceiling_exists)
	_check("porch_roof", "ceiling is flat at the expected clearance height (worst %.4f)" % ceiling_worst, ceiling_worst < EPS)
	_check("porch_roof", "ceiling clears the roof above it", clears_roof)

	var soffit_y: float = _roof_height_at_offset(house, 0.0, 3.0) - house.roof_fascia_height
	var expected_band_top: float = expected_ceiling_y + DetailConstants.POST_ROOF_EMBED
	var trim: Array = MeshChecks.surface_arrays(mesh, "trim")
	var band_min_y: float = INF
	var band_max_y: float = -INF
	for v in trim[Mesh.ARRAY_VERTEX]:
		if absf(v.z - 4.0) < 0.01 and v.x > -0.01 and v.x < 4.01 and v.y > 2.0:
			band_min_y = minf(band_min_y, v.y)
			band_max_y = maxf(band_max_y, v.y)
	_check("porch_roof", "perimeter band sits on the soffit line", absf(band_min_y - soffit_y) < EPS)
	_check("porch_roof", "perimeter band reaches exactly to the ceiling", absf(band_max_y - expected_band_top) < EPS)

	var posts: Array = MeshChecks.surface_arrays(mesh, "porch_post")
	var max_post_y: float = -INF
	for v in posts[Mesh.ARRAY_VERTEX]:
		max_post_y = maxf(max_post_y, v.y)
	_check("porch_roof", "posts reach the ceiling exactly (%.4f vs %.4f)" % [max_post_y, expected_band_top], absf(max_post_y - expected_band_top) < EPS)


func _test_all_details_end_to_end() -> void:
	var house := HouseData.new()
	house.level_cell_size = 2.0
	house.porch_has_roof = true
	house.porch_railing_style = HouseData.RailingStyle.CROSS

	var ground := FloorData.new()
	ground.level = 0
	ground.height = 3.0
	for x in range(3):
		for y in range(2):
			ground.add_cell(Vector2i(x, y))
	ground.add_porch_cell(Vector2i(0, 2))
	ground.add_porch_cell(Vector2i(1, 2))
	house.add_floor(ground)

	var upper := FloorData.new()
	upper.level = 1
	upper.height = 3.0
	for x in range(3):
		upper.add_cell(Vector2i(x, 0))
	house.add_floor(upper)

	var door := WallDetail.create(WallDetail.DetailType.DOOR, WallDetail.DoorStyle.PANELED)
	door.cell = Vector2i(0, 1)
	door.direction = WallDetail.EdgeDir.SOUTH
	ground.set_wall_detail(door)

	var garage := WallDetail.create(WallDetail.DetailType.GARAGE_DOOR)
	garage.cell = Vector2i(1, 0)
	garage.direction = WallDetail.EdgeDir.NORTH
	garage.span = 2
	garage.apply_span_defaults()
	ground.set_wall_detail(garage)

	var ground_window := WallDetail.create(WallDetail.DetailType.WINDOW, WallDetail.WindowStyle.WIDE)
	ground_window.cell = Vector2i(0, 0)
	ground_window.direction = WallDetail.EdgeDir.WEST
	ground.set_wall_detail(ground_window)

	var stairs := WallDetail.create(WallDetail.DetailType.STAIRS)
	stairs.cell = Vector2i(0, 2)
	stairs.direction = WallDetail.EdgeDir.SOUTH
	ground.set_wall_detail(stairs)

	var upper_window := WallDetail.create(WallDetail.DetailType.WINDOW, WallDetail.WindowStyle.SINGLE)
	upper_window.cell = Vector2i(0, 0)
	upper_window.direction = WallDetail.EdgeDir.NORTH
	upper.set_wall_detail(upper_window)

	var dormer := DormerData.new()
	dormer.cell = Vector2i(1, 0)
	dormer.direction = WallDetail.EdgeDir.NORTH
	upper.dormers.append(dormer)

	var chimney := ChimneyData.new()
	chimney.cell = Vector2i(2, 0)
	upper.chimneys.append(chimney)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("all_details", mesh, _check)
	for slot in [
		"siding", "trim", "foundation", "roof", "roof_underlayment",
		"window_frame", "glass", "door", "garage_door",
		"porch_floor", "porch_railing", "porch_post", "porch_baluster", "chimney",
		"gutter",
	]:
		_check("all_details", "slot '%s' present" % slot, MeshChecks.find_surface(mesh, slot) >= 0)


func _roof_height_at_offset(house: HouseData, offset: float, wall_top: float) -> float:
	var drop_run: float = house.roof_overhang - (house.corner_trim_width + RoofConstants.WALL_CLEARANCE_MARGIN)
	return wall_top + (offset - drop_run) * tan(deg_to_rad(house.roof_pitch_degrees))


func _test_chimney_mesh() -> void:
	var house := _bar_house()
	var floor_data: FloorData = house.floors[0]
	var chimney := ChimneyData.new()
	chimney.cell = Vector2i(1, 0)
	floor_data.chimneys.append(chimney)
	var stray := ChimneyData.new()
	stray.cell = Vector2i(5, 5)
	floor_data.chimneys.append(stray)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("chimney_mesh", mesh, _check)

	var ridge_y: float = _roof_height_at_offset(house, 1.5, 3.0)
	var arrays: Array = MeshChecks.surface_arrays(mesh, "chimney")
	_check("chimney_mesh", "chimney surface exists", not arrays.is_empty())
	if arrays.is_empty():
		return

	var min_y: float = INF
	var max_y: float = -INF
	var max_x: float = -INF
	for v in arrays[Mesh.ARRAY_VERTEX]:
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)
		max_x = maxf(max_x, v.x)
	_check("chimney_mesh", "shaft base buried below the ridge", absf(min_y - (ridge_y - DetailConstants.CHIMNEY_EMBED)) < EPS)
	_check("chimney_mesh", "crown top above the ridge", absf(max_y - (ridge_y + chimney.extra_height + DetailConstants.CHIMNEY_CAP_HEIGHT)) < EPS)
	_check("chimney_mesh", "crown overhangs the shaft", absf(max_x - (3.0 + chimney.width * 0.5 + DetailConstants.CHIMNEY_CAP_OVERHANG)) < EPS)
	_check("chimney_mesh", "stray chimney skipped", max_x < 4.0)


func _test_dormer_mesh() -> void:
	var house := _bar_house()
	var floor_data: FloorData = house.floors[0]
	var dormer := DormerData.new()
	dormer.cell = Vector2i(1, 0)
	dormer.direction = WallDetail.EdgeDir.NORTH
	floor_data.dormers.append(dormer)

	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("dormer_mesh", mesh, _check)

	var tan_pitch: float = tan(deg_to_rad(house.roof_pitch_degrees))
	var roof_y_front: float = _roof_height_at_offset(house, 1.2, 3.0)
	var base_y: float = roof_y_front - DetailConstants.DORMER_EMBED
	var eave_y: float = base_y + dormer.face_height
	var ridge_y: float = eave_y + dormer.width * 0.5 * tan_pitch

	_check("dormer_mesh", "dormer window glass exists", MeshChecks.find_surface(mesh, "glass") >= 0)

	var siding: Array = MeshChecks.surface_arrays(mesh, "siding")
	var region_min_y: float = INF
	var region_max_y: float = -INF
	for v in siding[Mesh.ARRAY_VERTEX]:
		if v.y > 3.05 and v.x > 2.0 and v.x < 4.0 and v.z > -0.5 and v.z < 2.0:
			region_min_y = minf(region_min_y, v.y)
			region_max_y = maxf(region_max_y, v.y)
	_check("dormer_mesh", "dormer walls exist above the wall top", region_max_y > 3.05)
	_check("dormer_mesh", "dormer base buried below the roof surface", absf(region_min_y - base_y) < EPS and base_y < roof_y_front - 0.1)
	_check("dormer_mesh", "gable apex at the dormer ridge", absf(region_max_y - ridge_y) < EPS)
	_check("dormer_mesh", "dormer face exposed above the roof", eave_y > roof_y_front + 0.5)

	var roof: Array = MeshChecks.surface_arrays(mesh, "roof")
	var roof_max_y: float = -INF
	var dormer_roof_min_z: float = INF
	for v in roof[Mesh.ARRAY_VERTEX]:
		roof_max_y = maxf(roof_max_y, v.y)
		if v.x > 2.0 and v.x < 4.0 and v.y > eave_y - 0.5:
			dormer_roof_min_z = minf(dormer_roof_min_z, v.z)
	_check("dormer_mesh", "dormer ridge is the mesh's highest roof", absf(roof_max_y - ridge_y) < EPS)
	var expected_front_z: float = 0.7 - (house.wall_thickness * 0.5 + DetailConstants.DORMER_ROOF_OVERHANG)
	_check("dormer_mesh", "dormer roof overhangs the front face", absf(dormer_roof_min_z - expected_front_z) < EPS)

	house.roof_pitch_degrees = 5.0
	var flat_mesh: ArrayMesh = HouseMeshBuilder.build(house)
	_check("dormer_mesh", "dormer skipped below the minimum pitch", MeshChecks.find_surface(flat_mesh, "glass") == -1)


func _check(shape: String, what: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("FAIL [%s] %s" % [shape, what])
