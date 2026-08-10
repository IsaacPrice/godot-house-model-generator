@tool
extends VBoxContainer

const MATERIAL_SLOTS: Array[Dictionary] = [
	{ "property": "siding_material", "label": "Siding Material" },
	{ "property": "trim_material", "label": "Trim Material" },
	{ "property": "foundation_material", "label": "Foundation Material" },
	{ "property": "sidewalk_material", "label": "Sidewalk Material" },
	{ "property": "porch_floor_material", "label": "Porch Floor Material" },
	{ "property": "porch_railing_material", "label": "Porch Railing Material" },
	{ "property": "porch_post_material", "label": "Porch Post Material" },
	{ "property": "porch_baluster_material", "label": "Porch Baluster Material" },
	{ "property": "roofing_shingles_material", "label": "Roofing Shingles Material" },
	{ "property": "roof_underlayment_material", "label": "Roof Underlayment Material" },
	{ "property": "gutter_material", "label": "Gutter Material" },
	{ "property": "window_frame_material", "label": "Window Frame Material" },
	{ "property": "glass_material", "label": "Glass Material" },
	{ "property": "lit_glass_material", "label": "Lit Glass Material" },
	{ "property": "door_material", "label": "Door Material" },
	{ "property": "garage_door_material", "label": "Garage Door Material" },
	{ "property": "chimney_material", "label": "Chimney Material" },
]

