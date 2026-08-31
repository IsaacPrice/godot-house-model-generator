@tool
class_name GridEditor
extends Control


enum Tool { CELLS, PORCH, SIDEWALK, BAY, WINDOW, DOOR, GARAGE, STAIRS, DORMER, CHIMNEY, GABLE, ERASE }


@export var grid_width: int = 10:
	set(value):
		grid_width = max(1, value)
		queue_redraw()

@export var grid_height: int = 10:
	set(value):
		grid_height = max(1, value)
		queue_redraw()

@export var cell_size: float = 12.0:
	set(value):
		cell_size = max(4.0, value)
		custom_minimum_size = Vector2(grid_width * cell_size, grid_height * cell_size)
		queue_redraw()

@export var grid_color := Color(0.35, 0.35, 0.35)
@export var filled_color := Color(0.2, 0.75, 1.0)
@export var hover_color := Color(1.0, 1.0, 1.0, 0.25)

## Whether detail glyphs (W/D/G/S letters) are drawn on wall details. Turned
## off for the dock's small static preview, where they aren't legible.
@export var show_glyphs: bool = true

const COLOR_PORCH := Color(0.35, 0.75, 0.4, 0.55)
const COLOR_SIDEWALK := Color(0.62, 0.62, 0.66, 0.55)
const COLOR_BAY := Color(0.72, 0.42, 0.9, 0.45)
const COLOR_WINDOW := Color(0.18, 0.42, 0.82)
const COLOR_DOOR := Color(1.0, 0.62, 0.18)
const COLOR_GARAGE := Color(0.72, 0.42, 0.9)
const COLOR_STAIRS := Color(0.62, 0.62, 0.62)
const COLOR_DORMER := Color(0.2, 0.75, 0.7)
const COLOR_CHIMNEY := Color(0.75, 0.28, 0.22)
const COLOR_GABLE := Color(0.95, 0.78, 0.2)
const COLOR_ILLEGAL := Color(0.95, 0.2, 0.2)

const EDGE_THICKNESS := 3.0
const EDGE_INSET := 2.0
const HOVER_ALPHA := 0.4
const GLYPH_FONT_SIZE_MIN := 9
const GLYPH_FONT_SIZE_MAX := 26

const DETAIL_COLORS := {
	WallDetail.DetailType.WINDOW: COLOR_WINDOW,
	WallDetail.DetailType.DOOR: COLOR_DOOR,
	WallDetail.DetailType.GARAGE_DOOR: COLOR_GARAGE,
	WallDetail.DetailType.STAIRS: COLOR_STAIRS,
}

const DETAIL_GLYPHS := {
	WallDetail.DetailType.WINDOW: "W",
	WallDetail.DetailType.DOOR: "D",
	WallDetail.DetailType.GARAGE_DOOR: "G",
	WallDetail.DetailType.STAIRS: "S",
}

const DOOR_MODE_GLYPHS := {
	WallDetail.DoorMode.STATIC: "",
	WallDetail.DoorMode.ANIMATED: "*",
	WallDetail.DoorMode.NONE: "\u00b0",
}

const TOOL_DETAIL_TYPES := {
	Tool.WINDOW: WallDetail.DetailType.WINDOW,
	Tool.DOOR: WallDetail.DetailType.DOOR,
	Tool.GARAGE: WallDetail.DetailType.GARAGE_DOOR,
	Tool.STAIRS: WallDetail.DetailType.STAIRS,
}


var _hovered_cell := Vector2i(-1, -1)
var _hovered_edge: Dictionary = {}
var _inspector: DetailInspector

var _drag_active: bool = false
var _drag_is_dormer: bool = false
var _drag_detail_type: int = -1
var _drag_start_edge: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(
		grid_width * cell_size,
		grid_height * cell_size
	)


var context: Node

func _context() -> Node:
	return context if context != null else get_parent()


func _floor_data() -> FloorData:
	return _context().floor_data


func _active_tool() -> int:
	return _context().active_tool


func _house_cell_size() -> float:
	return _context().house_cell_size


func _house_data() -> HouseData:
	return _context().house_data


func _is_lowest_floor() -> bool:
	return _context().is_lowest_floor


