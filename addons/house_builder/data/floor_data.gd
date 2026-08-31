@tool
class_name FloorData
extends Resource

@export var level: int = 0
@export var height: float = 3.0

@export var cells: Array[Vector2i] = []

## Porch deck cells, painted beside the house cells. Only meshed on the
## house's lowest floor.
@export var porch_cells: Array[Vector2i] = []

## Sidewalk/driveway slab cells, painted beside the house cells at the
## grade level. Only meshed on the house's lowest floor, as a separate
## mesh (SidewalkBuilder).
@export var sidewalk_cells: Array[Vector2i] = []

## House cells whose floor is laid at grade instead of at the level's own
## base - garage bays, so a garage door opening meets a slab rather than the
## cut edge of the floor deck. Only meshed on the house's lowest floor.
@export var garage_cells: Array[Vector2i] = []

## Windows/doors/garage doors on this floor's walls, plus STAIRS runs on
## porch boundary edges. One detail per (cell, direction) edge.
@export var wall_details: Array[WallDetail] = []

## Dormers on the roof sections above this floor's walls.
@export var dormers: Array[DormerData] = []

## Exterior walls whose roof section ends in a gable instead of a hip. One
## marker covers the whole straight wall run containing its edge.
@export var gables: Array[GableData] = []

## Chimneys rising through the roof above this floor's cells.
@export var chimneys: Array[ChimneyData] = []


func add_cell(cell: Vector2i):
	if !cells.has(cell):
		cells.append(cell)

func remove_cell(cell: Vector2i):
	cells.erase(cell)

func has_cell(cell: Vector2i) -> bool:
	return cells.has(cell)

func add_porch_cell(cell: Vector2i):
	if !porch_cells.has(cell):
		porch_cells.append(cell)

func remove_porch_cell(cell: Vector2i):
	porch_cells.erase(cell)

func has_porch_cell(cell: Vector2i) -> bool:
	return porch_cells.has(cell)

func add_sidewalk_cell(cell: Vector2i):
	if !sidewalk_cells.has(cell):
		sidewalk_cells.append(cell)

func remove_sidewalk_cell(cell: Vector2i):
	sidewalk_cells.erase(cell)

func has_sidewalk_cell(cell: Vector2i) -> bool:
	return sidewalk_cells.has(cell)

func add_garage_cell(cell: Vector2i):
	if !garage_cells.has(cell):
		garage_cells.append(cell)

func remove_garage_cell(cell: Vector2i):
	garage_cells.erase(cell)

func has_garage_cell(cell: Vector2i) -> bool:
	return garage_cells.has(cell)

func get_wall_detail(cell: Vector2i, direction: int) -> WallDetail:
	for detail in wall_details:
		if detail.covers(cell, direction):
			return detail
	return null

func set_wall_detail(detail: WallDetail) -> void:
	for spanned in detail.spanned_cells():
		var existing: WallDetail = get_wall_detail(spanned, detail.direction)
		if existing != null and existing != detail:
			wall_details.erase(existing)
	if !wall_details.has(detail):
		wall_details.append(detail)

func remove_wall_detail(cell: Vector2i, direction: int) -> void:
	var detail: WallDetail = get_wall_detail(cell, direction)
	if detail != null:
		wall_details.erase(detail)

func duplicate_data() -> FloorData:
	var copy := FloorData.new()
	copy.level = level
	copy.height = height
	copy.cells = cells.duplicate()
	copy.porch_cells = porch_cells.duplicate()
	copy.sidewalk_cells = sidewalk_cells.duplicate()
	copy.garage_cells = garage_cells.duplicate()
	for detail in wall_details:
		copy.wall_details.append(detail.duplicate())
	for dormer in dormers:
		copy.dormers.append(dormer.duplicate())
	for gable in gables:
		copy.gables.append(gable.duplicate())
	for chimney in chimneys:
		copy.chimneys.append(chimney.duplicate())
	return copy
