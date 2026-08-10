@tool
class_name BoundaryLoop
extends RefCounted


var points: PackedVector2Array = PackedVector2Array()
var normals: Array[Vector2] = []

func size() -> int:
	return points.size()


func corner_offset(i: int, distance: float) -> Vector2:
	var n: int = points.size()
	var normal_in: Vector2 = normals[(i - 1 + n) % n]
	var normal_out: Vector2 = normals[i]
	return points[i] + (normal_in + normal_out) * distance
