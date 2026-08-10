@tool
class_name DormerData
extends Resource


@export var cell: Vector2i = Vector2i.ZERO

## A WallDetail.EdgeDir value - which of the cell's edges the dormer faces.
@export var direction: int = 0

## Dormer width across the slope, in meters.
@export_range(0.6, 4.0, 0.01, "suffix:m") var width: float = 1.6

## Plan distance from the outer wall face up the slope to the dormer's front
## face, in meters.
@export_range(0.1, 4.0, 0.01, "suffix:m") var up_slope_offset: float = 0.8

## Height of the dormer's front wall from its (hidden) base to the eaves.
@export_range(0.5, 3.0, 0.01, "suffix:m") var face_height: float = 1.4

## A WallDetail.WindowStyle value for the window in the dormer's face.
@export var window_style: int = WallDetail.WindowStyle.SMALL

## How many adjacent colinear edges this dormer's anchor covers (dragged in
## the grid editor, or set via the inspector's Span control). Unlike
## WallDetail, `width` is never derived from span here - span only changes
## which/how-many boundary edges the anchor is validated against and where
## its center sits.
@export_range(1, DetailConstants.MAX_DETAIL_SPAN) var span: int = 1


func spanned_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = [cell]
	for i in range(1, span):
		cells.append(cell + WallDetail.SPAN_STEP[direction] * i)
	return cells
