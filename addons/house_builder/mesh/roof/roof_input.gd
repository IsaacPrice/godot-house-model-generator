@tool
class_name RoofInput
extends RefCounted


var polygon := PackedVector2Array()

var base_y: float = 0.0

var pitch_degrees: float = 30.0

var overhang: float = 0.4

var fascia_height: float = 0.18

var uv_scale: float = 1.0

var wall_clearance: float = 0.0

var soffit_overlap: float = 0.1

var clip_regions: Array[PackedVector2Array] = []

var clip_keep_margin: float = 0.3

var gable_walls: Array[PackedVector2Array] = []

var gutter_style: RoofGutters.Style = RoofGutters.Style.NONE

var gutter_width: float = 0.13

var gutter_height: float = 0.10

var downspouts_enabled: bool = false

var downspout_width: float = 0.08
var downspout_depth: float = 0.06

var downspout_max_span: float = 10.0

var downspout_grid: float = 0.0

var downspout_walls: Array[PackedVector2Array] = []

var shingles_material: Material

var underlayment_material: Material

var fascia_material: Material

var gable_material: Material

var gutter_material: Material

var slot_shingles: String = "roof"
var slot_underlayment: String = "roof_underlayment"
var slot_fascia: String = "trim"
var slot_gable: String = "siding"
var slot_gutter: String = "gutter"


static func from_house(house: HouseData, wall_face_polygon: PackedVector2Array, wall_top_y: float) -> RoofInput:
	var input := RoofInput.new()
	input.polygon = wall_face_polygon
	input.base_y = wall_top_y
	input.pitch_degrees = house.roof_pitch_degrees
	input.overhang = house.roof_overhang
	input.fascia_height = house.roof_fascia_height
	input.uv_scale = house.roof_uv_scale
	input.gutter_style = house.gutter_style
	input.gutter_width = house.gutter_width
	input.gutter_height = house.gutter_height
	input.downspouts_enabled = house.gutter_downspouts_enabled
	input.downspout_width = house.downspout_width
	input.downspout_depth = house.downspout_depth
	input.downspout_max_span = house.downspout_max_span
	input.downspout_grid = house.level_cell_size
	input.shingles_material = house.roofing_shingles_material
	input.underlayment_material = house.roof_underlayment_material
	input.fascia_material = house.trim_material
	input.gable_material = house.siding_material
	input.gutter_material = house.gutter_material
	return input
