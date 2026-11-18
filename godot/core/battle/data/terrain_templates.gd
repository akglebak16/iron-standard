extends RefCounted
## Field templates (TERRAIN.md 4.2, stage Р0б): a terrain description picks a template, the template fills the field
## by `seed`. Stage Р0 fills only trees and bushes, as the browser battle did, plus the terrain grid (cover and height
## bytes); rules that read the grid come in Р1, rivers, roads, fields and rocks with their rules and graphics.
## An empty description, and every template without its own filling yet, gives exactly VegetationSetup's field, so
## the battle stays bit for bit the same. Nothing here touches the battle RNG.
const Config = preload("res://core/battle/config.gd")
const Plant = preload("res://core/battle/model/plant.gd")
const TerrainGrid = preload("res://core/battle/model/terrain_grid.gd")
const VegetationSetup = preload("res://core/battle/data/vegetation_setup.gd")

const OPEN := "open" # plain, steppe: the browser field.
const VILLAGE := "village" # plain by a village: fields and fences come in Р1.
const EDGE := "edge" # forest 25-60% of the window: a forest strip along one flank.
const FOREST := "forest" # forest above 60%: forest on both flanks with glades, the middle stays clear for the armies.
const HILLS := "hills" # one or two hills where the map is higher.
const MOUNTAINS := "mountains" # mountains near: a high ridge along the edge; rocks come in Р2.
const RIVER := "river" # a river across the field: water, fords and a bridge come in Р1-Р2.
const ROAD := "road" # a road across the field: comes in Р1.
const TEMPLATES := [OPEN, VILLAGE, EDGE, FOREST, HILLS, MOUNTAINS, RIVER, ROAD]

const EDGE_FOREST := 0.25 # Window forest share for an edge.
const DEEP_FOREST := 0.6 # Window forest share for a forest.
const NEAR_MOUNTAINS := 0.1 # Window mountain share for mountains.
const HILLY_SHARE := 0.35 # Window hill share for hills...
const HILLY_RELIEF := 0.08 # ...or this much relief.
const FULL_RELIEF := 0.25 # Relief that makes the highest hill (255).
const LOW_HILL := 0.35 # The lowest hill is this share of the highest.
const SECOND_HILL := 0.6 # A second hill is this share of the first.

const STRIP_SHARE := 0.24 # Depth of an edge's forest strip, share of the field height.
const STRIP_GAP := 40.0 # Forest stops this far from the band kept clear for the armies.
const TREE_SPACING := 150.0 # Trees stand on a jittered grid this wide.
const TREE_JITTER := 0.4 # Share of the spacing a tree moves off its grid point.
const TREE_DENSITY := 0.8 # Share of grid points with a tree.
const BUSH_DENSITY := 0.0 # Share of empty grid points with a bush: none, a bush in a row of trees breaks its draw batch.
const GLADES := 2 # Glades in a forest, per strip.
const GLADE_RADIUS := 260.0
const UNIT_CLEARANCE := 1 # Cells around a placed fighter that stay free of trees.
const HILL_RADIUS_SHARE := 0.32 # Hill radius, share of the smaller field side.
const SALT := 0x5bd1e995 # Template samples are their own stream next to VegetationSetup's.

## A description that picks `template`, for the arena and the benchmarks (`--terrain=`); {} for "open" or unknown.
static func sample(template: String) -> Dictionary:
	match template:
		EDGE: return {"forest": 0.4, "plain": 0.6, "forest_side": Vector2.DOWN}
		FOREST: return {"forest": 0.8, "plain": 0.2}
		HILLS: return {"hills": 0.6, "plain": 0.4, "relief": 0.2, "high": Vector2.RIGHT}
		MOUNTAINS: return {"mountains": 0.2, "hills": 0.4, "plain": 0.4, "relief": 0.3, "high": Vector2.UP}
	return {}

