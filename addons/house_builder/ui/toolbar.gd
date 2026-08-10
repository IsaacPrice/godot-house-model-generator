@tool
extends SplitContainer

signal new_pressed
signal open_pressed
signal save_pressed
signal export_pressed

func _on_new_pressed() -> void:
	new_pressed.emit()

func _on_open_pressed() -> void:
	open_pressed.emit()

func _on_save_pressed() -> void:
	save_pressed.emit()

func _on_export_pressed() -> void:
	export_pressed.emit()
