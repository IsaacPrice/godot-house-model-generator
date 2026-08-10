extends SceneTree


var failures: int = 0


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var scene: PackedScene = load("res://addons/house_builder/ui/level_editor/level_editor.tscn")
	var editor: LevelEditor = scene.instantiate()

	var floor_data := FloorData.new()
	floor_data.height = 3.0
	for x in range(3):
		floor_data.add_cell(Vector2i(x + 1, 1))
	editor.floor_data = floor_data
	editor.house_cell_size = 2.0
	editor.house_data = HouseData.new()
	editor.expandable = false
	root.add_child(editor)

	var grid: GridEditor = editor.grid_editor
	grid.size = Vector2(grid.grid_width * grid.cell_size, grid.grid_height * grid.cell_size)

	_test_tool_bar(editor)
	_test_cell_and_porch_painting(editor, grid, floor_data)
	_test_sidewalk_painting(editor, grid, floor_data)
	_test_edge_placement(editor, grid, floor_data)
	_test_gable_tool(editor, grid, floor_data)
	_test_drag_span_placement()
	_test_right_click_removal(editor, grid, floor_data)
	_test_erase_tool(editor, grid, floor_data)
	_test_inspector_delete(floor_data)
	_test_floor_window(editor, floor_data)

	if failures == 0:
		print("ALL EDITOR UI TESTS PASSED")
		quit(0)
	else:
		print("%d EDITOR UI TEST FAILURE(S)" % failures)
		quit(1)


func _test_tool_bar(editor: LevelEditor) -> void:
	_check("tool_bar", "one button per tool", editor._tool_buttons.size() == LevelEditor.TOOLS.size())
	_check("tool_bar", "cells tool active by default", editor.active_tool == GridEditor.Tool.CELLS)
	_check("tool_bar", "ground tools enabled on the lowest floor", not editor._tool_buttons[GridEditor.Tool.DOOR].disabled)

	editor.active_tool = GridEditor.Tool.DOOR
	editor.is_lowest_floor = false
	_check("tool_bar", "ground tools disabled on upper floors", editor._tool_buttons[GridEditor.Tool.DOOR].disabled)
	_check("tool_bar", "active ground tool falls back to Cells", editor.active_tool == GridEditor.Tool.CELLS)
	editor.is_lowest_floor = true
	_check("tool_bar", "ground tools re-enabled", not editor._tool_buttons[GridEditor.Tool.DOOR].disabled)


func _test_cell_and_porch_painting(editor: LevelEditor, grid: GridEditor, floor_data: FloorData) -> void:
	editor.active_tool = GridEditor.Tool.PORCH
	_click(grid, _cell_pos(grid, Vector2i(2, 0)))
	_check("porch", "porch cell painted beside the house", floor_data.has_porch_cell(Vector2i(2, 0)))
	_click(grid, _cell_pos(grid, Vector2i(1, 1)))
	_check("porch", "porch cell refused under the house", not floor_data.has_porch_cell(Vector2i(1, 1)))

	editor.active_tool = GridEditor.Tool.CELLS
	_click(grid, _cell_pos(grid, Vector2i(2, 2)))
	_check("cells", "cell painted", floor_data.has_cell(Vector2i(2, 2)))
	editor.active_tool = GridEditor.Tool.PORCH
	_click(grid, _cell_pos(grid, Vector2i(3, 2)))
	editor.active_tool = GridEditor.Tool.CELLS
	_click(grid, _cell_pos(grid, Vector2i(3, 2)))
	_check("cells", "house cell replaces porch cell", floor_data.has_cell(Vector2i(3, 2)) and not floor_data.has_porch_cell(Vector2i(3, 2)))
	_click(grid, _cell_pos(grid, Vector2i(2, 2)))
	_click(grid, _cell_pos(grid, Vector2i(3, 2)))


