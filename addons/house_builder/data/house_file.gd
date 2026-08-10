@tool
class_name HouseFile
extends RefCounted


const HOUSE_DATA_META := "house_data"

const DATA_SCRIPT_PREFIX := "res://addons/house_builder/"


static func save_house(house: HouseData, path: String) -> Error:
	_clear_data_paths(house, {})

	var building: Node3D = HouseSceneBuilder.build(house)
	building.set_meta(HOUSE_DATA_META, house)

	var packed := PackedScene.new()
	var err: Error = packed.pack(building)
	building.free()
	if err != OK:
		push_error("Failed to pack house scene (error %d)." % err)
		return err

	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("Failed to save house to '%s' (error %d)." % [path, err])
	return err


static func load_any(path: String) -> HouseData:
	match path.get_extension().to_lower():
		"tscn", "scn":
			return _load_from_scene(path)
		_:
			var loaded: Resource = ResourceLoader.load(path, "HouseData", ResourceLoader.CACHE_MODE_IGNORE)
			if not loaded is HouseData:
				push_error("Failed to load house from '%s'." % path)
				return null
			return loaded


static func _load_from_scene(path: String) -> HouseData:
	var packed: Resource = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not packed is PackedScene:
		push_error("Failed to load scene from '%s'." % path)
		return null

	var state: SceneState = packed.get_state()
	if state.get_node_count() > 0:
		for i in range(state.get_node_property_count(0)):
			if state.get_node_property_name(0, i) == "metadata/" + HOUSE_DATA_META:
				var value: Variant = state.get_node_property_value(0, i)
				if value is HouseData:
					return value

	push_error("'%s' is not a house-builder scene (no embedded house data)." % path)
	return null


static func _clear_data_paths(res: Resource, visited: Dictionary) -> void:
	if res == null or visited.has(res.get_instance_id()):
		return
	visited[res.get_instance_id()] = true

	var script: Script = res.get_script() as Script
	if script == null or not script.resource_path.begins_with(DATA_SCRIPT_PREFIX):
		return
	res.resource_path = ""

	for prop in res.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_STORAGE == 0:
			continue
		_clear_variant_paths(res.get(prop["name"]), visited)


static func _clear_variant_paths(value: Variant, visited: Dictionary) -> void:
	if value is Resource:
		_clear_data_paths(value, visited)
	elif value is Array:
		for item in value:
			_clear_variant_paths(item, visited)
	elif value is Dictionary:
		for key in value:
			_clear_variant_paths(key, visited)
			_clear_variant_paths(value[key], visited)
