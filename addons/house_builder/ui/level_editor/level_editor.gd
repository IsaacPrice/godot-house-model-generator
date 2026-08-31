@tool
class_name LevelEditor
extends VBoxContainer


const TOOLS: Array[Dictionary] = [
	{ "tool": GridEditor.Tool.CELLS, "label": "Cells", "tooltip": "Paint floor cells", "ground_only": false },
	{ "tool": GridEditor.Tool.PORCH, "label": "Porch", "tooltip": "Paint porch deck cells (lowest floor only)", "ground_only": true },
	{ "tool": GridEditor.Tool.SIDEWALK, "label": "Walk", "tooltip": "Paint sidewalk/driveway slabs at grade (lowest floor only)", "ground_only": true },
	{ "tool": GridEditor.Tool.BAY, "label": "Bay", "tooltip": "Mark house cells whose floor sits at grade instead of at floor level - garage bays (lowest floor only)", "ground_only": true },
	{ "tool": GridEditor.Tool.WINDOW, "label": "Window", "tooltip": "Drag across wall edges to place a window (click for one cell); click an existing one to edit it", "ground_only": false },
	{ "tool": GridEditor.Tool.DOOR, "label": "Door", "tooltip": "Drag across wall edges to place a door (lowest floor only)", "ground_only": true },
	{ "tool": GridEditor.Tool.GARAGE, "label": "Garage", "tooltip": "Drag across wall edges to place a garage door spanning multiple cells (lowest floor only)", "ground_only": true },
	{ "tool": GridEditor.Tool.STAIRS, "label": "Stairs", "tooltip": "Drag across porch edges to place a stairway descending to grade (lowest floor only)", "ground_only": true },
	{ "tool": GridEditor.Tool.DORMER, "label": "Dormer", "tooltip": "Drag across wall edges to place a dormer on the roof; click an existing one to edit it", "ground_only": false },
	{ "tool": GridEditor.Tool.CHIMNEY, "label": "Chimney", "tooltip": "Place chimneys on a floor cell; click one to edit it", "ground_only": false },
	{ "tool": GridEditor.Tool.GABLE, "label": "Gable", "tooltip": "Click an exterior wall edge to end that whole wall's roof in a gable; click again to remove", "ground_only": false },
	{ "tool": GridEditor.Tool.ERASE, "label": "Erase", "tooltip": "Click any detail, porch, or sidewalk cell to remove it (right-click does the same in any mode)", "ground_only": false },
]

signal duplicate_requested(floor_data: FloorData)

signal delete_requested(floor_data: FloorData)

@onready var margin: MarginContainer = $MarginContainer
@onready var level_spin: SpinBox = %LevelSpinBox
@onready var height_spin: SpinBox = %HeightSpinBox
@onready var grid_editor: GridEditor = %GridEditor


var floor_data: FloorData:
	set(value):
		floor_data = value
		if is_node_ready():
			_refresh_data()

var active_tool: int = GridEditor.Tool.CELLS

var house_cell_size: float = 2.0

var house_data: HouseData

var is_lowest_floor: bool = true:
	set(value):
		is_lowest_floor = value
		if is_node_ready():
			_apply_tool_availability()

var expandable: bool = true

var _tool_buttons: Dictionary = {}
var _tool_group := ButtonGroup.new()


func _ready() -> void:
	grid_editor.context = self
	margin.visible = expandable
	_build_tool_bar()
	_apply_tool_availability()
	_refresh_data()

	level_spin.value_changed.connect(_on_level_changed)
	height_spin.value_changed.connect(_on_height_changed)


func _build_tool_bar() -> void:
	if expandable:
		_build_static_bar()
	else:
		_build_full_tool_bar()


func _build_static_bar() -> void:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	margin.reparent(details)

	var edit := Button.new()
	edit.text = "Edit"
	edit.tooltip_text = "Edit this floor in a larger window (one floor window at a time)"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.pressed.connect(_on_expand_pressed)
	details.add_child(edit)

	var duplicate := Button.new()
	duplicate.text = "Duplicate"
	duplicate.tooltip_text = "Add a copy of this floor (cells, details, dormers, gables, chimneys)"
	duplicate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duplicate.pressed.connect(_on_duplicate_pressed)
	details.add_child(duplicate)

	var delete := Button.new()
	delete.text = "Delete"
	delete.tooltip_text = "Remove this floor"
	delete.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete.pressed.connect(_on_delete_pressed)
	details.add_child(delete)

	body.add_child(details)

	grid_editor.reparent(body)
	grid_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_editor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_editor.show_glyphs = false

	add_child(body)


func _build_full_tool_bar() -> void:
	var bar := HFlowContainer.new()
	for entry in TOOLS:
		var button := Button.new()
		button.text = entry["label"]
		button.tooltip_text = entry["tooltip"]
		button.toggle_mode = true
		button.button_group = _tool_group
		button.pressed.connect(_on_tool_selected.bind(entry["tool"]))
		bar.add_child(button)
		_tool_buttons[entry["tool"]] = button

	_tool_buttons[GridEditor.Tool.CELLS].button_pressed = true
	add_child(bar)
	move_child(bar, grid_editor.get_index())

	var hint := Label.new()
	hint.text = "Left-click: place / edit  ·  Right-click or Erase: remove"
	hint.add_theme_font_size_override("font_size", 10)
	hint.self_modulate = Color(1, 1, 1, 0.55)
	add_child(hint)
	move_child(hint, grid_editor.get_index())


func _on_expand_pressed() -> void:
	FloorEditorWindow.open(self)


func _on_duplicate_pressed() -> void:
	if floor_data != null:
		duplicate_requested.emit(floor_data)


func _on_delete_pressed() -> void:
	if floor_data != null:
		delete_requested.emit(floor_data)


func _apply_tool_availability() -> void:
	if _tool_buttons.is_empty():
		return

	for entry in TOOLS:
		if entry["ground_only"]:
			_tool_buttons[entry["tool"]].disabled = not is_lowest_floor

	if _tool_buttons[active_tool].disabled:
		active_tool = GridEditor.Tool.CELLS
		_tool_buttons[GridEditor.Tool.CELLS].button_pressed = true
		grid_editor.queue_redraw()


func _on_tool_selected(tool: int) -> void:
	active_tool = tool
	grid_editor.queue_redraw()


func _refresh_data() -> void:
	if floor_data == null:
		return

	level_spin.value = floor_data.level
	height_spin.value = floor_data.height


func _on_level_changed(value: float) -> void:
	if floor_data == null:
		return

	floor_data.level = int(value)


func _on_height_changed(value: float) -> void:
	if floor_data == null:
		return

	floor_data.height = value