func _gui_input(event: InputEvent) -> void:
	var floor_data: FloorData = _floor_data()
	if floor_data == null:
		return

	if event is InputEventMouseMotion:
		_hovered_cell = _mouse_to_cell(event.position)
		_hovered_edge = _mouse_to_edge(event.position)
		queue_redraw()

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_press(event, floor_data)
			else:
				_left_release(event, floor_data)
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_right_click(event.position, floor_data)
			queue_redraw()


func _left_press(event: InputEventMouseButton, floor_data: FloorData) -> void:
	var tool: int = _active_tool()
	match tool:
		Tool.CELLS:
			var cell := _mouse_to_cell(event.position)
			if _is_inside_grid(cell):
				if floor_data.has_cell(cell):
					floor_data.remove_cell(cell)
				else:
					floor_data.add_cell(cell)
					floor_data.remove_porch_cell(cell)
					floor_data.remove_sidewalk_cell(cell)
		Tool.PORCH:
			var cell := _mouse_to_cell(event.position)
			if _is_inside_grid(cell):
				if floor_data.has_porch_cell(cell):
					floor_data.remove_porch_cell(cell)
				elif DetailRules.can_paint_porch_cell(floor_data, cell):
					floor_data.add_porch_cell(cell)
		Tool.SIDEWALK:
			var cell := _mouse_to_cell(event.position)
			if _is_inside_grid(cell):
				if floor_data.has_sidewalk_cell(cell):
					floor_data.remove_sidewalk_cell(cell)
				elif DetailRules.can_paint_sidewalk_cell(floor_data, cell):
					floor_data.add_sidewalk_cell(cell)
		Tool.BAY:
			var cell := _mouse_to_cell(event.position)
			if _is_inside_grid(cell):
				if floor_data.has_garage_cell(cell):
					floor_data.remove_garage_cell(cell)
				elif DetailRules.can_paint_garage_cell(floor_data, cell):
					floor_data.add_garage_cell(cell)
		Tool.WINDOW, Tool.DOOR, Tool.GARAGE, Tool.STAIRS:
			_start_wall_detail_drag(event, floor_data, TOOL_DETAIL_TYPES[tool])
		Tool.DORMER:
			_start_dormer_drag(event, floor_data)
		Tool.CHIMNEY:
			_place_or_edit_chimney(event, floor_data)
		Tool.GABLE:
			_toggle_gable(event, floor_data)
		Tool.ERASE:
			_remove_at(event.position, floor_data, true)


func _left_release(event: InputEventMouseButton, floor_data: FloorData) -> void:
	if not _drag_active:
		return
	var run := _drag_run(_drag_start_edge, _mouse_to_cell(event.position))
	if _drag_is_dormer:
		_finish_dormer_drag(run, floor_data)
	else:
		_finish_wall_detail_drag(run, floor_data)
	_drag_active = false


func _start_wall_detail_drag(event: InputEventMouseButton, floor_data: FloorData, type: int) -> void:
	var edge := _canonical_edge_for_type(_mouse_to_edge(event.position), floor_data, type)
	if edge.is_empty():
		return

	var existing: WallDetail = floor_data.get_wall_detail(edge["cell"], edge["direction"])
	if existing != null:
		_inspector_popup().open_for_wall_detail(existing, _house_cell_size(), _popup_position(event.position), func() -> void:
			floor_data.wall_details.erase(existing)
		, _house_data())
		return

	_drag_active = true
	_drag_is_dormer = false
	_drag_detail_type = type
	_drag_start_edge = edge


func _finish_wall_detail_drag(run: Dictionary, floor_data: FloorData) -> void:
	var detail: WallDetail = WallDetail.create(_drag_detail_type, 0, _house_data())
	detail.cell = run["cell"]
	detail.direction = _drag_start_edge["direction"]
	detail.span = run["span"]
	if detail.span > 1:
		detail.apply_span_defaults(_house_cell_size())
	if DetailRules.wall_detail_valid(detail, floor_data, _is_lowest_floor()):
		floor_data.set_wall_detail(detail)