## The template for a description (TERRAIN.md 4.2). Order matters: a river crosses whatever is around it.
static func pick(description: Dictionary) -> String:
	if description.is_empty():
		return OPEN
	if bool(description.get("river", false)):
		return RIVER
	var forest := float(description.get("forest", 0.0))
	if forest >= DEEP_FOREST:
		return FOREST
	if forest >= EDGE_FOREST:
		return EDGE
	if float(description.get("mountains", 0.0)) >= NEAR_MOUNTAINS:
		return MOUNTAINS
	if float(description.get("hills", 0.0)) >= HILLY_SHARE or float(description.get("relief", 0.0)) >= HILLY_RELIEF:
		return HILLS
	if description.get("settlement", "") == "village":
		return VILLAGE
	if bool(description.get("road", false)):
		return ROAD
	return OPEN

## The field: {"template": String, "plants": Array[Plant], "grid": TerrainGrid}. `occupied` are the fighters' start
## positions: new trees keep off them. `wall_x` is the siege wall (INF without one).
static func build(description: Dictionary, arena: Vector2, seed_value: int, biome: String, wall_x: float = INF, occupied := PackedVector2Array()) -> Dictionary:
	var template := pick(description)
	var plants := VegetationSetup.create(arena, seed_value, biome, wall_x)
	var grid = TerrainGrid.create(arena)
	var sampler := [(seed_value ^ SALT) & VegetationSetup.UINT32_MASK]
	match template:
		EDGE:
			var below := _strip_side(description, sampler)
			_forest_strip(grid, plants, arena, below, minf(STRIP_SHARE * arena.y, _strip_limit(arena)), 0, sampler, wall_x, occupied)
		FOREST:
			for below in [false, true]:
				_forest_strip(grid, plants, arena, below, _strip_limit(arena), GLADES, sampler, wall_x, occupied)
		HILLS:
			_hills(grid, arena, description, sampler, false)
		MOUNTAINS:
			_hills(grid, arena, description, sampler, true)
	return {"template": template, "plants": plants, "grid": grid}

## Depth a strip may take from the field edge before the band kept clear for the armies.
static func _strip_limit(arena: Vector2) -> float:
	var clear: float = VegetationSetup.FORMATION_CLEARANCE * arena.y / Config.ARENA_SIZE.y
	return maxf(0.0, arena.y * 0.5 - clear - STRIP_GAP)

## An edge's strip lies on the flank where the map forest is; straight ahead or behind, the seed decides.
static func _strip_side(description: Dictionary, sampler: Array) -> bool:
	var side: Vector2 = description.get("forest_side", Vector2.ZERO)
	if absf(side.y) >= 0.3:
		return side.y > 0.0
	return _next(sampler) >= 0.5

static func _forest_strip(grid, plants: Array[Plant], arena: Vector2, below: bool, depth: float, glades: int, sampler: Array, wall_x: float, occupied: PackedVector2Array) -> void:
	if depth <= 0.0:
		return
	var top := arena.y - depth if below else 0.0
	var strip := Rect2(0.0, top, arena.x, depth)
	var glade_centers: Array[Vector2] = []
	for i in glades:
		glade_centers.append(Vector2(lerpf(arena.x * 0.2, arena.x * 0.8, _next(sampler)), top + depth * lerpf(0.3, 0.7, _next(sampler))))
	var blocked := _occupied_cells(grid, occupied)
	for y in grid.height:
		for x in grid.width:
			var center: Vector2 = grid.cell_center(x, y)
			if strip.has_point(center) and center.x < wall_x - VegetationSetup.SIEGE_CLEARANCE and not _in_glade(center, glade_centers):
				grid.cover[y * grid.width + x] = TerrainGrid.Cover.FOREST
	var margin := VegetationSetup.EDGE_MARGIN
	var columns := floori((arena.x - margin.x * 2.0) / TREE_SPACING)
	var rows := floori(maxf(0.0, depth - margin.y) / TREE_SPACING)
	for row in rows + 1:
		for column in columns + 1:
			# Every grid point draws the same three samples, used or not, so one skipped tree does not move the rest.
			var jitter := Vector2(_next(sampler) - 0.5, _next(sampler) - 0.5) * TREE_SPACING * TREE_JITTER * 2.0
			var roll := _next(sampler)
			var point := Vector2(margin.x + column * TREE_SPACING, (arena.y - margin.y - row * TREE_SPACING) if below else (margin.y + row * TREE_SPACING)) + jitter
			if not strip.has_point(point) or point.x >= wall_x - VegetationSetup.SIEGE_CLEARANCE or _in_glade(point, glade_centers):
				continue
			if blocked.has(grid.index(point)):
				continue
			# One look per row: rows never overlap in y, so the y-sorted drawing keeps a row in one batch (one texture).
			if roll < TREE_DENSITY:
				plants.append(Plant.new(point, VegetationSetup.TRUNK_RADIUS, row % VegetationSetup.TREE_VARIANTS))
			elif roll < TREE_DENSITY + BUSH_DENSITY:
				plants.append(Plant.new(point, 0.0, row % VegetationSetup.BUSH_VARIANTS))

