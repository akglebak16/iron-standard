extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const Config = preload("res://battle/config.gd")
const Factory = preload("res://battle/application/factory.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Plant = preload("res://battle/model/plant.gd")
const Vegetation = preload("res://battle/data/vegetation_setup.gd")
const Movement = preload("res://battle/rules/movement.gd")
const TEST_SEED := 4017
const STEP := 1.0 / 60.0

func _initialize() -> void:
	_check_layout()
	_check_collision()
	print("Vegetation tests passed")
	quit(0)

func _check_layout() -> void:
	var setup := Setup.new()
	setup.seed = TEST_SEED
	setup.hero_troop = "n1"
	var catalog := Catalog.new()
	assert(ContentLoader.populate(catalog))
	var field := Factory.create(setup, catalog)
	var layout := field.vegetation_layout()
	# Recorded from startBattle's placement loop with mulberry(4017).
	assert(layout.size() == 28 and field._state.trunks.size() == 12)
	assert(layout[0].tree and layout[0].variant == 1)
	assert(Vector2(layout[0].position).is_equal_approx(Vector2(575.795156, 1626.659235)))
	assert(not layout[12].tree and layout[12].variant == 1)
	assert(Vector2(layout[12].position).is_equal_approx(Vector2(1490.652066, 583.096681)))
	assert(Factory.create(setup, catalog).vegetation_layout() == layout)
	var rng_state: int = field._rng.state
	layout[0].position = Vector2.INF
	assert(field.vegetation_layout()[0].position.is_finite() and field._rng.state == rng_state)
	setup.biome = "steppe"
	assert(Factory.create(setup, catalog)._state.trunks.size() == 3)
	setup.biome = "arid"
	assert(Factory.create(setup, catalog)._state.trunks.size() == 5)
	setup.biome = "snow"
	setup.siege = true
	var siege := Factory.create(setup, catalog)
	var cutoff := siege._state.wall.x - Vegetation.SIEGE_CLEARANCE
	assert(siege._state.trunks.size() == 8 and siege.vegetation_layout().size() == 18)
	assert(siege.vegetation_layout().all(func(plant): return plant.position.x < cutoff))

func _check_collision() -> void:
	var field := State.new()
	var trunk := Plant.new(Vector2(440, 420), Vegetation.TRUNK_RADIUS, 0)
	var bush := Plant.new(Vector2(500, 420), 0.0, 0)
	field.set_plants([trunk, bush])
	var hero := Unit.new(0, 0, trunk.position + Vector2.LEFT, 100, 0, 1)
	hero.hero = true
	field.add_unit(hero)
	var reach := hero.collision_radius + trunk.trunk_radius
	Movement.step_formation_only(field, STEP)
	assert(hero.position.is_equal_approx(trunk.position + Vector2.LEFT * reach))
	hero.position = trunk.position
	Movement.step_formation_only(field, STEP)
	assert(hero.position.is_equal_approx(trunk.position + Vector2.RIGHT * reach))
	hero.position = bush.position
	Movement.step_formation_only(field, STEP)
	assert(hero.position == bush.position)
	hero.position = trunk.position
	hero.dead = true
	Movement.step_formation_only(field, STEP)
	assert(hero.position == trunk.position)
