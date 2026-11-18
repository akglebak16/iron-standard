extends SceneTree
## TERRAIN.md 3.4, stage Р0б: the C++ terrain reader (core/battle/api/native/terrain_grid.hpp) reads the same cell as
## core/battle/model/terrain_grid.gd for every point, on the base and the largest field, with cover and height set.
const NativeColumns = preload("res://adapters/godot/native/columns.gd")
const Config = preload("res://core/battle/config.gd")
const TerrainGrid = preload("res://core/battle/model/terrain_grid.gd")
const Description = preload("res://core/battle/data/terrain_description.gd")
const Templates = preload("res://core/battle/data/terrain_templates.gd")

func _initialize() -> void:
	var native = NativeColumns.create()
	assert(native != null, "The native column kernel must load")
	for arena in [Config.ARENA_SIZE, Vector2(4600, 3000)]:
		# A forest with hills: every cover and height byte below is something a template really writes.
		var forest := Templates.build({"forest": 0.8, "biome": "grass"}, arena, 11, "grass")
		var hills := Templates.build({"hills": 0.6, "relief": 0.2, "high": Vector2(0.6, 0.8), "biome": "grass"}, arena, 11, "grass")
		var grid = forest.grid
		grid.elevation = hills.grid.elevation
		var tail: int = grid.cover.size() - 1
		grid.cover[tail] = TerrainGrid.Cover.ROCK
		assert(grid.count(TerrainGrid.Cover.FOREST) > 0 and grid.elevation.count(0) < grid.elevation.size())
		var points := PackedVector2Array()
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for i in 4000:
			points.append(Vector2(rng.randf_range(-100.0, arena.x + 100.0), rng.randf_range(-100.0, arena.y + 100.0)))
		for x in [0.0, 31.999, 32.0, 32.001, arena.x - 0.001, arena.x, -0.0001, 1e9, -1e9]:
			for y in [0.0, 31.999, 32.0, arena.y, -1e9, 1e9]:
				points.append(Vector2(x, y))
		var read: PackedInt32Array = native.terrain_cells(grid.cover, grid.elevation, grid.width, Config.TERRAIN_CELL, points)
		assert(read.size() == points.size())
		var differs := 0
		for i in points.size():
			var expected: int = grid.cover_at(points[i]) | grid.height_at(points[i]) << 8
			if read[i] != expected: differs += 1
		assert(differs == 0, "C++ and GDScript read %d cells differently on %s" % [differs, arena])
	assert(native.terrain_cells(PackedByteArray([1, 2, 3]), PackedByteArray([1, 2]), 2, Config.TERRAIN_CELL, PackedVector2Array([Vector2.ZERO])).is_empty(), "A malformed grid reads nothing")
	print("Native terrain grid tests passed")
	quit(0)