const GEOMETRY_SECTIONS: Array[Dictionary] = [
	{
		"title": "Walls & Foundation",
		"slots": [
			{ "property": "wall_thickness", "label": "Wall Thickness", "min": 0.05, "max": 1.0, "step": 0.01 },
			{ "property": "corner_trim_width", "label": "Corner Trim Width", "min": 0.02, "max": 0.5, "step": 0.01 },
			{ "property": "corner_trim_depth", "label": "Corner Trim Depth", "min": 0.01, "max": 0.2, "step": 0.005 },
			{ "property": "base_trim_height", "label": "Base Trim Height", "min": 0.02, "max": 0.6, "step": 0.01 },
			{ "property": "base_trim_depth", "label": "Base Trim Depth", "min": 0.01, "max": 0.2, "step": 0.005 },
			{ "property": "foundation_height", "label": "Foundation Height", "min": 0.1, "max": 2.0, "step": 0.01 },
			{ "property": "foundation_overhang", "label": "Foundation Overhang", "min": 0.0, "max": 0.5, "step": 0.01 },
		],
	},
	{
		"title": "Sidewalk & Grade",
		"slots": [
			{ "property": "sidewalk_drop", "label": "Sidewalk Drop", "min": -2.0, "max": 2.0, "step": 0.01 },
			{ "property": "foundation_mode", "label": "Foundation Mode", "kind": "enum", "options": ["Keep At Floor", "Lower To Grade"] },
			{ "property": "sidewalk_thickness", "label": "Sidewalk Thickness", "min": 0.05, "max": 0.5, "step": 0.01 },
			{ "property": "sidewalk_expand", "label": "Sidewalk Expand", "min": -1.0, "max": 1.0, "step": 0.01 },
		],
	},
	{
		"title": "Roof",
		"slots": [
			{ "property": "roof_pitch_degrees", "label": "Roof Pitch", "min": 0.0, "max": 80.0, "step": 0.5, "suffix": "°" },
			{ "property": "roof_overhang", "label": "Roof Overhang", "min": 0.0, "max": 1.5, "step": 0.01 },
			{ "property": "roof_fascia_height", "label": "Roof Fascia Height", "min": 0.0, "max": 0.6, "step": 0.01 },
			{ "property": "roof_uv_scale", "label": "Roof UV Scale", "min": 0.05, "max": 10.0, "step": 0.05, "suffix": "×" },
		],
	},
	{
		"title": "Gutters",
		"slots": [
			{ "property": "gutter_style", "label": "Gutter Style", "kind": "enum", "options": ["None", "K-Style", "Half-Round"] },
			{ "property": "gutter_width", "label": "Gutter Width", "min": 0.06, "max": 0.3, "step": 0.005 },
			{ "property": "gutter_height", "label": "Gutter Height", "min": 0.04, "max": 0.25, "step": 0.005 },
			{ "property": "gutter_downspouts_enabled", "label": "Downspouts", "kind": "bool" },
			{ "property": "downspout_width", "label": "Downspout Width", "min": 0.04, "max": 0.2, "step": 0.005 },
			{ "property": "downspout_depth", "label": "Downspout Depth", "min": 0.03, "max": 0.2, "step": 0.005 },
			{ "property": "downspout_max_span", "label": "Downspout Max Span", "min": 2.0, "max": 20.0, "step": 0.5 },
		],
	},
	{
		"title": "Porch",
		"slots": [
			{ "property": "porch_has_roof", "label": "Porch Roof", "kind": "bool" },
			{ "property": "porch_floor_thickness", "label": "Porch Floor Thickness", "min": 0.05, "max": 0.4, "step": 0.01 },
			{ "property": "porch_floor_overhang", "label": "Porch Floor Overhang", "min": 0.0, "max": 0.5, "step": 0.01 },
		],
	},
	{
		"title": "Porch Railings",
		"slots": [
			{ "property": "porch_railing_style", "label": "Railing Style", "kind": "enum", "options": ["Picket", "Horizontal", "Cross"] },
			{ "property": "porch_railing_height", "label": "Railing Height", "min": 0.6, "max": 2.0, "step": 0.01 },
			{ "property": "porch_baluster_spacing", "label": "Picket Spacing", "min": 0.05, "max": 0.5, "step": 0.01 },
			{ "property": "porch_baluster_width", "label": "Picket Width", "min": 0.01, "max": 0.15, "step": 0.005 },
			{ "property": "porch_horizontal_rail_count", "label": "Horizontal Rails", "min": 1, "max": 8, "step": 1, "suffix": "" },
			{ "property": "porch_horizontal_rail_height", "label": "Horizontal Rail Height", "min": 0.01, "max": 0.2, "step": 0.005 },
			{ "property": "porch_post_width", "label": "Post Width", "min": 0.06, "max": 0.3, "step": 0.01 },
			{ "property": "porch_post_base_mode", "label": "Post Bases", "kind": "enum", "options": ["None", "Ends + Corners", "All"] },
			{ "property": "porch_post_base_width", "label": "Post Base Width", "min": 0.1, "max": 0.8, "step": 0.01 },
			{ "property": "porch_post_base_height", "label": "Post Base Height", "min": 0.1, "max": 2.0, "step": 0.01 },
			{ "property": "porch_post_base_trim_height", "label": "Post Base Trim Height", "min": 0.01, "max": 0.3, "step": 0.005 },
			{ "property": "porch_post_base_trim_overhang", "label": "Post Base Trim Overhang", "min": 0.0, "max": 0.15, "step": 0.005 },
		],
	},
	{
		"title": "Window Defaults",
		"slots": [
			{ "property": "window_single_default_width", "label": "Single Width", "min": 0.3, "max": 50.0, "step": 0.01 },
			{ "property": "window_single_default_height", "label": "Single Height", "min": 0.3, "max": 20.0, "step": 0.01 },
			{ "property": "window_single_default_sill", "label": "Single Sill Height", "min": 0.0, "max": 20.0, "step": 0.01 },
			{ "property": "window_wide_default_width", "label": "Wide Width", "min": 0.3, "max": 50.0, "step": 0.01 },
			{ "property": "window_wide_default_height", "label": "Wide Height", "min": 0.3, "max": 20.0, "step": 0.01 },
			{ "property": "window_wide_default_sill", "label": "Wide Sill Height", "min": 0.0, "max": 20.0, "step": 0.01 },
			{ "property": "window_small_default_width", "label": "Small Width", "min": 0.3, "max": 50.0, "step": 0.01 },
			{ "property": "window_small_default_height", "label": "Small Height", "min": 0.3, "max": 20.0, "step": 0.01 },
			{ "property": "window_small_default_sill", "label": "Small Sill Height", "min": 0.0, "max": 20.0, "step": 0.01 },
		],
	},
	{
		"title": "Window Glow",
		"slots": [
			{ "property": "window_glow_enabled", "label": "Export Lit Windows", "kind": "bool" },
			{ "property": "window_glow_color", "label": "Glow Color", "kind": "color" },
			{ "property": "window_glow_energy", "label": "Glow Energy", "min": 0.0, "max": 16.0, "step": 0.05, "suffix": "" },
		],
	},
	{
		"title": "Door Defaults",
		"slots": [
			{ "property": "door_default_width", "label": "Door Width", "min": 0.3, "max": 50.0, "step": 0.01 },
			{ "property": "door_default_height", "label": "Door Height", "min": 0.3, "max": 20.0, "step": 0.01 },
			{ "property": "garage_door_default_width", "label": "Garage Door Width", "min": 0.3, "max": 50.0, "step": 0.01 },
			{ "property": "garage_door_default_height", "label": "Garage Door Height", "min": 0.3, "max": 20.0, "step": 0.01 },
		],
	},
	{
		"title": "Stair Defaults",
		"slots": [
			{ "property": "stair_default_step_height", "label": "Step Height", "min": 0.05, "max": 0.4, "step": 0.005 },
			{ "property": "stair_default_step_depth", "label": "Step Depth", "min": 0.1, "max": 1.0, "step": 0.01 },
			{ "property": "stair_default_has_railing", "label": "Include Railing", "kind": "bool" },
		],
	},
	{
		"title": "Dormer Defaults",
		"slots": [
			{ "property": "dormer_default_width", "label": "Width", "min": 0.6, "max": 4.0, "step": 0.01 },
			{ "property": "dormer_default_up_slope_offset", "label": "Up-slope Offset", "min": 0.1, "max": 4.0, "step": 0.01 },
			{ "property": "dormer_default_face_height", "label": "Face Height", "min": 0.5, "max": 3.0, "step": 0.01 },
			{ "property": "dormer_default_window_style", "label": "Window Style", "kind": "enum", "options": ["Single", "Wide", "Small"] },
		],
	},
]

