extends SceneTree


const EPS := 1e-3

const HOUSE_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
const PORCH_CELLS: Array[Vector2i] = [Vector2i(0, 2), Vector2i(1, 2)]

const WEST_PORCH := Vector2(1.0, 5.0)
const EAST_PORCH := Vector2(3.0, 5.0)

var failures: int = 0


func _init() -> void:
	_test_roof_covered_porch()
	_test_storey_covered_porch()
	_test_partly_covered_porch()
	_test_unroofed_porch_under_storey()
	_test_no_downspouts_over_a_porch()

	if failures == 0:
		print("ALL PORCH COVER TESTS PASSED")
		quit(0)
	else:
		print("%d PORCH COVER TEST FAILURE(S)" % failures)
		quit(1)


func _porch_house(upper_cells: Array[Vector2i]) -> HouseData:
	var house := HouseData.new()
	house.level_cell_size = 2.0

	var ground := FloorData.new()
	ground.level = 0
	ground.height = 3.0
	for cell in HOUSE_CELLS:
		ground.add_cell(cell)
	for cell in PORCH_CELLS:
		ground.add_porch_cell(cell)
	house.add_floor(ground)

	if not upper_cells.is_empty():
		var upper := FloorData.new()
		upper.level = 1
		upper.height = 3.0
		for cell in upper_cells:
			upper.add_cell(cell)
		house.add_floor(upper)

	return house


func _covering_floor() -> Array[Vector2i]:
	var cells: Array[Vector2i] = HOUSE_CELLS.duplicate()
	cells.append_array(PORCH_CELLS)
	return cells


func _ceiling_over(mesh: ArrayMesh, plan: Vector2) -> float:
	return MeshChecks.surface_height_at(mesh, "roof_underlayment", plan, -1.0)


func _post_top(mesh: ArrayMesh) -> float:
	return _extreme_y(mesh, "porch_post", true)


func _extreme_y(mesh: ArrayMesh, slot: String, want_max: bool) -> float:
	var arrays: Array = MeshChecks.surface_arrays(mesh, slot)
	if arrays.is_empty():
		return -INF
	var best: float = -INF if want_max else INF
	for v in arrays[Mesh.ARRAY_VERTEX]:
		best = maxf(best, v.y) if want_max else minf(best, v.y)
	return best


func _roof_levels(built: Dictionary) -> Array[int]:
	var levels: Array[int] = []
	for entry in built["roof_models"]:
		levels.append(entry["floor_level"])
	return levels


func _test_roof_covered_porch() -> void:
	var built: Dictionary = HouseMeshBuilder.build_with_roof_models(_porch_house([]))
	var mesh: ArrayMesh = built["mesh"]
	MeshChecks.check_windings("roof_covered", mesh, _check)

	var ceiling: float = _ceiling_over(mesh, WEST_PORCH)
	_check("roof_covered", "porch has a ceiling under the roof", ceiling > 2.0)
	_check("roof_covered", "both porch bays share the roof ceiling", absf(_ceiling_over(mesh, EAST_PORCH) - ceiling) < EPS)
	_check("roof_covered", "posts reach the ceiling", absf(_post_top(mesh) - (ceiling + DetailConstants.POST_ROOF_EMBED)) < EPS)
	_check("roof_covered", "the lowest floor is roofed", _roof_levels(built).has(0))


func _test_storey_covered_porch() -> void:
	var built: Dictionary = HouseMeshBuilder.build_with_roof_models(_porch_house(_covering_floor()))
	var mesh: ArrayMesh = built["mesh"]
	MeshChecks.check_windings("storey_covered", mesh, _check)

	var expected: float = 3.0 - DetailConstants.PORCH_SOFFIT_DROP
	_check("storey_covered", "west bay has a soffit, not open sky", _ceiling_over(mesh, WEST_PORCH) != -INF)
	_check("storey_covered", "east bay has a soffit, not open sky", _ceiling_over(mesh, EAST_PORCH) != -INF)
	_check("storey_covered", "soffit hangs below the storey above", absf(_ceiling_over(mesh, WEST_PORCH) - expected) < EPS)
	_check("storey_covered", "posts carry the storey", absf(_post_top(mesh) - (expected + DetailConstants.POST_ROOF_EMBED)) < EPS)
	_check("storey_covered", "no roof is built at the covered level", not _roof_levels(built).has(0))

	var band_top: float = _extreme_y(mesh, "trim", true)
	_check("storey_covered", "rim band closes up to the storey's base", band_top > 3.0 - EPS)


func _test_partly_covered_porch() -> void:
	var upper: Array[Vector2i] = HOUSE_CELLS.duplicate()
	upper.append(Vector2i(0, 2))
	var built: Dictionary = HouseMeshBuilder.build_with_roof_models(_porch_house(upper))
	var mesh: ArrayMesh = built["mesh"]
	MeshChecks.check_windings("partly_covered", mesh, _check)

	var covered: float = _ceiling_over(mesh, WEST_PORCH)
	var open: float = _ceiling_over(mesh, EAST_PORCH)
	_check("partly_covered", "covered bay is soffited by the storey", absf(covered - (3.0 - DetailConstants.PORCH_SOFFIT_DROP)) < EPS)
	_check("partly_covered", "open bay is ceilinged by the roof", open != -INF and open > covered)
	_check("partly_covered", "the two bays get different ceilings", absf(open - covered) > EPS)
	_check("partly_covered", "a roof still covers the exposed bay", _roof_levels(built).has(0))


func _test_unroofed_porch_under_storey() -> void:
	var house: HouseData = _porch_house(_covering_floor())
	house.porch_has_roof = false
	var mesh: ArrayMesh = HouseMeshBuilder.build(house)
	MeshChecks.check_windings("unroofed_under_storey", mesh, _check)

	var expected: float = 3.0 - DetailConstants.PORCH_SOFFIT_DROP
	_check("unroofed_under_storey", "the storey still soffits the porch", absf(_ceiling_over(mesh, WEST_PORCH) - expected) < EPS)


func _test_no_downspouts_over_a_porch() -> void:
	var built: Dictionary = HouseMeshBuilder.build_with_roof_models(_porch_house(_covering_floor()))
	var over_porch: int = 0
	var total: int = 0
	for entry in built["roof_models"]:
		for spout in (entry["model"] as RoofModel).downspouts:
			total += 1
			if spout.wall.y > 4.0 + EPS:
				over_porch += 1
	_check("downspouts", "the storey above the porch still gets downspouts elsewhere", total > 0)
	_check("downspouts", "no downspout runs down through the porch", over_porch == 0)


func _check(group: String, name: String, condition: bool) -> void:
	if condition:
		print("PASS [%s] %s" % [group, name])
	else:
		failures += 1
		printerr("FAIL [%s] %s" % [group, name])
