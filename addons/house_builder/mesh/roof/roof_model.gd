@tool
class_name RoofModel
extends RefCounted


enum EdgeType { EAVE, RIDGE, HIP, VALLEY, RAKE }


class RoofPlane extends RefCounted:
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normal := Vector3.UP
	var slot: String = ""
	var material: Material
	var convex: bool = false


class RoofEdge extends RefCounted:
	var type: int = 0
	var a := Vector3.ZERO
	var b := Vector3.ZERO


class Downspout extends RefCounted:
	var head := Vector2.ZERO
	var wall := Vector2.ZERO
	var outward := Vector2.ZERO
	var top_y: float = 0.0
	var soffit_y: float = 0.0


var planes: Array[RoofPlane] = []
var edges: Array[RoofEdge] = []
var downspouts: Array[Downspout] = []

var used_fallback: bool = false
