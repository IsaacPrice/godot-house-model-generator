@tool
class_name FloorEditorWindow
extends Window


const LEVEL_EDITOR_SCENE := preload("res://addons/house_builder/ui/level_editor/level_editor.tscn")
const DEFAULT_SIZE := Vector2i(620, 780)

const FIT_MARGIN := Vector2(56.0, 220.0)

static var _current: FloorEditorWindow
static var _last_size := Vector2i.ZERO

var _editor: LevelEditor
var _source: LevelEditor


static func open(source: LevelEditor) -> void:
	if is_instance_valid(_current):
		_current.close_window()

	var window := FloorEditorWindow.new()
	_current = window
	window._source = source
	source.add_child(window)
	window._setup()
	window.popup_centered(_stored_size())
	window._apply_stored_size()
	window._fit_grid()


func close_window() -> void:
	_remember_size()
	if is_instance_valid(_source) and _source.grid_editor != null:
		_source.grid_editor.queue_redraw()
	if _current == self:
		_current = null
	queue_free()


static func _stored_size() -> Vector2i:
	if _last_size.x > 0:
		return _last_size
	if Engine.is_editor_hint():
		var stored: Variant = EditorInterface.get_editor_settings().get_project_metadata("house_builder", "floor_window_size", Vector2i.ZERO)
		if stored is Vector2i and stored.x > 0:
			return stored
	return DEFAULT_SIZE


func _remember_size() -> void:
	_last_size = size
	if Engine.is_editor_hint():
		EditorInterface.get_editor_settings().set_project_metadata("house_builder", "floor_window_size", size)


func _apply_stored_size() -> void:
	var target: Vector2i = _stored_size()
	if is_embedded():
		var parent_size := Vector2(get_parent().get_viewport().get_visible_rect().size)
		var limit := Vector2i(parent_size) - Vector2i(32, 32)
		if limit.x > min_size.x and limit.y > min_size.y:
			target = Vector2i(mini(target.x, limit.x), mini(target.y, limit.y))
		size = target
		position = Vector2i(((parent_size - Vector2(size)) * 0.5).max(Vector2.ZERO))
	else:
		size = target


func _setup() -> void:
	title = "Floor %d" % _source.floor_data.level if _source.floor_data != null else "Floor"
	min_size = Vector2i(420, 520)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)

	_editor = LEVEL_EDITOR_SCENE.instantiate()
	_editor.expandable = false
	_editor.floor_data = _source.floor_data
	_editor.house_cell_size = _source.house_cell_size
	_editor.house_data = _source.house_data
	_editor.is_lowest_floor = _source.is_lowest_floor
	margin.add_child(_editor)
	add_child(margin)

	close_requested.connect(close_window)
	size_changed.connect(_fit_grid)
	window_input.connect(_on_window_input)


func _on_window_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode != KEY_S or not event.is_command_or_control_pressed():
		return
	if event.shift_pressed or event.alt_pressed:
		return
	var dock: Node = _find_house_editor()
	if dock == null:
		return
	set_input_as_handled()
	dock.quick_save_house()


func _find_house_editor() -> Node:
	if not is_instance_valid(_source):
		return null
	var node: Node = _source
	while node != null and not node.has_method("quick_save_house"):
		node = node.get_parent()
	return node


func _fit_grid() -> void:
	if _editor == null or _editor.grid_editor == null:
		return
	var grid: GridEditor = _editor.grid_editor
	var available: Vector2 = Vector2(size) - FIT_MARGIN
	var cell: float = floorf(minf(available.x / grid.grid_width, available.y / grid.grid_height))
	grid.cell_size = clampf(cell, 14.0, 72.0)
