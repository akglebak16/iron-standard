extends SceneTree
## TERRAIN.md 3.4, 4.1, 4.2, stage Р0б: the terrain grid, map window -> description -> template on made-up cells, the
## same field for the same seed, and the open field of an empty description.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Setup = preload("res://core/battle/data/battle_setup.gd")
const Config = preload("res://core/battle/config.gd")
const TerrainGrid = preload("res://core/battle/model/terrain_grid.gd")
const Description = preload("res://core/battle/data/terrain_description.gd")
const Templates = preload("res://core/battle/data/terrain_templates.gd")
const VegetationSetup = preload("res://core/battle/data/vegetation_setup.gd")
const C := Description.MapCell
const N := Description.WINDOW * Description.WINDOW

var _catalog := Catalog.new()

func _initialize() -> void:
	var loaded := ContentLoader.populate(_catalog)
	assert(loaded)
	_check_grid()
	_check_window_to_template()
	_check_directions()
	_check_same_field_by_seed()
	_check_empty_is_open_field()
	_check_forest_keeps_off_formations()
	print("Terrain template tests passed")
	quit(0)

func _check_grid() -> void:
	var grid = TerrainGrid.create(Vector2(2600, 1700))
	assert(grid.width == 82 and grid.height == 54, "Cells of 32 cover the field, the last one partly")
	assert(grid.is_open())
	grid.cover[grid.index(Vector2(100, 70))] = TerrainGrid.Cover.FOREST
	grid.elevation[grid.index(Vector2(100, 70))] = 200
	assert(grid.cover_at(Vector2(96, 64)) == TerrainGrid.Cover.FOREST and grid.cover_at(Vector2(127.9, 95.9)) == TerrainGrid.Cover.FOREST)
	assert(grid.cover_at(Vector2(128, 64)) == TerrainGrid.Cover.OPEN, "The next cell starts at 128")
	assert(grid.height_at(Vector2(100, 70)) == 200 and not grid.is_open())
	assert(grid.index(Vector2(-50, -50)) == 0 and grid.index(Vector2(99999, 99999)) == grid.width * grid.height - 1, "Off the field reads the edge cell")
	assert(grid.count(TerrainGrid.Cover.FOREST) == 1)

## A made-up window: every cell `fill`, then `cells` overrides {index: code}; heights rise with `slope` along x.
func _window(fill: int, cells := {}, slope := Vector2.ZERO, extra := {}) -> Dictionary:
	var codes := PackedByteArray()
	var heights := PackedFloat32Array()
	var zeros := PackedByteArray()
	var half := Description.WINDOW / 2
	for k in N:
		codes.append(int(cells.get(k, fill)))
		heights.append(0.5 + slope.dot(Vector2(k % Description.WINDOW - half, k / Description.WINDOW - half)))
		zeros.append(0)
	var window := {"cells": codes, "elevation": heights, "road": zeros, "bridge": zeros.duplicate(), "biome": "grass", "settlement": "", "facing": 0.0}
	window.merge(extra, true)
	return window

func _template(window: Dictionary) -> String:
	var description := Description.from_window(window)
	assert(not description.is_empty())
	return Templates.pick(description)

func _check_window_to_template() -> void:
	assert(Templates.pick({}) == Templates.OPEN)
	assert(_template(_window(C.PLAIN)) == Templates.OPEN)
	var description := Description.from_window(_window(C.PLAIN))
	assert(description.plain == 1.0 and description.forest == 0.0 and description.relief == 0.0 and description.high == Vector2.ZERO)
	# Forest: under 25% stays open, 25-60% is an edge, above 60% a forest.
	var some := {}
	for k in 10: some[k] = C.FOREST # 10 of 49
	assert(_template(_window(C.PLAIN, some)) == Templates.OPEN)
	for k in range(10, 20): some[k] = C.FOREST # 20 of 49
	assert(_template(_window(C.PLAIN, some)) == Templates.EDGE)
	assert(_template(_window(C.FOREST)) == Templates.FOREST)
	assert(_template(_window(C.HILLS)) == Templates.HILLS)
	assert(_template(_window(C.PLAIN, {}, Vector2(0.03, 0.0))) == Templates.HILLS, "Relief alone makes hills")
	var peaks := {}
	for k in 7: peaks[k] = C.MOUNTAINS
	assert(_template(_window(C.PLAIN, peaks)) == Templates.MOUNTAINS)
	var river := {}
	for row in Description.WINDOW: river[row * Description.WINDOW + 3] = C.RIVER
	assert(_template(_window(C.FOREST, river)) == Templates.RIVER, "A river crosses whatever is around it")
	var crossed := _window(C.PLAIN, river)
	crossed.bridge[24] = 1
	var described := Description.from_window(crossed)
	assert(described.river and described.bridge and is_equal_approx(described.water, 7.0 / 49.0))
	assert(_template(_window(C.PLAIN, {}, Vector2.ZERO, {"settlement": "village"})) == Templates.VILLAGE)
	var road := _window(C.PLAIN)
	road.road[24] = 1
	assert(_template(road) == Templates.ROAD)
	# Malformed windows describe nothing (the battle then stays the open field).
	assert(Description.from_window({}).is_empty())
	var short := _window(C.PLAIN)
	short.cells.resize(5)
	assert(Description.from_window(short).is_empty())
	assert(Description.from_window(_window(C.PLAIN, {}, Vector2.ZERO, {"settlement": "болото"})).is_empty())

