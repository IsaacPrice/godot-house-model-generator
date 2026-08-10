@tool
extends VBoxContainer

@onready var floor_list: VBoxContainer = $FloorList
var level_editor: PackedScene = preload("res://addons/house_builder/ui/level_editor/level_editor.tscn")

var floors: Array[FloorData]

var house_data: HouseData

signal add_floor
signal duplicate_floor(floor_data: FloorData)
signal delete_floor(floor_data: FloorData)

func set_floors(data: Array[FloorData]) -> void:
	floors = data
	_refresh_visuals()

func _ready():
	$AddButton.pressed.connect(_on_add_pressed)

func _on_add_pressed() -> void:
	add_floor.emit()

func _refresh_visuals() -> void:
	for child in floor_list.get_children():
		floor_list.remove_child(child)

	var lowest_level: int = floors[0].level if not floors.is_empty() else 0
	for floor in floors:
		lowest_level = min(lowest_level, floor.level)

	for floor in floors:
		var new_level_editor := level_editor.instantiate()
		new_level_editor.floor_data = floor
		new_level_editor.is_lowest_floor = floor.level == lowest_level
		if house_data != null:
			new_level_editor.house_cell_size = house_data.level_cell_size
			new_level_editor.house_data = house_data
		new_level_editor.duplicate_requested.connect(_on_duplicate_requested)
		new_level_editor.delete_requested.connect(_on_delete_requested)
		floor_list.add_child(new_level_editor)


func _on_duplicate_requested(floor_data: FloorData) -> void:
	duplicate_floor.emit(floor_data)


func _on_delete_requested(floor_data: FloorData) -> void:
	delete_floor.emit(floor_data)
