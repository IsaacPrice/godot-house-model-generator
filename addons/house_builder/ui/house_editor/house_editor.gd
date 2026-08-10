@tool
extends VBoxContainer

const OPEN_FILE_FILTERS: PackedStringArray = ["*.tscn ; House Scene", "*.tres, *.res ; Legacy House Resource"]
const SAVE_FILE_FILTERS: PackedStringArray = ["*.tscn ; House Scene"]

enum FileDialogMode { NONE, OPEN, SAVE_AS, EXPORT }

var house: HouseData

@onready var toolbar: SplitContainer = $Toolbar
@onready var current_file_label: Label = $CurrentFile
@onready var house_properties: VBoxContainer = $ScrollContainer/Content/HouseProperties
@onready var floors: VBoxContainer = $ScrollContainer/Content/Floors

var _file_dialog: EditorFileDialog
var _file_dialog_mode: FileDialogMode = FileDialogMode.NONE

var _current_path: String = ""

var _legacy_path: String = ""

func _ready() -> void:
	toolbar.new_pressed.connect(_new)
	toolbar.open_pressed.connect(_open)
	toolbar.save_pressed.connect(_save_as)
	toolbar.export_pressed.connect(_export)

	floors.add_floor.connect(_add_floor)
	floors.duplicate_floor.connect(_duplicate_floor)
	floors.delete_floor.connect(_delete_floor)

	_setup_file_dialog()
	_update_file_label()

func _shortcut_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode != KEY_S or not event.is_command_or_control_pressed():
		return
	if event.shift_pressed or event.alt_pressed:
		return
	if house == null or not is_visible_in_tree():
		return
	if not _hovered() and not _focus_inside():
		return
	accept_event()
	quick_save_house()

func _hovered() -> bool:
	return get_global_rect().has_point(get_global_mouse_position())

func _focus_inside() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	return focus != null and (focus == self or is_ancestor_of(focus))


func _new() -> void:
	print("Creating new house...")
	house = HouseData.new()
	_current_path = ""
	_legacy_path = ""
	house_properties.house_data = house
	floors.house_data = house
	floors.set_floors(house.floors)
	_update_file_label()

func _open() -> void:
	_file_dialog_mode = FileDialogMode.OPEN
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = OPEN_FILE_FILTERS
	_file_dialog.title = "Open House"
	_file_dialog.popup_centered_ratio()

func _save_as() -> void:
	if house == null:
		push_warning("No house to save. Create a new house first.")
		return

	_file_dialog_mode = FileDialogMode.SAVE_AS
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.filters = SAVE_FILE_FILTERS
	_file_dialog.title = "Save House As"
	_file_dialog.current_file = _suggested_file_name()
	_file_dialog.popup_centered_ratio()

func _export() -> void:
	if house == null:
		push_warning("No house to export. Create or open a house first.")
		return

	_file_dialog_mode = FileDialogMode.EXPORT
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.filters = SAVE_FILE_FILTERS
	_file_dialog.title = "Export House Copy"
	_file_dialog.current_file = _suggested_file_name()
	_file_dialog.popup_centered_ratio()

func quick_save_house() -> void:
	if house == null:
		push_warning("No house to save. Create or open a house first.")
		return
	if _current_path == "":
		_save_as()
		return
	_write_house(_current_path)


func _setup_file_dialog() -> void:
	_file_dialog = EditorFileDialog.new()
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.filters = OPEN_FILE_FILTERS
	_file_dialog.file_selected.connect(_on_file_dialog_file_selected)
	add_child(_file_dialog)

func _on_file_dialog_file_selected(path: String) -> void:
	match _file_dialog_mode:
		FileDialogMode.OPEN:
			_load_house(path)
		FileDialogMode.SAVE_AS:
			if _write_house(path) == OK:
				_current_path = path
				_legacy_path = ""
				_update_file_label()
		FileDialogMode.EXPORT:
			_write_house(path)
	_file_dialog_mode = FileDialogMode.NONE

func _load_house(path: String) -> void:
	var loaded: HouseData = HouseFile.load_any(path)
	if loaded == null:
		return

	house = loaded
	if path.get_extension().to_lower() in ["tscn", "scn"]:
		_current_path = path
		_legacy_path = ""
	else:
		_current_path = ""
		_legacy_path = path

	house_properties.house_data = house
	floors.house_data = house
	floors.set_floors(house.floors)
	_update_file_label()

func _write_house(path: String) -> Error:
	var err: Error = HouseFile.save_house(house, path)
	if err == OK:
		print("Saved house to %s" % path)
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(path)
	return err

func _suggested_file_name() -> String:
	if _current_path != "":
		return _current_path.get_file()
	if _legacy_path != "":
		return _legacy_path.get_file().get_basename() + ".tscn"
	return "house.tscn"

func _update_file_label() -> void:
	if current_file_label == null:
		return
	if house == null:
		current_file_label.text = "(no house)"
		current_file_label.tooltip_text = ""
	elif _current_path != "":
		current_file_label.text = _current_path.get_file()
		current_file_label.tooltip_text = "%s\nCtrl+S saves and exports in place." % _current_path
	elif _legacy_path != "":
		current_file_label.text = "%s (legacy)" % _legacy_path.get_file()
		current_file_label.tooltip_text = "Opened from legacy resource %s.\nSave As / Ctrl+S writes a combined .tscn instead." % _legacy_path
	else:
		current_file_label.text = "(unsaved)"
		current_file_label.tooltip_text = "Ctrl+S will ask where to save."


func _add_floor() -> void:
	var new_floor: FloorData = FloorData.new()
	house.add_floor(new_floor)
	floors.set_floors(house.floors)

func _duplicate_floor(floor_data: FloorData) -> void:
	house.add_floor(floor_data.duplicate_data())
	floors.set_floors(house.floors)

func _delete_floor(floor_data: FloorData) -> void:
	house.remove_floor(floor_data)
	floors.set_floors(house.floors)
