@tool
class_name WallDetailBuilder
extends RefCounted


static func build(
	house: HouseData, openings: Array[Dictionary], accumulator: SurfaceAccumulator,
	rigs: Array[Dictionary] = []
) -> void:
	for opening in openings:
		var detail: WallDetail = opening["detail"]
		match detail.type:
			WallDetail.DetailType.WINDOW:
				WindowBuilder.build(house, opening, accumulator)
			WallDetail.DetailType.DOOR:
				DoorBuilder.build(house, opening, accumulator)
			WallDetail.DetailType.GARAGE_DOOR:
				GarageDoorBuilder.build(house, opening, accumulator)
		InteriorCasing.build(house, opening, accumulator)

		if detail.is_animated():
			var rig: Dictionary = DoorRig.build(house, opening, rigs.size())
			if not rig.is_empty():
				rigs.append(rig)
