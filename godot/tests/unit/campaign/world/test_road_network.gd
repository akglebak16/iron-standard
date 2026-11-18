extends SceneTree
## Rendering and navigation consume every shared corridor exactly once.
const WorldMap = preload("res://core/campaign/world/world_map.gd")
const Europe = preload("res://core/campaign/data/europe_data.gd")
const Catalog = preload("res://adapters/content/catalog_loader.gd")

func _initialize() -> void:
	var data := Europe.new()
	assert(Catalog.populate(data))
	var map = WorldMap.create(4242, data)
	var graph: Dictionary = map.paths.road_edges
	var drawn := {}
	var entrances := {}
	for site in map.settles:
		entrances[Vector2(site.x, site.y)] = 0
	for run in map.road_network.runs:
		var points: PackedVector2Array = run.points
		if entrances.has(points[0]):
			entrances[points[0]] += 1
		for i in range(1, points.size()):
			var a: int = map.terrain.cell_of(points[i-1].x, points[i-1].y)
			var b: int = map.terrain.cell_of(points[i].x, points[i].y)
			if a == b or not points[i-1].is_equal_approx(map.road_network._center(a)) or not points[i].is_equal_approx(map.road_network._center(b)):
				continue
			var edge := Vector2i(mini(a, b), maxi(a, b))
			assert(not drawn.has(edge), "Shared road was painted twice")
			drawn[edge] = true
	for a: int in graph:
		for b: int in graph[a]:
			assert(graph[b].has(a) and map.paths.road[b])
			assert(drawn.has(Vector2i(mini(a, b), maxi(a, b))), "Invisible road edge")
	for count in entrances.values():
		assert(count <= 1, "Parallel entrances at one gate")
	assert(drawn.size() > 200)
	print("Shared road geometry and entrance tests passed")
	quit(0)
