extends SceneTree
const Terrain = preload("res://core/campaign/world/terrain_generator.gd")
const Paths = preload("res://core/campaign/world/pathfinder.gd")

func _initialize() -> void:
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		var terrain := Terrain.new()
		var count := Terrain.GW * Terrain.GH
		terrain.cells.resize(count)
		terrain.bio.resize(count)
		terrain.bridge.resize(count)
		var center := Vector2(210, 210)
		var bridge := terrain.cell_of(center.x, center.y)
		for y in range(6, 15):
			for x in range(6, 15):
				var cell := y * Terrain.GW + x
				var river := x == 10 if axis == Vector2.RIGHT else y == 10
				terrain.cells[cell] = 5 if river and cell != bridge else 1
		terrain.bridge[bridge] = 1
		terrain.bridges.append({"k": bridge, "ax": 0 if axis == Vector2.RIGHT else 1})
		var paths := Paths.new(terrain)
		for direction in [-1, 1]:
			var start: Vector2 = center - axis * 45 * direction + axis.orthogonal() * 8
			var end: Vector2 = center + axis * 45 * direction - axis.orthogonal() * 8
			var route: Array = paths.find_path(start.x, start.y, end.x, end.y)
			var index := route.find(center)
			assert(index > 0 and index < route.size() - 1)
			assert(route[index - 1] == center - axis * 20 * direction)
			assert(route[index + 1] == center + axis * 20 * direction)
			assert(route.back() == end)
		var gate: Vector2 = center + axis * 55
		paths.register_gates([{"kind": "town", "x": gate.x, "y": gate.y}])
		var path: Array = paths.find_path(145, 145, gate.x, gate.y)
		assert(path[-2] == paths.gate_approaches[gate] and path.back() == gate)
	print("Bridge and gate routes passed")
	quit()
