@tool
class_name GableData
extends Resource


## Grid cell owning the edge (a floor cell, or a porch cell when the porch
## joins the roof footprint).
@export var cell: Vector2i = Vector2i.ZERO

## A WallDetail.EdgeDir value - which of the cell's four edges the gable
## wall lies on.
@export var direction: int = 0