func _test_sidewalk_painting(editor: LevelEditor, grid: GridEditor, floor_data: FloorData) -> void:
	editor.active_tool = GridEditor.Tool.SIDEWALK
	_click(grid, _cell_pos(grid, Vector2i(0, 0)))
	_check("sidewalk", "sidewalk cell painted beside the house", floor_data.has_sidewalk_cell(Vector2i(0, 0)))
	_click(grid, _cell_pos(grid, Vector2i(1, 1)))
	_check("sidewalk", "sidewalk cell refused under the house", not floor_data.has_sidewalk_cell(Vector2i(1, 1)))
	_click(grid, _cell_pos(grid, Vector2i(2, 0)))
	_check("sidewalk", "sidewalk cell refused on a porch cell", not floor_data.has_sidewalk_cell(Vector2i(2, 0)))

	editor.active_tool = GridEditor.Tool.PORCH
	_click(grid, _cell_pos(grid, Vector2i(0, 0)))
	_check("sidewalk", "porch cell refused on a sidewalk cell", not floor_data.has_porch_cell(Vector2i(0, 0)))

	editor.active_tool = GridEditor.Tool.CELLS
	_click(grid, _cell_pos(grid, Vector2i(0, 0)))
	_check("sidewalk", "house cell replaces sidewalk cell", floor_data.has_cell(Vector2i(0, 0)) and not floor_data.has_sidewalk_cell(Vector2i(0, 0)))
	_click(grid, _cell_pos(grid, Vector2i(0, 0)))

	editor.active_tool = GridEditor.Tool.SIDEWALK
	_click(grid, _cell_pos(grid, Vector2i(0, 2)))
	_click(grid, _cell_pos(grid, Vector2i(0, 2)))
	_check("sidewalk", "sidewalk tool toggles a cell off", not floor_data.has_sidewalk_cell(Vector2i(0, 2)))
	_click(grid, _cell_pos(grid, Vector2i(0, 2)))
	_click(grid, _cell_pos(grid, Vector2i(0, 2)), MOUSE_BUTTON_RIGHT)
	_check("sidewalk", "sidewalk cell removed by right-click", not floor_data.has_sidewalk_cell(Vector2i(0, 2)))
	_click(grid, _cell_pos(grid, Vector2i(0, 2)))
	editor.active_tool = GridEditor.Tool.ERASE
	_click(grid, _cell_pos(grid, Vector2i(0, 2)))
	_check("sidewalk", "erase tool removes a sidewalk cell", not floor_data.has_sidewalk_cell(Vector2i(0, 2)))


func _test_edge_placement(editor: LevelEditor, grid: GridEditor, floor_data: FloorData) -> void:
	editor.active_tool = GridEditor.Tool.WINDOW
	_click(grid, _edge_pos(grid, Vector2i(2, 1), WallDetail.EdgeDir.NORTH))
	var window: WallDetail = floor_data.get_wall_detail(Vector2i(2, 1), WallDetail.EdgeDir.NORTH)
	_check("edges", "window placed on its edge", window != null and window.type == WallDetail.DetailType.WINDOW)

	_click(grid, _edge_pos(grid, Vector2i(2, 2), WallDetail.EdgeDir.NORTH))
	_check("edges", "click from the empty side canonicalizes", floor_data.get_wall_detail(Vector2i(2, 1), WallDetail.EdgeDir.SOUTH) != null)

	editor.active_tool = GridEditor.Tool.GARAGE
	var details_before: int = floor_data.wall_details.size()
	_drag(grid, _edge_pos(grid, Vector2i(1, 1), WallDetail.EdgeDir.NORTH), _cell_pos(grid, Vector2i(2, 1)))
	_check("edges", "overlapping span-2 garage refused", floor_data.wall_details.size() == details_before)

	_click(grid, _edge_pos(grid, Vector2i(1, 1), WallDetail.EdgeDir.NORTH))
	var garage: WallDetail = floor_data.get_wall_detail(Vector2i(1, 1), WallDetail.EdgeDir.NORTH)
	_check("edges", "garage placed", garage != null and garage.type == WallDetail.DetailType.GARAGE_DOOR and garage.span == 1)

	editor.active_tool = GridEditor.Tool.WINDOW
	details_before = floor_data.wall_details.size()
	_click(grid, _edge_pos(grid, Vector2i(1, 1), WallDetail.EdgeDir.EAST))
	_check("edges", "interior edge refused", floor_data.wall_details.size() == details_before)

	editor.active_tool = GridEditor.Tool.STAIRS
	_click(grid, _edge_pos(grid, Vector2i(2, 0), WallDetail.EdgeDir.NORTH))
	var stairs: WallDetail = floor_data.get_wall_detail(Vector2i(2, 0), WallDetail.EdgeDir.NORTH)
	_check("edges", "stairs placed on porch edge", stairs != null and stairs.type == WallDetail.DetailType.STAIRS)

	editor.active_tool = GridEditor.Tool.DORMER
	_click(grid, _edge_pos(grid, Vector2i(3, 1), WallDetail.EdgeDir.EAST))
	_check("edges", "dormer placed on boundary edge", floor_data.dormers.size() == 1 and floor_data.dormers[0].cell == Vector2i(3, 1))

	editor.active_tool = GridEditor.Tool.CHIMNEY
	_click(grid, _cell_pos(grid, Vector2i(1, 1)))
	_check("edges", "chimney placed on occupied cell", floor_data.chimneys.size() == 1)
	_click(grid, _cell_pos(grid, Vector2i(5, 5)))
	_check("edges", "chimney refused on empty cell", floor_data.chimneys.size() == 1)


