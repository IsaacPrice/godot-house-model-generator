@tool
class_name Footprint
extends RefCounted

static func trace_loops(cells: Array[Vector2i], cell_size: float) -> Array[BoundaryLoop]:
	var occupied: Dictionary = {}
	for cell in cells:
		occupied[cell] = true

	var edges: Array = []
	for cell in cells:
		var x: int = cell.x
		var y: int = cell.y
		if not occupied.has(Vector2i(x, y - 1)):
			edges.append([Vector2i(x, y), Vector2i(x + 1, y), Vector2(0, -1)])
		if not occupied.has(Vector2i(x, y + 1)):
			edges.append([Vector2i(x, y + 1), Vector2i(x + 1, y + 1), Vector2(0, 1)])
		if not occupied.has(Vector2i(x - 1, y)):
			edges.append([Vector2i(x, y), Vector2i(x, y + 1), Vector2(-1, 0)])
		if not occupied.has(Vector2i(x + 1, y)):
			edges.append([Vector2i(x + 1, y), Vector2i(x + 1, y + 1), Vector2(1, 0)])

	var by_point: Dictionary = {}
	for i in range(edges.size()):
		for endpoint in [edges[i][0], edges[i][1]]:
			if not by_point.has(endpoint):
				by_point[endpoint] = []
			by_point[endpoint].append(i)

	var visited: Dictionary = {}
	var loops: Array[BoundaryLoop] = []

	for start_index in range(edges.size()):
		if visited.has(start_index):
			continue

		var raw_points: Array[Vector2i] = [edges[start_index][0]]
		var raw_normals: Array[Vector2] = []
		var current_index: int = start_index
		var current_point: Vector2i = edges[start_index][0]

		while true:
			visited[current_index] = true
			var edge: Array = edges[current_index]
			var next_point: Vector2i = edge[1] if edge[0] == current_point else edge[0]
			raw_normals.append(edge[2])
			raw_points.append(next_point)
			current_point = next_point

			if current_point == raw_points[0]:
				break

			var next_index: int = -1
			for candidate in by_point[current_point]:
				if not visited.has(candidate):
					next_index = candidate
					break
			if next_index == -1:
				break
			current_index = next_index

		raw_points.remove_at(raw_points.size() - 1)
		var loop: BoundaryLoop = _simplify_loop(raw_points, raw_normals, cell_size)
		_normalize_winding(loop)
		loops.append(loop)

	return loops


static func _simplify_loop(raw_points: Array[Vector2i], raw_normals: Array[Vector2], cell_size: float) -> BoundaryLoop:
	var loop := BoundaryLoop.new()
	var n: int = raw_normals.size()

	for i in range(n):
		if raw_normals[i] != raw_normals[(i - 1 + n) % n]:
			loop.points.append(Vector2(raw_points[i].x * cell_size, raw_points[i].y * cell_size))
			loop.normals.append(raw_normals[i])

	return loop


static func _normalize_winding(loop: BoundaryLoop) -> void:
	var n: int = loop.points.size()
	if n < 3:
		return

	var signed_area: float = 0.0
	for i in range(n):
		var a: Vector2 = loop.points[i]
		var b: Vector2 = loop.points[(i + 1) % n]
		signed_area += a.x * b.y - b.x * a.y

	if signed_area >= 0.0:
		return

	var reversed_points := PackedVector2Array()
	var reversed_normals: Array[Vector2] = []
	for k in range(n):
		reversed_points.append(loop.points[n - 1 - k])
		reversed_normals.append(loop.normals[(n - 2 - k + n) % n])

	loop.points = reversed_points
	loop.normals = reversed_normals
