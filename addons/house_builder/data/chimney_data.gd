@tool
class_name ChimneyData
extends Resource


@export var cell: Vector2i = Vector2i.ZERO

## Plan x extent of the shaft, in meters.
@export_range(0.2, 2.0, 0.01, "suffix:m") var width: float = 0.6

## Plan z extent of the shaft, in meters.
@export_range(0.2, 2.0, 0.01, "suffix:m") var depth: float = 0.6

## How far the shaft top rises above the roof surface at the chimney center.
@export_range(0.2, 3.0, 0.01, "suffix:m") var extra_height: float = 0.8