func _start_dormer_drag(event: InputEventMouseButton, floor_data: FloorData) -> void:
	var edge := _canonical_boundary_edge(floor_data.cells, _mouse_to_edge(event.position))
	if edge.is_empty():
		return

	var existing: DormerData = _find_dormer(floor_data, edge["cell"], edge["direction"])
	if existing != null:
		_inspector_popup().open_for_dormer(existing, _popup_position(event.position), func() -> void:
			floor_data.dormers.erase(existing)
		)
		return

	_drag_active = true
	_drag_is_dormer = true
	_drag_start_edge = edge


func _finish_dormer_drag(run: Dictionary, floor_data: FloorData) -> void:
	var dormer := DormerData.new()
	dormer.cell = run["cell"]
	dormer.direction = _drag_start_edge["direction"]
	dormer.span = run["span"]
	var house_data: HouseData = _house_data()
	if house_data != null:
		dormer.width = house_data.dormer_default_width
		dormer.up_slope_offset = house_data.dormer_default_up_slope_offset
		dormer.face_height = house_data.dormer_default_face_height
		dormer.window_style = house_data.dormer_default_window_style
	if DetailRules.dormer_edge_valid(dormer, floor_data):
		floor_data.dormers.append(dormer)


func _drag_run(start_edge: Dictionary, current_cell: Vector2i) -> Dictionary:
	var start_cell: Vector2i = start_edge["cell"]
	var vary_x: bool = start_edge["direction"] == WallDetail.EdgeDir.NORTH or start_edge["direction"] == WallDetail.EdgeDir.SOUTH
	var axis_size: int = grid_width if vary_x else grid_height
	var start_coord: int = start_cell.x if vary_x else start_cell.y
	var end_coord: int = clampi(current_cell.x if vary_x else current_cell.y, 0, axis_size - 1)
	if end_coord > start_coord:
		end_coord = mini(end_coord, start_coord + DetailConstants.MAX_DETAIL_SPAN - 1)
	else:
		end_coord = maxi(end_coord, start_coord - (DetailConstants.MAX_DETAIL_SPAN - 1))

	var anchor_cell: Vector2i = start_cell
	if vary_x:
		anchor_cell.x = mini(start_coord, end_coord)
	else:
		anchor_cell.y = mini(start_coord, end_coord)
	return {"cell": anchor_cell, "span": absi(end_coord - start_coord) + 1}