func _test_gable_tool(editor: LevelEditor, grid: GridEditor, floor_data: FloorData) -> void:
	editor.active_tool = GridEditor.Tool.GABLE
	_click(grid, _edge_pos(grid, Vector2i(1, 1), WallDetail.EdgeDir.WEST))
	_check("gable", "gable placed on boundary edge", floor_data.gables.size() == 1
		and floor_data.gables[0].cell == Vector2i(1, 1)
		and floor_data.gables[0].direction == WallDetail.EdgeDir.WEST)

	_click(grid, _edge_pos(grid, Vector2i(0, 1), WallDetail.EdgeDir.EAST))
	_check("gable", "gable toggled off from the mirror side", floor_data.gables.is_empty())

	_click(grid, _edge_pos(grid, Vector2i(1, 1), WallDetail.EdgeDir.EAST))
	_check("gable", "interior edge refused", floor_data.gables.is_empty())

	_click(grid, _edge_pos(grid, Vector2i(1, 1), WallDetail.EdgeDir.WEST))
	editor.active_tool = GridEditor.Tool.CELLS
	_click(grid, _edge_pos(grid, Vector2i(1, 1), WallDetail.EdgeDir.WEST), MOUSE_BUTTON_RIGHT)
	_check("gable", "gable removed by right-click", floor_data.gables.is_empty())


func _test_drag_span_placement() -> void:
	var floor_data := FloorData.new()
	floor_data.height = 3.0
	for x in range(4):
		floor_data.add_cell(Vector2i(x, 0))

	var scene: PackedScene = load("res://addons/house_builder/ui/level_editor/level_editor.tscn")
	var editor: LevelEditor = scene.instantiate()
	editor.floor_data = floor_data
	editor.house_cell_size = 2.0
	root.add_child(editor)

	var grid: GridEditor = editor.grid_editor
	grid.size = Vector2(grid.grid_width * grid.cell_size, grid.grid_height * grid.cell_size)

	editor.active_tool = GridEditor.Tool.WINDOW
	_drag(grid, _edge_pos(grid, Vector2i(0, 0), WallDetail.EdgeDir.NORTH), _cell_pos(grid, Vector2i(2, 0)))
	var window: WallDetail = floor_data.get_wall_detail(Vector2i(0, 0), WallDetail.EdgeDir.NORTH)
	_check("drag", "window dragged across 3 cells gets span 3", window != null and window.span == 3)
	_check("drag", "span-3 window found through its last edge", floor_data.get_wall_detail(Vector2i(2, 0), WallDetail.EdgeDir.NORTH) == window)

	editor.active_tool = GridEditor.Tool.DOOR
	_drag(grid, _edge_pos(grid, Vector2i(0, 0), WallDetail.EdgeDir.SOUTH), _cell_pos(grid, Vector2i(1, 0)))
	var door: WallDetail = floor_data.get_wall_detail(Vector2i(0, 0), WallDetail.EdgeDir.SOUTH)
	_check("drag", "door dragged across 2 cells gets span 2", door != null and door.span == 2)

	editor.active_tool = GridEditor.Tool.DORMER
	_drag(grid, _edge_pos(grid, Vector2i(2, 0), WallDetail.EdgeDir.SOUTH), _cell_pos(grid, Vector2i(3, 0)))
	var dormer: DormerData = floor_data.dormers[0] if not floor_data.dormers.is_empty() else null
	_check("drag", "dormer dragged across 2 cells gets span 2", dormer != null and dormer.span == 2 and dormer.cell == Vector2i(2, 0))

	editor.queue_free()


