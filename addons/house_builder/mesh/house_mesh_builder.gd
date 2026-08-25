@tool
class_name HouseMeshBuilder
extends RefCounted


static func build(house: HouseData) -> ArrayMesh:
	return build_with_roof_models(house)["mesh"]


static func build_with_roof_models(house: HouseData) -> Dictionary:
	var accumulator: SurfaceAccumulator = house.accumulator()

	if house.floors.is_empty():
		return {"mesh": accumulator.commit(), "roof_models": [] as Array[Dictionary]}

	var ground_reaching_posts: Array[Dictionary] = TrimBuilder.build_all(house, accumulator)

	var floor_base_y: float = 0.0
	var floor_infos: Array[Dictionary] = []
	var ground_openings: Array[Dictionary] = []
	for floor_index in range(house.floors.size()):
		var floor_data: FloorData = house.floors[floor_index]
		var openings: Array[Dictionary] = WallOpenings.collect(house, floor_data, floor_base_y, floor_index == 0)
		if floor_index == 0:
			ground_openings = openings
		var floor_below: FloorData = house.floors[floor_index - 1] if floor_index > 0 else null
		WallBuilder.build(house, floor_data, floor_base_y, accumulator, openings, floor_index == 0, floor_below)
		WallDetailBuilder.build(house, openings, accumulator)
		floor_base_y += floor_data.height
		floor_infos.append({"floor_data": floor_data, "base_y": floor_base_y - floor_data.height, "top_y": floor_base_y})

	FoundationBuilder.build(house, house.floors[0], accumulator, ground_reaching_posts, ground_openings)

	var floor_above_ground: FloorData = house.floors[1] if house.floors.size() > 1 else null
	floor_infos[0]["roof_cells"] = PorchBuilder.roof_cells(house, house.floors[0], floor_above_ground)
	var roof_models: Array[Dictionary] = RoofBuilder.build(house, floor_infos, accumulator)

	PorchBuilder.build(house, house.floors[0], accumulator, roof_models, floor_above_ground)
	for floor_data in house.floors:
		DormerBuilder.build(house, floor_data, roof_models, accumulator)
		ChimneyBuilder.build(house, floor_data, roof_models, accumulator)

	return {"mesh": accumulator.commit(), "roof_models": roof_models}