func _run_cells(anchor_cell: Vector2i, direction: int, span: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [anchor_cell]
	for i in range(1, span):
		cells.append(anchor_cell + WallDetail.SPAN_STEP[direction] * i)
	return cells


func _toggle_gable(event: InputEventMouseButton, floor_data: FloorData) -> void:
	var edge := _canonical_boundary_edge(_gable_cells(floor_data), _mouse_to_edge(event.position))
	if edge.is_empty():
		return

	var existing: GableData = _find_gable(floor_data, edge["cell"], edge["direction"])
	if existing != null:
		floor_data.gables.erase(existing)
		return

	var gable := GableData.new()
	gable.cell = edge["cell"]
	gable.direction = edge["direction"]
	floor_data.gables.append(gable)


func _gable_cells(floor_data: FloorData) -> Array[Vector2i]:
	var house: HouseData = _house_data()
	if house != null and _is_lowest_floor():
		var upper_floor: FloorData = house.floors[1] if house.floors.size() > 1 else null
		return PorchBuilder.roof_cells(house, floor_data, upper_floor)
	return floor_data.cells


func _place_or_edit_chimney(event: InputEventMouseButton, floor_data: FloorData) -> void:
	var cell := _mouse_to_cell(event.position)
	if not _is_inside_grid(cell):
		return

	var existing: ChimneyData = _find_chimney(floor_data, cell)
	if existing != null:
		_inspector_popup().open_for_chimney(existing, _popup_position(event.position), func() -> void:
			floor_data.chimneys.erase(existing)
		)
		return

	if floor_data.has_cell(cell):
		var chimney := ChimneyData.new()
		chimney.cell = cell
		floor_data.chimneys.append(chimney)


func _right_click(position: Vector2, floor_data: FloorData) -> void:
	var tool: int = _active_tool()
	_remove_at(position, floor_data, tool == Tool.PORCH or tool == Tool.SIDEWALK or tool == Tool.BAY or tool == Tool.ERASE)


func _remove_at(position: Vector2, floor_data: FloorData, remove_paint: bool) -> void:
	var edge := _mouse_to_edge(position)
	if not edge.is_empty():
		for candidate in [edge, _mirror_edge(edge)]:
			if floor_data.get_wall_detail(candidate["cell"], candidate["direction"]) != null:
				floor_data.remove_wall_detail(candidate["cell"], candidate["direction"])
				return
			var dormer: DormerData = _find_dormer(floor_data, candidate["cell"], candidate["direction"])
			if dormer != null:
				floor_data.dormers.erase(dormer)
				return
			var gable: GableData = _find_gable(floor_data, candidate["cell"], candidate["direction"])
			if gable != null:
				floor_data.gables.erase(gable)
				return

	var cell := _mouse_to_cell(position)
	var chimney: ChimneyData = _find_chimney(floor_data, cell)
	if chimney != null:
		floor_data.chimneys.erase(chimney)
		return

	if remove_paint and floor_data.has_porch_cell(cell):
		floor_data.remove_porch_cell(cell)
	elif remove_paint and floor_data.has_sidewalk_cell(cell):
		floor_data.remove_sidewalk_cell(cell)
	elif remove_paint and floor_data.has_garage_cell(cell):
		floor_data.remove_garage_cell(cell)


func _mouse_to_edge(mouse_pos: Vector2) -> Dictionary:
	var cell := _mouse_to_cell(mouse_pos)
	if not _is_inside_grid(cell):
		return {}

	var local: Vector2 = (mouse_pos - _grid_origin() - Vector2(cell) * cell_size) / cell_size
	var direction: int = WallDetail.EdgeDir.NORTH
	var distance: float = local.y
	if 1.0 - local.y < distance:
		direction = WallDetail.EdgeDir.SOUTH
		distance = 1.0 - local.y
	if local.x < distance:
		direction = WallDetail.EdgeDir.WEST
		distance = local.x
	if 1.0 - local.x < distance:
		direction = WallDetail.EdgeDir.EAST
		distance = 1.0 - local.x

	if distance > DetailConstants.EDGE_PICK_FRACTION:
		return {}
	return {"cell": cell, "direction": direction}


func _mirror_edge(edge: Dictionary) -> Dictionary:
	return {
		"cell": edge["cell"] + Vector2i(WallDetail.NORMALS[edge["direction"]]),
		"direction": WallDetail.OPPOSITE[edge["direction"]],
	}


func _canonical_boundary_edge(cells: Array[Vector2i], edge: Dictionary) -> Dictionary:
	if edge.is_empty():
		return {}
	if DetailRules.is_boundary_edge(cells, edge["cell"], edge["direction"]):
		return edge
	var mirror := _mirror_edge(edge)
	if DetailRules.is_boundary_edge(cells, mirror["cell"], mirror["direction"]):
		return mirror
	return {}


func _canonical_edge_for_type(edge: Dictionary, floor_data: FloorData, type: int) -> Dictionary:
	var cells: Array[Vector2i] = floor_data.cells
	if type == WallDetail.DetailType.STAIRS:
		cells = floor_data.porch_cells
	return _canonical_boundary_edge(cells, edge)


func _find_dormer(floor_data: FloorData, cell: Vector2i, direction: int) -> DormerData:
	for dormer in floor_data.dormers:
		if dormer.cell == cell and dormer.direction == direction:
			return dormer
	return null


func _find_gable(floor_data: FloorData, cell: Vector2i, direction: int) -> GableData:
	for gable in floor_data.gables:
		if gable.cell == cell and gable.direction == direction:
			return gable
	return null


func _find_chimney(floor_data: FloorData, cell: Vector2i) -> ChimneyData:
	for chimney in floor_data.chimneys:
		if chimney.cell == cell:
			return chimney
	return null


func _inspector_popup() -> DetailInspector:
	if _inspector == null:
		_inspector = DetailInspector.new()
		_inspector.detail_changed.connect(queue_redraw)
		add_child(_inspector)
	return _inspector


func _popup_position(local_pos: Vector2) -> Vector2i:
	return Vector2i(get_screen_position() + local_pos)


func _draw() -> void:
	var origin := _grid_origin()
	var floor_data: FloorData = _floor_data()

	if floor_data != null:
		for cell in floor_data.sidewalk_cells:
			draw_rect(Rect2(origin + Vector2(cell) * cell_size, Vector2.ONE * cell_size), COLOR_SIDEWALK)
		for cell in floor_data.porch_cells:
			draw_rect(Rect2(origin + Vector2(cell) * cell_size, Vector2.ONE * cell_size), COLOR_PORCH)
		for cell in floor_data.cells:
			draw_rect(Rect2(origin + Vector2(cell) * cell_size, Vector2.ONE * cell_size), filled_color)
		for cell in floor_data.garage_cells:
			var legal: bool = DetailRules.can_paint_garage_cell(floor_data, cell)
			draw_rect(Rect2(origin + Vector2(cell) * cell_size, Vector2.ONE * cell_size), COLOR_BAY if legal else Color(COLOR_ILLEGAL, 0.45))

	for x in range(grid_width + 1):
		var px := origin.x + x * cell_size
		draw_line(
			Vector2(px, origin.y),
			Vector2(px, origin.y + grid_height * cell_size),
			grid_color
		)

	for y in range(grid_height + 1):
		var py := origin.y + y * cell_size
		draw_line(
			Vector2(origin.x, py),
			Vector2(origin.x + grid_width * cell_size, py),
			grid_color
		)

	if floor_data != null:
		_draw_details(floor_data)
		_draw_hover(floor_data)


func _draw_details(floor_data: FloorData) -> void:
	var is_lowest := _is_lowest_floor()

	for detail in floor_data.wall_details:
		var valid: bool = DetailRules.wall_detail_valid(detail, floor_data, is_lowest)
		var color: Color = DETAIL_COLORS[detail.type] if valid else COLOR_ILLEGAL
		var hollow: bool = detail.type == WallDetail.DetailType.STAIRS or not detail.has_leaf() and detail.is_door()
		for spanned in detail.spanned_cells():
			_draw_edge_marker(spanned, detail.direction, color, hollow)
		_draw_edge_glyph(detail, color)

	for dormer in floor_data.dormers:
		var valid: bool = DetailRules.dormer_edge_valid(dormer, floor_data)
		_draw_dormer_marker(dormer.cell, dormer.direction, COLOR_DORMER if valid else COLOR_ILLEGAL)

	var gable_cells: Array[Vector2i] = _gable_cells(floor_data)
	for gable in floor_data.gables:
		var valid: bool = DetailRules.gable_edge_valid(gable, gable_cells)
		_draw_gable_marker(gable.cell, gable.direction, COLOR_GABLE if valid else COLOR_ILLEGAL)

	for chimney in floor_data.chimneys:
		var valid: bool = DetailRules.chimney_cell_valid(chimney, floor_data)
		_draw_chimney_marker(chimney.cell, COLOR_CHIMNEY if valid else COLOR_ILLEGAL)


func _draw_hover(floor_data: FloorData) -> void:
	if _drag_active:
		_draw_drag_preview()
		return

	var tool: int = _active_tool()
	match tool:
		Tool.CELLS:
			if _is_inside_grid(_hovered_cell):
				draw_rect(_cell_rect(_hovered_cell), hover_color)
		Tool.PORCH:
			if _is_inside_grid(_hovered_cell):
				var legal: bool = floor_data.has_porch_cell(_hovered_cell) or DetailRules.can_paint_porch_cell(floor_data, _hovered_cell)
				draw_rect(_cell_rect(_hovered_cell), hover_color if legal else Color(COLOR_ILLEGAL, 0.25))
		Tool.SIDEWALK:
			if _is_inside_grid(_hovered_cell):
				var legal: bool = floor_data.has_sidewalk_cell(_hovered_cell) or DetailRules.can_paint_sidewalk_cell(floor_data, _hovered_cell)
				draw_rect(_cell_rect(_hovered_cell), hover_color if legal else Color(COLOR_ILLEGAL, 0.25))
		Tool.BAY:
			if _is_inside_grid(_hovered_cell):
				var legal: bool = floor_data.has_garage_cell(_hovered_cell) or DetailRules.can_paint_garage_cell(floor_data, _hovered_cell)
				draw_rect(_cell_rect(_hovered_cell), hover_color if legal else Color(COLOR_ILLEGAL, 0.25))
		Tool.WINDOW, Tool.DOOR, Tool.GARAGE, Tool.STAIRS:
			if _hovered_edge.is_empty():
				return
			var type: int = TOOL_DETAIL_TYPES[tool]
			var edge := _canonical_edge_for_type(_hovered_edge, floor_data, type)
			if edge.is_empty():
				_draw_edge_marker(_hovered_edge["cell"], _hovered_edge["direction"], Color(COLOR_ILLEGAL, HOVER_ALPHA), false)
			else:
				_draw_edge_marker(edge["cell"], edge["direction"], Color(DETAIL_COLORS[type], HOVER_ALPHA), type == WallDetail.DetailType.STAIRS)
		Tool.DORMER:
			if _hovered_edge.is_empty():
				return
			var edge := _canonical_boundary_edge(floor_data.cells, _hovered_edge)
			if edge.is_empty():
				_draw_edge_marker(_hovered_edge["cell"], _hovered_edge["direction"], Color(COLOR_ILLEGAL, HOVER_ALPHA), false)
			else:
				_draw_dormer_marker(edge["cell"], edge["direction"], Color(COLOR_DORMER, HOVER_ALPHA))
		Tool.CHIMNEY:
			if _is_inside_grid(_hovered_cell):
				var legal: bool = floor_data.has_cell(_hovered_cell)
				_draw_chimney_marker(_hovered_cell, Color(COLOR_CHIMNEY if legal else COLOR_ILLEGAL, HOVER_ALPHA))
		Tool.GABLE:
			if _hovered_edge.is_empty():
				return
			var edge := _canonical_boundary_edge(_gable_cells(floor_data), _hovered_edge)
			if edge.is_empty():
				_draw_edge_marker(_hovered_edge["cell"], _hovered_edge["direction"], Color(COLOR_ILLEGAL, HOVER_ALPHA), false)
			else:
				_draw_gable_marker(edge["cell"], edge["direction"], Color(COLOR_GABLE, HOVER_ALPHA))
		Tool.ERASE:
			_draw_erase_hover(floor_data)


func _draw_drag_preview() -> void:
	var run := _drag_run(_drag_start_edge, _hovered_cell)
	var direction: int = _drag_start_edge["direction"]
	var cells := _run_cells(run["cell"], direction, run["span"])
	if _drag_is_dormer:
		for spanned in cells:
			_draw_dormer_marker(spanned, direction, Color(COLOR_DORMER, HOVER_ALPHA))
	else:
		var dashed: bool = _drag_detail_type == WallDetail.DetailType.STAIRS
		for spanned in cells:
			_draw_edge_marker(spanned, direction, Color(DETAIL_COLORS[_drag_detail_type], HOVER_ALPHA), dashed)


func _draw_erase_hover(floor_data: FloorData) -> void:
	if not _hovered_edge.is_empty():
		for candidate in [_hovered_edge, _mirror_edge(_hovered_edge)]:
			var detail: WallDetail = floor_data.get_wall_detail(candidate["cell"], candidate["direction"])
			if detail != null:
				for spanned in detail.spanned_cells():
					_draw_edge_marker(spanned, detail.direction, Color(COLOR_ILLEGAL, 0.8), false)
				return
			if _find_dormer(floor_data, candidate["cell"], candidate["direction"]) != null:
				_draw_dormer_marker(candidate["cell"], candidate["direction"], Color(COLOR_ILLEGAL, 0.8))
				return
			if _find_gable(floor_data, candidate["cell"], candidate["direction"]) != null:
				_draw_gable_marker(candidate["cell"], candidate["direction"], Color(COLOR_ILLEGAL, 0.8))
				return
	if not _is_inside_grid(_hovered_cell):
		return
	if _find_chimney(floor_data, _hovered_cell) != null:
		_draw_chimney_marker(_hovered_cell, Color(COLOR_ILLEGAL, 0.8))
	elif floor_data.has_porch_cell(_hovered_cell) or floor_data.has_sidewalk_cell(_hovered_cell) or floor_data.has_garage_cell(_hovered_cell):
		draw_rect(_cell_rect(_hovered_cell), Color(COLOR_ILLEGAL, 0.25))


func _edge_segment(cell: Vector2i, direction: int) -> PackedVector2Array:
	var origin := _grid_origin() + Vector2(cell) * cell_size
	var inset: Vector2 = -WallDetail.NORMALS[direction] * EDGE_INSET
	match direction:
		WallDetail.EdgeDir.NORTH:
			return PackedVector2Array([origin + inset, origin + Vector2(cell_size, 0) + inset])
		WallDetail.EdgeDir.SOUTH:
			return PackedVector2Array([origin + Vector2(0, cell_size) + inset, origin + Vector2(cell_size, cell_size) + inset])
		WallDetail.EdgeDir.WEST:
			return PackedVector2Array([origin + inset, origin + Vector2(0, cell_size) + inset])
		WallDetail.EdgeDir.EAST:
			return PackedVector2Array([origin + Vector2(cell_size, 0) + inset, origin + Vector2(cell_size, cell_size) + inset])
	return PackedVector2Array()


func _draw_edge_marker(cell: Vector2i, direction: int, color: Color, dashed: bool) -> void:
	var segment := _edge_segment(cell, direction)
	if dashed:
		draw_dashed_line(segment[0], segment[1], color, EDGE_THICKNESS, 4.0)
	else:
		draw_line(segment[0], segment[1], color, EDGE_THICKNESS)


func _draw_edge_glyph(detail: WallDetail, color: Color) -> void:
	if not show_glyphs:
		return
	var glyph: String = DETAIL_GLYPHS[detail.type]
	if glyph.is_empty():
		return
	if detail.is_door():
		glyph += DOOR_MODE_GLYPHS[detail.door_mode]
	var font_size: int = _glyph_font_size()
	var segment := _edge_segment(detail.cell, detail.direction)
	var into: Vector2 = -WallDetail.NORMALS[detail.direction]
	var mid: Vector2 = (segment[0] + segment[1]) * 0.5 + into * (cell_size * 0.3)
	draw_string(get_theme_default_font(), mid + Vector2(-font_size * 0.3, font_size * 0.35), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _glyph_font_size() -> int:
	return clampi(roundi(cell_size * 0.45), GLYPH_FONT_SIZE_MIN, GLYPH_FONT_SIZE_MAX)


func _draw_dormer_marker(cell: Vector2i, direction: int, color: Color) -> void:
	var segment := _edge_segment(cell, direction)
	var mid: Vector2 = (segment[0] + segment[1]) * 0.5
	var along: Vector2 = (segment[1] - segment[0]).normalized()
	var into: Vector2 = -WallDetail.NORMALS[direction]
	draw_colored_polygon(PackedVector2Array([
		mid - along * (cell_size * 0.2),
		mid + along * (cell_size * 0.2),
		mid + into * (cell_size * 0.35),
	]), color)


func _draw_gable_marker(cell: Vector2i, direction: int, color: Color) -> void:
	var segment := _edge_segment(cell, direction)
	var mid: Vector2 = (segment[0] + segment[1]) * 0.5
	var along: Vector2 = (segment[1] - segment[0]).normalized()
	var out: Vector2 = WallDetail.NORMALS[direction]
	draw_line(segment[0], segment[1], color, EDGE_THICKNESS)
	draw_colored_polygon(PackedVector2Array([
		mid - along * (cell_size * 0.25),
		mid + along * (cell_size * 0.25),
		mid + out * (cell_size * 0.3),
	]), color)


func _draw_chimney_marker(cell: Vector2i, color: Color) -> void:
	var center: Vector2 = _grid_origin() + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size
	var half: float = cell_size * 0.2
	draw_rect(Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0), color)


func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_grid_origin() + Vector2(cell) * cell_size, Vector2.ONE * cell_size)


func _mouse_to_cell(mouse_pos: Vector2) -> Vector2i:
	var local := mouse_pos - _grid_origin()

	return Vector2i(
		floor(local.x / cell_size),
		floor(local.y / cell_size)
	)


func _is_inside_grid(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < grid_width
		and cell.y < grid_height
	)


func _grid_origin() -> Vector2:
	var size_px := Vector2(
		grid_width * cell_size,
		grid_height * cell_size
	)

	return (size - size_px) * 0.5
