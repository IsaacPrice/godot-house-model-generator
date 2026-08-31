@tool
class_name HouseDoors
extends Node3D


const ANIMATION_NAME := "open"
const LIBRARY_NAME := ""

const META_STARTS_OPEN := "starts_open"
const META_DOOR_TYPE := "door_type"
const META_OPEN_ROTATION := "open_rotation"


## Drives every door at once from the editor inspector or at runtime. Reads
## back false while any door is shut.
@export var all_doors_open: bool = false:
	set(value):
		all_doors_open = value
		if is_node_ready():
			set_all_open(value)


var _open: Array[bool] = []


func _ready() -> void:
	_open.resize(door_count())
	for i in range(door_count()):
		var pivot: Node3D = _pivot(i)
		_open[i] = pivot != null and bool(pivot.get_meta(META_STARTS_OPEN, false))
		_apply(i, true)


func door_count() -> int:
	return get_child_count()


func door_name(index: int) -> String:
	var pivot: Node3D = _pivot(index)
	return "" if pivot == null else pivot.name


func door_index(name: StringName) -> int:
	for i in range(door_count()):
		if get_child(i).name == name:
			return i
	return -1


func is_open(index: int) -> bool:
	return index >= 0 and index < _open.size() and _open[index]


func open(index: int) -> void:
	set_open(index, true)


func close(index: int) -> void:
	set_open(index, false)


func toggle(index: int) -> void:
	set_open(index, not is_open(index))


func set_open(index: int, opened: bool, instant: bool = false) -> void:
	if index < 0 or index >= door_count():
		return
	if _open.size() != door_count():
		_open.resize(door_count())
	if _open[index] == opened and not instant:
		return
	_open[index] = opened
	_apply(index, instant)


func open_all() -> void:
	set_all_open(true)


func close_all() -> void:
	set_all_open(false)


func set_all_open(opened: bool, instant: bool = false) -> void:
	for i in range(door_count()):
		set_open(i, opened, instant)


func _pivot(index: int) -> Node3D:
	if index < 0 or index >= get_child_count():
		return null
	return get_child(index) as Node3D


func _apply(index: int, instant: bool) -> void:
	var pivot: Node3D = _pivot(index)
	if pivot == null:
		return
	var player: AnimationPlayer = pivot.get_node_or_null(^"AnimationPlayer") as AnimationPlayer
	if player == null or not player.has_animation(ANIMATION_NAME):
		pivot.rotation = pivot.get_meta(META_OPEN_ROTATION, Vector3.ZERO) if _open[index] else Vector3.ZERO
		return

	if instant:
		var opened: Vector3 = pivot.get_meta(META_OPEN_ROTATION, Vector3.ZERO)
		pivot.rotation = opened if _open[index] else Vector3.ZERO
		return

	if _open[index]:
		player.play(ANIMATION_NAME)
	else:
		player.play_backwards(ANIMATION_NAME)
