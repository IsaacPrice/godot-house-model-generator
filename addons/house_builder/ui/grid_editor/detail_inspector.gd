@tool
class_name DetailInspector
extends PopupPanel


signal detail_changed

const WINDOW_STYLE_LABELS: PackedStringArray = ["Single", "Wide", "Small"]
const DOOR_STYLE_LABELS: PackedStringArray = ["Plain", "Paneled"]

var _content: VBoxContainer


func _init() -> void:
	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(240, 0)
	add_child(_content)


func open_for_wall_detail(detail: WallDetail, house_cell_size: float, screen_position: Vector2i, on_delete: Callable, house: HouseData = null) -> void:
	_rebuild_wall_detail(detail, house_cell_size, on_delete, house)
	_open_at(screen_position)


func open_for_dormer(dormer: DormerData, screen_position: Vector2i, on_delete: Callable) -> void:
	_clear()
	_add_title("Dormer")
	_add_enum("Window", WINDOW_STYLE_LABELS, dormer.window_style, func(index: int): dormer.window_style = index)
	_add_spin("Span", 1, DetailConstants.MAX_DETAIL_SPAN, 1, dormer.span, func(value: float): dormer.span = int(value), " cells")
	_add_spin("Width", 0.6, 4.0, 0.01, dormer.width, func(value: float): dormer.width = value)
	_add_spin("Up-slope Offset", 0.1, 4.0, 0.01, dormer.up_slope_offset, func(value: float): dormer.up_slope_offset = value)
	_add_spin("Face Height", 0.5, 3.0, 0.01, dormer.face_height, func(value: float): dormer.face_height = value)
	_add_delete_button(on_delete)
	_open_at(screen_position)


func open_for_chimney(chimney: ChimneyData, screen_position: Vector2i, on_delete: Callable) -> void:
	_clear()
	_add_title("Chimney")
	_add_spin("Width", 0.2, 2.0, 0.01, chimney.width, func(value: float): chimney.width = value)
	_add_spin("Depth", 0.2, 2.0, 0.01, chimney.depth, func(value: float): chimney.depth = value)
	_add_spin("Above Roof", 0.2, 3.0, 0.01, chimney.extra_height, func(value: float): chimney.extra_height = value)
	_add_delete_button(on_delete)
	_open_at(screen_position)


const MAX_WIDTH := 50.0
const MAX_HEIGHT := 20.0
const MAX_SILL := 20.0
const MAX_STEP_HEIGHT := 0.4
const MAX_STEP_DEPTH := 1.0


func _rebuild_wall_detail(detail: WallDetail, house_cell_size: float, on_delete: Callable, house: HouseData = null) -> void:
	_clear()
	match detail.type:
		WallDetail.DetailType.WINDOW:
			_add_title("Window")
			_add_enum("Style", WINDOW_STYLE_LABELS, detail.style, func(index: int):
				detail.style = index
				detail.apply_window_style_defaults(house)
				_rebuild_wall_detail(detail, house_cell_size, on_delete, house)
			)
			_add_span_spin(detail, house_cell_size, on_delete)
			_add_spin("Width", 0.3, MAX_WIDTH, 0.01, detail.width, func(value: float): detail.width = value)
			_add_spin("Height", 0.3, MAX_HEIGHT, 0.01, detail.height, func(value: float): detail.height = value)
			_add_spin("Sill Height", 0.0, MAX_SILL, 0.01, detail.sill_height, func(value: float): detail.sill_height = value)
		WallDetail.DetailType.DOOR:
			_add_title("Door")
			_add_enum("Style", DOOR_STYLE_LABELS, detail.style, func(index: int): detail.style = index)
			_add_span_spin(detail, house_cell_size, on_delete)
			_add_spin("Width", 0.3, MAX_WIDTH, 0.01, detail.width, func(value: float): detail.width = value)
			_add_spin("Height", 0.3, MAX_HEIGHT, 0.01, detail.height, func(value: float): detail.height = value)
		WallDetail.DetailType.GARAGE_DOOR:
			_add_title("Garage Door")
			_add_span_spin(detail, house_cell_size, on_delete)
			_add_spin("Width", 0.3, MAX_WIDTH, 0.01, detail.width, func(value: float): detail.width = value)
			_add_spin("Height", 0.3, MAX_HEIGHT, 0.01, detail.height, func(value: float): detail.height = value)
		WallDetail.DetailType.STAIRS:
			_add_title("Stairs")
			_add_span_spin(detail, house_cell_size, on_delete)
			_add_spin("Step Height", 0.05, MAX_STEP_HEIGHT, 0.005, detail.stair_step_height, func(value: float): detail.stair_step_height = value)
			_add_spin("Step Depth", 0.1, MAX_STEP_DEPTH, 0.01, detail.stair_step_depth, func(value: float): detail.stair_step_depth = value)
			_add_checkbox("Include Railing", detail.stair_has_railing, func(value: bool): detail.stair_has_railing = value)
	_add_delete_button(on_delete)


func _add_span_spin(detail: WallDetail, house_cell_size: float, on_delete: Callable) -> void:
	_add_spin("Span", 1, DetailConstants.MAX_DETAIL_SPAN, 1, detail.span, func(value: float):
		detail.span = int(value)
		detail.apply_span_defaults(house_cell_size)
		_rebuild_wall_detail(detail, house_cell_size, on_delete)
	, " cells")


func _clear() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


func _open_at(screen_position: Vector2i) -> void:
	if visible:
		hide()
	popup(Rect2i(screen_position, Vector2i.ZERO))


func _add_title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.theme_type_variation = "HeaderSmall"
	_content.add_child(title)


func _add_spin(label_text: String, min_value: float, max_value: float, step: float, value: float, setter: Callable, suffix: String = "m") -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.suffix = suffix
	spin.value = value
	spin.value_changed.connect(func(new_value: float):
		setter.call(new_value)
		detail_changed.emit()
	)
	row.add_child(spin)
	_content.add_child(row)


func _add_enum(label_text: String, options: PackedStringArray, selected: int, setter: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var button := OptionButton.new()
	for option in options:
		button.add_item(option)
	button.selected = selected
	button.item_selected.connect(func(index: int):
		setter.call(index)
		detail_changed.emit()
	)
	row.add_child(button)
	_content.add_child(row)


func _add_checkbox(label_text: String, value: bool, setter: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var checkbox := CheckBox.new()
	checkbox.button_pressed = value
	checkbox.toggled.connect(func(pressed: bool):
		setter.call(pressed)
		detail_changed.emit()
	)
	row.add_child(checkbox)
	_content.add_child(row)


func _add_delete_button(on_delete: Callable) -> void:
	var button := Button.new()
	button.text = "Delete"
	button.tooltip_text = "Remove this detail (right-clicking it in the grid works too)"
	button.pressed.connect(func():
		hide()
		if on_delete.is_valid():
			on_delete.call()
		detail_changed.emit()
	)
	_content.add_child(button)
