@tool
class_name WallDetail
extends Resource


enum DetailType { WINDOW, DOOR, GARAGE_DOOR, STAIRS }
enum EdgeDir { NORTH, EAST, SOUTH, WEST }
enum WindowStyle { SINGLE, WIDE, SMALL }
enum DoorStyle { PLAIN, PANELED }

const NORMALS := {
	EdgeDir.NORTH: Vector2(0, -1),
	EdgeDir.EAST: Vector2(1, 0),
	EdgeDir.SOUTH: Vector2(0, 1),
	EdgeDir.WEST: Vector2(-1, 0),
}

const OPPOSITE := {
	EdgeDir.NORTH: EdgeDir.SOUTH,
	EdgeDir.SOUTH: EdgeDir.NORTH,
	EdgeDir.EAST: EdgeDir.WEST,
	EdgeDir.WEST: EdgeDir.EAST,
}

const SPAN_STEP := {
	EdgeDir.NORTH: Vector2i(1, 0),
	EdgeDir.SOUTH: Vector2i(1, 0),
	EdgeDir.EAST: Vector2i(0, 1),
	EdgeDir.WEST: Vector2i(0, 1),
}

@export var type: DetailType = DetailType.WINDOW

## Grid cell owning the edge this detail sits on (a floor cell for openings,
## a porch cell for STAIRS).
@export var cell: Vector2i = Vector2i.ZERO

## Which of the cell's four edges the detail sits on.
@export var direction: EdgeDir = EdgeDir.NORTH

## WindowStyle for WINDOW, DoorStyle for DOOR; unused otherwise.
@export var style: int = 0

## How many adjacent colinear edges this detail covers (dragged in the grid
## editor, or set via the inspector's Span control).
@export_range(1, DetailConstants.MAX_DETAIL_SPAN) var span: int = 1

## Opening width along the wall, in meters. Not clamped to the segment's
## fit here - an opening wider than its run allows still places; it just
## renders clamped to fit (see WallOpenings.collect). The range is sized
## for a span-12 run at the largest cell size (12 * 4.0 m).
@export_range(0.3, 50.0, 0.01, "suffix:m") var width: float = 1.2

## Opening height, in meters. Not clamped to the floor's header room here
## either - see WallOpenings.collect.
@export_range(0.3, 20.0, 0.01, "suffix:m") var height: float = 1.4

## Bottom of the opening above the floor base, in meters (0 for doors).
@export_range(0.0, 20.0, 0.01, "suffix:m") var sill_height: float = 0.9

## STAIRS: rise of each individual step, in meters. Unused otherwise.
@export_range(0.05, 0.4, 0.005, "suffix:m") var stair_step_height: float = 0.18

## STAIRS: run (tread depth) of each individual step, in meters. Unused
## otherwise.
@export_range(0.1, 1.0, 0.01, "suffix:m") var stair_step_depth: float = 0.3

## STAIRS: whether a railing runs alongside the steps, matching the porch's
## own railing style/height/materials. Unused otherwise.
@export var stair_has_railing: bool = false


static func create(detail_type: DetailType, detail_style: int = 0, house: HouseData = null) -> WallDetail:
	var detail := WallDetail.new()
	detail.type = detail_type
	detail.style = detail_style

	match detail_type:
		DetailType.WINDOW:
			detail.apply_window_style_defaults(house)
		DetailType.DOOR:
			detail.width = house.door_default_width if house else 1.0
			detail.height = house.door_default_height if house else 2.1
			detail.sill_height = 0.0
		DetailType.GARAGE_DOOR:
			detail.width = house.garage_door_default_width if house else 1.5
			detail.height = house.garage_door_default_height if house else 2.2
			detail.sill_height = 0.0
		DetailType.STAIRS:
			detail.stair_step_height = house.stair_default_step_height if house else 0.18
			detail.stair_step_depth = house.stair_default_step_depth if house else 0.3
			detail.stair_has_railing = house.stair_default_has_railing if house else false

	return detail


func spanned_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = [cell]
	for i in range(1, span):
		cells.append(cell + SPAN_STEP[direction] * i)
	return cells


func covers(other_cell: Vector2i, other_direction: int) -> bool:
	return other_direction == direction and other_cell in spanned_cells()


func apply_window_style_defaults(house: HouseData = null) -> void:
	match style:
		WindowStyle.WIDE:
			width = house.window_wide_default_width if house else 1.5
			height = house.window_wide_default_height if house else 1.4
			sill_height = house.window_wide_default_sill if house else 0.9
		WindowStyle.SMALL:
			width = house.window_small_default_width if house else 0.6
			height = house.window_small_default_height if house else 0.6
			sill_height = house.window_small_default_sill if house else 1.5
		_:
			width = house.window_single_default_width if house else 1.2
			height = house.window_single_default_height if house else 1.4
			sill_height = house.window_single_default_sill if house else 0.9


func apply_span_defaults(cell_size: float = 2.0) -> void:
	if span > 1:
		width = DetailRules.max_opening_width(cell_size, span)
	elif type == DetailType.GARAGE_DOOR:
		width = 1.5


static func endpoints(edge_cell: Vector2i, edge_direction: int, cell_size: float) -> PackedVector2Array:
	var x := float(edge_cell.x)
	var y := float(edge_cell.y)
	var points: PackedVector2Array
	match edge_direction:
		EdgeDir.NORTH:
			points = PackedVector2Array([Vector2(x, y), Vector2(x + 1, y)])
		EdgeDir.SOUTH:
			points = PackedVector2Array([Vector2(x, y + 1), Vector2(x + 1, y + 1)])
		EdgeDir.WEST:
			points = PackedVector2Array([Vector2(x, y), Vector2(x, y + 1)])
		EdgeDir.EAST:
			points = PackedVector2Array([Vector2(x + 1, y), Vector2(x + 1, y + 1)])
	return PackedVector2Array([points[0] * cell_size, points[1] * cell_size])
