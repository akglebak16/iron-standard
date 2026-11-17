extends SceneTree
## Party routes go through the engine's AStarGrid2D (pathfinder.gd): every route must cost as little as the GDScript
## search finds (the same terrain, biome and road costs), unreachable places stay unreachable, and the grid search must
## be clearly faster — a long march of the dead used to cost up to a hundred milliseconds in GDScript.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldMap = preload("res://core/campaign/world/world_map.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Pathfinder = preload("res://core/campaign/world/pathfinder.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var map = WorldMap.create(4242, data)
	var paths: Pathfinder = map.paths
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var gd_us := 0
	var grid_us := 0
	var compared := 0
	for k in 60:
		var a: Dictionary = map.settles[rng.randi_range(0, map.settles.size() - 1)]
		var b: Dictionary = map.settles[rng.randi_range(0, map.settles.size() - 1)]
		var t := Time.get_ticks_usec()
		var reference = paths.find_path(a.x, a.y, b.x, b.y, true)
		gd_us += Time.get_ticks_usec() - t
		t = Time.get_ticks_usec()
		var route = paths.find_path(a.x, a.y, b.x, b.y)
		grid_us += Time.get_ticks_usec() - t
		assert((reference == null) == (route == null), "the grid finds a way exactly when the GDScript search does")
		if reference == null or reference.size() < 2:
			continue
		var cells := paths._grid.get_id_path(paths.nearest_pass(a.x, a.y), paths.nearest_pass(b.x, b.y))
		var ref_cells: Array = [paths.nearest_pass(a.x, a.y)]
		for p in reference:
			ref_cells.append(Vector2i(floori(p.x / Pathfinder.GC), floori(p.y / Pathfinder.GC)))
		var ref_cost := _cost(paths, ref_cells)
		var cost := _cost(paths, Array(cells))
		assert(cost <= ref_cost * 1.002 + 0.01, "grid route %s costs more than the GDScript one %s" % [cost, ref_cost])
		assert(cost >= ref_cost * 0.998 - 0.01, "grid route %s cheaper than the optimum %s: costs differ" % [cost, ref_cost])
		assert(route.back() == Vector2(b.x, b.y) or not paths.passable_type(paths.terr_at(b.x, b.y)), "a route ends at its target")
		compared += 1
	assert(compared >= 40, "enough routes compared")
	assert(grid_us * 5 < gd_us, "the grid search is much faster (%d us vs %d us)" % [grid_us, gd_us])
	# Into the sea: no way. (nearest_pass always lands on passable ground, so ask the grid with a water cell directly.)
	var water := Vector2i(-1, -1)
	for k in Pathfinder.GW * Pathfinder.GH:
		if paths.cell_cost(k) == 0.0:
			water = Vector2i(k % Pathfinder.GW, k / Pathfinder.GW)
			break
	assert(water.x >= 0)
	var from := paths.nearest_pass(map.settles[0].x, map.settles[0].y)
	assert(paths._grid_path(from, water, map.settles[0].x, map.settles[0].y, water.x * 20.0, water.y * 20.0) == null, "no route into the sea")
	# Roads changed: the grid is set up again from the new roads.
	paths.roads_changed()
	assert(paths._grid == null)
	assert(paths.find_path(map.settles[0].x, map.settles[0].y, map.settles[1].x, map.settles[1].y) != null)
	print("compared %d routes: GDScript %.1f ms, grid %.1f ms" % [compared, gd_us / 1000.0, grid_us / 1000.0])
	print("Pathfinder tests passed")
	quit(0)

func _cost(paths: Pathfinder, cells: Array) -> float:
	var c := 0.0
	for i in range(1, cells.size()):
		var a: Vector2i = cells[i - 1]
		var b: Vector2i = cells[i]
		if a == b:
			continue
		c += paths.cell_cost(b.y * Pathfinder.GW + b.x) * (1.414 if a.x != b.x and a.y != b.y else 1.0)
	return c