func _test_right_click_removal(editor: LevelEditor, grid: GridEditor, floor_data: FloorData) -> void:
	editor.active_tool = GridEditor.Tool.CELLS

	_click(grid, _edge_pos(grid, Vector2i(2, 1), WallDetail.EdgeDir.NORTH), MOUSE_BUTTON_RIGHT)
	_check("removal", "window removed by right-click", floor_data.get_wall_detail(Vector2i(2, 1), WallDetail.EdgeDir.NORTH) == null)

	_click(grid, _edge_pos(grid, Vector2i(2, 2), WallDetail.EdgeDir.NORTH), MOUSE_BUTTON_RIGHT)
	_check("removal", "detail removed from the mirror side", floor_data.get_wall_detail(Vector2i(2, 1), WallDetail.EdgeDir.SOUTH) == null)

	_click(grid, _edge_pos(grid, Vector2i(3, 1), WallDetail.EdgeDir.EAST), MOUSE_BUTTON_RIGHT)
	_check("removal", "dormer removed", floor_data.dormers.is_empty())

	_click(grid, _cell_pos(grid, Vector2i(1, 1)), MOUSE_BUTTON_RIGHT)
	_check("removal", "chimney removed", floor_data.chimneys.is_empty())

	editor.active_tool = GridEditor.Tool.PORCH
	_click(grid, _cell_pos(grid, Vector2i(2, 0)), MOUSE_BUTTON_RIGHT)
	_check("removal", "porch cell removed in porch mode", not floor_data.has_porch_cell(Vector2i(2, 0)))

func _test_erase_tool(editor: LevelEditor, grid: GridEditor, floor_data: FloorData) -> void:
	editor.active_tool = GridEditor.Tool.WINDOW
	_click(grid, _edge_pos(grid, Vector2i(2, 1), WallDetail.EdgeDir.NORTH))
	editor.active_tool = GridEditor.Tool.PORCH
	_click(grid, _cell_pos(grid, Vector2i(2, 0)))

	editor.active_tool = GridEditor.Tool.ERASE
	_click(grid, _edge_pos(grid, Vector2i(2, 1), WallDetail.EdgeDir.NORTH))
	_check("erase", "erase tool removes a wall detail", floor_data.get_wall_detail(Vector2i(2, 1), WallDetail.EdgeDir.NORTH) == null)
	_click(grid, _cell_pos(grid, Vector2i(2, 0)))
	_check("erase", "erase tool removes a porch cell", not floor_data.has_porch_cell(Vector2i(2, 0)))
	_click(grid, _cell_pos(grid, Vector2i(1, 1)))
	_check("erase", "erase tool leaves house cells alone", floor_data.has_cell(Vector2i(1, 1)))


