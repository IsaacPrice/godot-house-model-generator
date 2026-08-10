@tool
extends EditorPlugin

var house_editor

func _enable_plugin() -> void:
	pass


func _disable_plugin() -> void:
	pass


func _enter_tree() -> void:
	house_editor = preload("res://addons/house_builder/ui/house_editor/house_editor.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, house_editor)


func _exit_tree() -> void:
	remove_control_from_docks(house_editor)
	house_editor.free()
