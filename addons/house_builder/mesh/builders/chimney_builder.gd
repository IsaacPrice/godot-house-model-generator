@tool
class_name ChimneyBuilder
extends RefCounted


const SLOT_CHIMNEY := "chimney"


static func build(house: HouseData, floor_data: FloorData, roof_models: Array[Dictionary], accumulator: SurfaceAccumulator) -> void:
	var cell_size: float = house.level_cell_size
	for chimney in floor_data.chimneys:
		if not DetailRules.chimney_cell_valid(chimney, floor_data):
			push_warning("House builder: skipping chimney at %s - its cell is not part of floor level %d." % [chimney.cell, floor_data.level])
			continue

		var center: Vector2 = (Vector2(chimney.cell) + Vector2(0.5, 0.5)) * cell_size
		var roof_y: float = RoofSurface.height_at(roof_models, center)
		if roof_y == -INF:
			push_warning("House builder: skipping chimney at %s - no roof surface above it." % chimney.cell)
			continue

		var half := Vector2(chimney.width, chimney.depth) * 0.5
		var top: float = roof_y + chimney.extra_height
		BoxBuilder.build(
			accumulator, SLOT_CHIMNEY, house.chimney_material,
			center - half, center + half,
			roof_y - DetailConstants.CHIMNEY_EMBED, top
		)

		var crown_half: Vector2 = half + Vector2.ONE * DetailConstants.CHIMNEY_CAP_OVERHANG
		BoxBuilder.build(
			accumulator, SLOT_CHIMNEY, house.chimney_material,
			center - crown_half, center + crown_half,
			top, top + DetailConstants.CHIMNEY_CAP_HEIGHT
		)