var house_data: HouseData:
	set(value):
		house_data = value
		if is_node_ready():
			_refresh_data()

@onready var grid_container: GridContainer = $GridContainer
@onready var level_size_spinbox: SpinBox = $GridContainer/CellSizeSpin

var _material_pickers: Dictionary = {}
var _geometry_controls: Dictionary = {}


func _ready() -> void:
	_setup_level_size_spinbox()
	_setup_material_pickers()
	_setup_geometry_sections()
	_refresh_data()


func _setup_level_size_spinbox() -> void:
	level_size_spinbox.min_value = 1.0
	level_size_spinbox.max_value = 4.0
	level_size_spinbox.step = 0.01
	level_size_spinbox.suffix = "m"
	if not level_size_spinbox.value_changed.is_connected(_on_level_size_changed):
		level_size_spinbox.value_changed.connect(_on_level_size_changed)


func _add_folded_section(title: String) -> GridContainer:
	var section := FoldableContainer.new()
	section.title = title
	section.folded = true
	add_child(section)

	var section_grid := GridContainer.new()
	section_grid.columns = 2
	section.add_child(section_grid)
	return section_grid


func _setup_material_pickers() -> void:
	var section_grid := _add_folded_section("Materials")
	for slot in MATERIAL_SLOTS:
		var property: String = slot["property"]
		if _material_pickers.has(property):
			continue

		var label := Label.new()
		label.text = slot["label"]
		section_grid.add_child(label)

		var picker := EditorResourcePicker.new()
		picker.base_type = "Material"
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.custom_minimum_size = Vector2(0, 0)
		picker.resource_changed.connect(_on_material_changed.bind(property))
		section_grid.add_child(picker)

		_material_pickers[property] = picker


func _setup_geometry_sections() -> void:
	for section in GEOMETRY_SECTIONS:
		var section_grid := _add_folded_section(section["title"])
		for slot in section["slots"]:
			var property: String = slot["property"]
			if _geometry_controls.has(property):
				continue

			var label := Label.new()
			label.text = slot["label"]
			section_grid.add_child(label)

			var control: Control
			match slot.get("kind", "float"):
				"enum":
					var options := OptionButton.new()
					for option in slot["options"]:
						options.add_item(option)
					options.item_selected.connect(_on_geometry_enum_changed.bind(property))
					control = options
				"bool":
					var checkbox := CheckBox.new()
					checkbox.toggled.connect(_on_geometry_bool_changed.bind(property))
					control = checkbox
				"color":
					var color_button := ColorPickerButton.new()
					color_button.color_changed.connect(_on_geometry_color_changed.bind(property))
					control = color_button
				_:
					var spinbox := SpinBox.new()
					spinbox.min_value = slot["min"]
					spinbox.max_value = slot["max"]
					spinbox.step = slot["step"]
					spinbox.suffix = slot.get("suffix", "m")
					spinbox.value_changed.connect(_on_geometry_value_changed.bind(property))
					control = spinbox
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			section_grid.add_child(control)

			_geometry_controls[property] = control


func _refresh_data() -> void:
	if house_data == null:
		return

	level_size_spinbox.value = house_data.level_cell_size
	for property in _material_pickers:
		_material_pickers[property].edited_resource = house_data.get(property)
	for property in _geometry_controls:
		var control: Control = _geometry_controls[property]
		if control is SpinBox:
			control.value = house_data.get(property)
		elif control is OptionButton:
			control.selected = int(house_data.get(property))
		elif control is CheckBox:
			control.button_pressed = house_data.get(property)
		elif control is ColorPickerButton:
			control.color = house_data.get(property)


func _on_level_size_changed(value: float) -> void:
	if house_data:
		house_data.level_cell_size = value


func _on_material_changed(resource: Resource, property: String) -> void:
	if house_data:
		house_data.set(property, resource)


func _on_geometry_value_changed(value: float, property: String) -> void:
	if house_data:
		house_data.set(property, value)


func _on_geometry_enum_changed(index: int, property: String) -> void:
	if house_data:
		house_data.set(property, index)


func _on_geometry_bool_changed(pressed: bool, property: String) -> void:
	if house_data:
		house_data.set(property, pressed)


func _on_geometry_color_changed(color: Color, property: String) -> void:
	if house_data:
		house_data.set(property, color)
