extends SceneTree
## TERRAIN.md 4.1, stage Р0б: the campaign map window becomes the battle's terrain description at one point
## (battle_terrain_window.gd), and a campaign battle is built on its template.
const Loader = preload("res://adapters/content/catalog_loader.gd")
const World = preload("res://core/campaign/world/world_state.gd")
const Europe = preload("res://core/campaign/data/europe_data.gd")
const Encounter = preload("res://core/campaign/application/battle_encounter.gd")
const MapWindow = preload("res://core/campaign/application/battle_terrain_window.gd")
const Description = preload("res://core/battle/data/terrain_description.gd")
const Templates = preload("res://core/battle/data/terrain_templates.gd")
const Factory = preload("res://core/battle/application/factory.gd")

func _initialize() -> void:
	var europe := Europe.new()
	var populated := Loader.populate(europe)
	assert(populated)
	var definitions := Loader.registry()
	var world := World.create(413, europe, "emp", definitions)
	var map = world.map
	var at := Vector2(world.player.x, world.player.y)
	# The window reads the map cells around the battle, row by row.
	var window := MapWindow.read(map, at, at + Vector2(100, 0))
	var half := Description.WINDOW / 2
	for row in Description.WINDOW:
		for column in Description.WINDOW:
			var point: Vector2 = at + Vector2(column - half, row - half) * map.terrain.GC
			assert(window.cells[row * Description.WINDOW + column] == map.terrain.cells[map.terrain.cell_of(point.x, point.y)])
	assert(window.facing == 0.0 and window.biome == map.terrain.biome_name(at.x, at.y))
	var described := MapWindow.describe(map, at, at + Vector2(0, -100))
	var total := 0.0
	for key in Description.SHARES: total += float(described[key])
	assert(is_equal_approx(total, 1.0) and is_equal_approx(described.facing, -PI / 2.0))
	# Look over the map for each kind of place; the window must pick its template.
	var found := {}
	var step: float = map.terrain.GC * 5.0
	var y := step
	while y < map.terrain.WH - step:
		var x := step
		while x < map.terrain.WW - step:
			var k: int = map.terrain.cell_of(x, y)
			if map.terrain.walkable(map.terrain.cells[k]):
				var template := Templates.pick(MapWindow.describe(map, Vector2(x, y), Vector2(x + 100, y)))
				if not found.has(template): found[template] = Vector2(x, y)
			x += step
		y += step
	for template in [Templates.OPEN, Templates.FOREST, Templates.EDGE, Templates.HILLS, Templates.RIVER]:
		assert(found.has(template), "The map has a place for the %s template: %s" % [template, found.keys()])
	# A campaign battle carries the description and is built on its template.
	var forest: Vector2 = found[Templates.FOREST]
	world.player.x = forest.x
	world.player.y = forest.y
	var service := Encounter.new(definitions, world.roster.rng)
	var band: Dictionary = world.roster.make_party("bandit", "bandit", "Шайка", forest.x + 30.0, forest.y, [{"type": "b1", "n": 20}])
	var ticket := service.begin(world, band)
	var setup := service.battle_setup(ticket)
	assert(not setup.terrain.is_empty() and Templates.pick(setup.terrain) == Templates.FOREST)
	assert(setup.terrain.biome == setup.biome)
	var battle := Factory.create(setup, definitions.troops, definitions.gear, definitions.perks, definitions.companions)
	assert(battle != null and battle._state.terrain_template == Templates.FOREST)
	service.dispose()
	world.dispose()
	print("Battle terrain window tests passed")
	quit(0)