func _check_directions() -> void:
	# The map rises to the east and the enemy comes from the east: the high ground is ahead (+x) in the battle.
	var east := Description.from_window(_window(C.PLAIN, {}, Vector2(0.02, 0.0)))
	assert(east.high.is_equal_approx(Vector2.RIGHT))
	# The enemy comes from the north (map angle -PI/2): east is now the player's right (+y).
	var north := Description.from_window(_window(C.PLAIN, {}, Vector2(0.02, 0.0), {"facing": -PI / 2.0}))
	assert(north.high.is_equal_approx(Vector2.DOWN))
	# Forest in the southern rows, enemy from the east: the forest is on the right flank, an edge puts its strip there.
	var south := {}
	for k in range(35, 49): south[k] = C.FOREST
	var edge := Description.from_window(_window(C.PLAIN, south))
	assert(edge.forest_side.y > 0.9 and Templates.pick(edge) == Templates.EDGE)
	var field := Templates.build(edge, Config.ARENA_SIZE, 4242, "grass")
	var grid = field.grid
	assert(grid.count(TerrainGrid.Cover.FOREST) > 0)
	for k in grid.cover.size():
		if grid.cover[k] == TerrainGrid.Cover.FOREST:
			assert(k / grid.width >= grid.height / 2, "The strip is on the right flank (lower half)")

func _check_same_field_by_seed() -> void:
	for window in [_window(C.FOREST), _window(C.PLAIN, {}, Vector2(0.03, 0.01)), _window(C.PLAIN, {0: C.MOUNTAINS, 1: C.MOUNTAINS, 2: C.MOUNTAINS, 3: C.MOUNTAINS, 4: C.MOUNTAINS})]:
		var description := Description.from_window(window)
		for arena in [Config.ARENA_SIZE, Vector2(4600, 3000)]:
			var a := Templates.build(description, arena, 77, "grass")
			var b := Templates.build(description, arena, 77, "grass")
			var c := Templates.build(description, arena, 78, "grass")
			assert(a.template == b.template and a.grid.cover == b.grid.cover and a.grid.elevation == b.grid.elevation)
			assert(_plants(a.plants) == _plants(b.plants), "The same seed gives the same field")
			assert(_plants(a.plants) != _plants(c.plants) or a.grid.elevation != c.grid.elevation, "Another seed gives another field")
			if a.template in [Templates.HILLS, Templates.MOUNTAINS]:
				assert(a.grid.elevation.count(0) < a.grid.elevation.size(), "Hills raise the ground")
				assert(a.grid.count(TerrainGrid.Cover.OPEN) == a.grid.cover.size())
			if a.template == Templates.FOREST:
				var base := VegetationSetup.create(arena, 77, "grass")
				var trunks: int = a.plants.filter(func(p): return p.trunk_radius > 0.0).size()
				assert(trunks > base.filter(func(p): return p.trunk_radius > 0.0).size() * 3, "A forest has many more trees")

func _plants(plants: Array) -> Array:
	return plants.map(func(p): return [p.position, p.trunk_radius, p.variant])

func _setup(terrain: Dictionary) -> Setup:
	var setup := Setup.new()
	setup.seed = 4242
	setup.hero_troop = "n1"
	setup.hero_position = Config.HERO_START
	setup.player_faction = "nord"
	setup.enemy_faction = "emp"
	setup.player_army.assign([{"type": "n1", "n": 60}, {"type": "n2a", "n": 30}, {"type": "n3c", "n": 20}])
	setup.enemy_army.assign([{"type": "e1", "n": 60}, {"type": "e2a", "n": 30}, {"type": "e3c", "n": 20}])
	setup.terrain = terrain
	return setup

func _check_empty_is_open_field() -> void:
	var empty := Templates.build({}, Config.ARENA_SIZE, 4242, "steppe", 1500.0)
	assert(empty.template == Templates.OPEN and empty.grid.is_open())
	assert(_plants(empty.plants) == _plants(VegetationSetup.create(Config.ARENA_SIZE, 4242, "steppe", 1500.0)), "Empty is the browser field")
	# A plain window keeps the browser field too: the campaign battle in the open looks as before.
	var plain := Templates.build(Description.from_window(_window(C.PLAIN)), Config.ARENA_SIZE, 4242, "grass")
	assert(_plants(plain.plants) == _plants(VegetationSetup.create(Config.ARENA_SIZE, 4242, "grass")))
	# Whole battles: the empty description and an open-field description play the same battle.
	var a := Factory.create(_setup({}), _catalog)
	var b := Factory.create(_setup(Description.from_window(_window(C.PLAIN))), _catalog)
	assert(a != null and b != null and a._state.terrain_template == Templates.OPEN)
	for tick in 600:
		a.step()
		b.step()
	assert(a._rng.state == b._rng.state and a.snapshot() == b.snapshot())

func _check_forest_keeps_off_formations() -> void:
	var session := Factory.create(_setup(Description.from_window(_window(C.FOREST))), _catalog)
	assert(session != null and session._state.terrain_template == Templates.FOREST)
	var state = session._state
	assert(state.terrain.count(TerrainGrid.Cover.FOREST) > 0)
	var base := VegetationSetup.create(state.arena_size, 4242, "")
	for plant in state.plants.slice(base.size()):
		if plant.trunk_radius <= 0.0: continue
		for unit in state.units:
			assert(unit.position.distance_to(plant.position) > Config.TERRAIN_CELL * 0.5, "No new tree stands on a fighter")
	# The forest is a real obstacle field: the battle runs with it.
	for tick in 300:
		session.step()
	assert(session._rng.state != 0)