## Cells under and around the fighters' start positions, so a new tree never stands inside a formation.
static func _occupied_cells(grid, occupied: PackedVector2Array) -> Dictionary:
	var cells := {}
	for at in occupied:
		var x := clampi(floori(at.x / Config.TERRAIN_CELL), 0, grid.width - 1)
		var y := clampi(floori(at.y / Config.TERRAIN_CELL), 0, grid.height - 1)
		for dy in range(-UNIT_CLEARANCE, UNIT_CLEARANCE + 1):
			for dx in range(-UNIT_CLEARANCE, UNIT_CLEARANCE + 1):
				var cx := x + dx
				var cy := y + dy
				if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height:
					cells[cy * grid.width + cx] = true
	return cells

static func _in_glade(point: Vector2, glades: Array[Vector2]) -> bool:
	for center in glades:
		if point.distance_to(center) < GLADE_RADIUS:
			return true
	return false

## Height bytes: hills where the map is higher (TERRAIN.md 4.2 "армии стоят по высоте карты"); a ridge along the far
## edge for mountains. Only the grid changes; the field is drawn and fought as before until Р1.
static func _hills(grid, arena: Vector2, description: Dictionary, sampler: Array, ridge: bool) -> void:
	var high: Vector2 = description.get("high", Vector2.ZERO)
	if high == Vector2.ZERO:
		high = Vector2.RIGHT.rotated(_next(sampler) * TAU)
	var peak := clampf(float(description.get("relief", 0.0)) / FULL_RELIEF, LOW_HILL, 1.0) * 255.0
	var radius := minf(arena.x, arena.y) * HILL_RADIUS_SHARE
	var centers: Array[Vector2] = []
	var tops: Array[float] = []
	if ridge:
		# The ridge stands beyond the field edge the map rises to: only its slopes reach the field.
		for i in 3:
			centers.append(arena * 0.5 + Vector2(high.x * arena.x, high.y * arena.y) * 0.6 + high.orthogonal() * (i - 1) * radius)
			tops.append(peak)
	else:
		centers.append(arena * 0.5 + Vector2(high.x * arena.x, high.y * arena.y) * 0.3)
		tops.append(peak)
		if _next(sampler) < 0.5:
			# A lower second hill on the other flank.
			var flank := -signf(high.y) if high.y != 0.0 else 1.0
			centers.append(arena * 0.5 + Vector2(high.x * arena.x * 0.1, flank * arena.y * 0.3))
			tops.append(peak * SECOND_HILL)
	for y in grid.height:
		for x in grid.width:
			var center: Vector2 = grid.cell_center(x, y)
			var level := 0.0
			for i in centers.size():
				var d := center.distance_to(centers[i]) / radius
				level = maxf(level, tops[i] * exp(-d * d * 2.0))
			grid.elevation[y * grid.width + x] = clampi(roundi(level), 0, 255)

## The next template sample in [0, 1): the browser's Mulberry, in its own stream.
static func _next(sampler: Array) -> float:
	sampler[0] = (int(sampler[0]) + VegetationSetup.MULBERRY_STEP) & VegetationSetup.UINT32_MASK
	return VegetationSetup._mulberry_value(sampler[0])
