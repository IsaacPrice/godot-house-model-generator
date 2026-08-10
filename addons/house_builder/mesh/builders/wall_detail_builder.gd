@tool
class_name WallDetailBuilder
extends RefCounted


static func build(house: HouseData, openings: Array[Dictionary], accumulator: SurfaceAccumulator) -> void:
	for opening in openings:
		match (opening["detail"] as WallDetail).type:
			WallDetail.DetailType.WINDOW:
				WindowBuilder.build(house, opening, accumulator)
			WallDetail.DetailType.DOOR:
				DoorBuilder.build(house, opening, accumulator)
			WallDetail.DetailType.GARAGE_DOOR:
				GarageDoorBuilder.build(house, opening, accumulator)