func _test_inspector_delete(floor_data: FloorData) -> void:
	var inspector := DetailInspector.new()
	root.add_child(inspector)

	var window := WallDetail.create(WallDetail.DetailType.WINDOW)
	window.cell = Vector2i(1, 1)
	window.direction = WallDetail.EdgeDir.SOUTH
	floor_data.set_wall_detail(window)
	var deleted: Array[bool] = [false]
	inspector.open_for_wall_detail(window, 2.0, Vector2i.ZERO, func() -> void:
		floor_data.wall_details.erase(window)
		deleted[0] = true
	)
	var delete_button: Button = _find_delete_button(inspector)
	_check("inspector", "wall detail inspector has a Delete button", delete_button != null)
	if delete_button != null:
		delete_button.pressed.emit()
	_check("inspector", "Delete removes the detail", deleted[0] and not floor_data.wall_details.has(window))

	var dormer := DormerData.new()
	inspector.open_for_dormer(dormer, Vector2i.ZERO, func() -> void: pass)
	_check("inspector", "dormer inspector has a Delete button", _find_delete_button(inspector) != null)

	var chimney := ChimneyData.new()
	inspector.open_for_chimney(chimney, Vector2i.ZERO, func() -> void: pass)
	_check("inspector", "chimney inspector has a Delete button", _find_delete_button(inspector) != null)

	inspector.queue_free()


func _find_delete_button(inspector: DetailInspector) -> Button:
	var stack: Array[Node] = [inspector]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Button and node.text == "Delete":
			return node
		stack.append_array(node.get_children())
	return null


func _test_floor_window(editor: LevelEditor, floor_data: FloorData) -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1600, 1200)
	FloorEditorWindow.open(editor)
	var first: FloorEditorWindow = FloorEditorWindow._current
	_check("floor_window", "window opens", first != null)
	if first == null:
		return
	_check("floor_window", "window edits the same floor data", first._editor.floor_data == floor_data)
	_check("floor_window", "pop-out inherits the source's house_data (defaults still apply there)", first._editor.house_data == editor.house_data and editor.house_data != null)
	_check("floor_window", "inner editor hides its own Pop Out", first._editor.expandable == false)
	_check("floor_window", "pop-out grid is enlarged", first._editor.grid_editor.cell_size > editor.grid_editor.cell_size)

	FloorEditorWindow.open(editor)
	var second: FloorEditorWindow = FloorEditorWindow._current
	_check("floor_window", "reopening replaces the previous window", second != first and is_instance_valid(second))
	_check("floor_window", "previous window is gone", first.is_queued_for_deletion() or not is_instance_valid(first))

	var resized := Vector2i(500, 600)
	second.size = resized
	second.close_window()
	_check("floor_window", "closing clears the singleton", FloorEditorWindow._current == null)
	FloorEditorWindow.open(editor)
	var third: FloorEditorWindow = FloorEditorWindow._current
	_check("floor_window", "reopened window keeps the resized size", third.size == resized)
	third.close_window()


func _click(grid: GridEditor, position: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = position
	grid._gui_input(press)

	if button != MOUSE_BUTTON_LEFT:
		return

	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = position
	grid._gui_input(release)


func _drag(grid: GridEditor, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	grid._gui_input(press)

	var motion := InputEventMouseMotion.new()
	motion.position = to
	grid._gui_input(motion)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	grid._gui_input(release)


func _cell_pos(grid: GridEditor, cell: Vector2i) -> Vector2:
	return grid._grid_origin() + (Vector2(cell) + Vector2(0.5, 0.5)) * grid.cell_size


func _edge_pos(grid: GridEditor, cell: Vector2i, direction: int) -> Vector2:
	var base: Vector2 = grid._grid_origin() + Vector2(cell) * grid.cell_size
	var near := 0.08
	var far := 1.0 - near
	match direction:
		WallDetail.EdgeDir.NORTH:
			return base + Vector2(0.5, near) * grid.cell_size
		WallDetail.EdgeDir.SOUTH:
			return base + Vector2(0.5, far) * grid.cell_size
		WallDetail.EdgeDir.WEST:
			return base + Vector2(near, 0.5) * grid.cell_size
		WallDetail.EdgeDir.EAST:
			return base + Vector2(far, 0.5) * grid.cell_size
	return base


func _check(shape: String, what: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("FAIL [%s] %s" % [shape, what])
