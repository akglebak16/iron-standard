extends SceneTree
## TERRAIN.md 5, stage Р0а: the field grows with the larger army, placement is a share of the field, and a battle
## up to ARENA_TIERS[0] fighters a side keeps the base field with the exact browser placement.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Setup = preload("res://core/battle/data/battle_setup.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const State = preload("res://core/battle/model/state.gd")
const ArmyBuilder = preload("res://core/battle/data/army_builder.gd")
const VegetationSetup = preload("res://core/battle/data/vegetation_setup.gd")
const ArenaLayout = preload("res://core/battle/rules/arena_layout.gd")
const Config = preload("res://core/battle/config.gd")

const MEDIUM := Vector2(3600, 2400)
const LARGE := Vector2(4600, 3000)

var _catalog := Catalog.new()

func _initialize() -> void:
	var loaded := ContentLoader.populate(_catalog)
	assert(loaded)
	_check_tiers()
	_check_base_placement_is_exact()
	_check_large_placement()
	_check_field_count_matches_spawn()
	_check_battles()
	_check_vegetation_band()
	print("Arena layout tests passed")
	quit(0)

func _check_tiers() -> void:
	assert(ArenaLayout.size_for(0) == Config.ARENA_SIZE)
	assert(ArenaLayout.size_for(200) == Config.ARENA_SIZE, "Up to 200 a side the field stays as before")
	assert(ArenaLayout.size_for(201) == MEDIUM)
	assert(ArenaLayout.size_for(500) == MEDIUM)
	assert(ArenaLayout.size_for(501) == LARGE)
	assert(ArenaLayout.size_for(1000) == LARGE)
	assert(ArenaLayout.size_for(5000) == LARGE, "Above the last row the largest field is used")
	var previous := Vector2.ZERO
	for tier in Config.ARENA_TIERS:
		var size: Vector2 = tier[1]
		assert(size.x > previous.x and size.y > previous.y, "Rows grow")
		assert(float(tier[2]) > 0.0 and float(tier[2]) < 0.5, "The front stands on its own half")
		previous = size
	assert(Config.ARENA_TIERS[0][1] == Config.ARENA_SIZE)

func _check_base_placement_is_exact() -> void:
	var base := Config.ARENA_SIZE
	assert(ArenaLayout.front_x(base) == Config.FRONT_X)
	assert(ArenaLayout.center_y(base) == Config.CENTER_Y)
	assert(ArenaLayout.scale(base) == Vector2.ONE)
	assert(ArenaLayout.from_base(Config.HERO_START, base) == Config.HERO_START)
	var odd := Vector2(731.37, 849.91)
	assert(ArenaLayout.from_base(odd, base) == odd, "The base field never touches the given point")
	# The groups stand exactly where the browser numbers put them.
	var state := State.new()
	state.setup_groups()
	assert(state.groups[0][Config.GROUP_INFANTRY].center == Vector2(Config.FRONT_X, Config.CENTER_Y))
	assert(state.groups[0][Config.GROUP_ARCHERS].center == Vector2(Config.FRONT_X - Config.ARCHER_REAR_OFFSET, Config.CENTER_Y))
	assert(state.groups[0][Config.GROUP_CAVALRY].center == Vector2(Config.FRONT_X - Config.CAVALRY_REAR_OFFSET, Config.CENTER_Y + Config.CAVALRY_FLANK_OFFSET))
	assert(state.groups[1][Config.GROUP_INFANTRY].center == Vector2(base.x - Config.FRONT_X, Config.CENTER_Y))
	assert(state.groups[1][Config.GROUP_ARCHERS].center == Vector2(base.x - Config.FRONT_X + Config.ARCHER_REAR_OFFSET, Config.CENTER_Y))

func _check_large_placement() -> void:
	for arena in [MEDIUM, LARGE]:
		var state := State.new()
		state.arena_size = arena
		state.setup_groups()
		var front := ArenaLayout.front_x(arena)
		var proportional: float = Config.FRONT_X * arena.x / Config.ARENA_SIZE.x
		assert(front > proportional, "On a larger field the armies stand nearer the middle than a plain stretch")
		var gap: float = arena.x - 2.0 * front
		assert(gap < arena.x - 2.0 * proportional)
		assert(gap > Config.ARENA_SIZE.x - 2.0 * Config.FRONT_X, "The approach grows, but less than the field")
		var infantry: Vector2 = state.groups[0][Config.GROUP_INFANTRY].center
		assert(infantry == Vector2(front, arena.y * 0.5))
		assert(state.groups[1][Config.GROUP_INFANTRY].center == Vector2(arena.x - front, arena.y * 0.5))
		var cavalry: Vector2 = state.groups[0][Config.GROUP_CAVALRY].center
		assert(is_equal_approx(cavalry.y - infantry.y, Config.CAVALRY_FLANK_OFFSET * arena.y / Config.ARENA_SIZE.y), "Offsets grow with the field")
		var archers: Vector2 = state.groups[0][Config.GROUP_ARCHERS].center
		assert(is_equal_approx(infantry.x - archers.x, Config.ARCHER_REAR_OFFSET * arena.x / Config.ARENA_SIZE.x))
		var hero := ArenaLayout.from_base(Config.HERO_START, arena)
		assert(hero.y == arena.y * 0.5 and hero.x > front and hero.x < arena.x * 0.5, "The hero keeps his place in front of his army")

func _check_field_count_matches_spawn() -> void:
	var cases := [
		[[{"type": "n1", "n": 120}, {"type": "n2a", "n": 60}], 300, false],
		[[{"type": "n1", "n": 400}, {"type": "n2a", "n": 333}, {"type": "n3c", "n": 7}], 300, false],
		[[{"type": "n1", "n": 1}, {"type": "n2a", "n": 1}, {"type": "n3c", "n": 998}], 300, false],
		[[{"type": "z1", "n": 30}, {"type": "s1", "n": 20}], 12, true],
		[[{"type": "n1", "n": 900}, {"type": "n3c", "n": 100}], 1000, false],
	]
	for item in cases:
		var state := State.new()
		state.setup_groups()
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var ok := ArmyBuilder.spawn(state, 0, item[0], "nord", _catalog, rng, item[1], "", 0.0, item[2])
		assert(ok)
		var counted := ArmyBuilder.field_count(item[0], item[1], item[2])
		assert(counted == state.units.size(), "field_count %d against %d spawned" % [counted, state.units.size()])
	assert(ArmyBuilder.field_count([{"type": "n1", "n": 0}], 300, false) == 0, "Invalid stacks count as nothing")

func _setup(per_side: int, cap: int = 0) -> Setup:
	var setup := Setup.new()
	setup.seed = 4242
	setup.hero_troop = "n1"
	setup.hero_position = Config.HERO_START
	setup.player_faction = "nord"
	setup.enemy_faction = "emp"
	setup.player_unit_cap = cap
	setup.enemy_unit_cap = cap
	var infantry := per_side / 2
	setup.player_army.assign([{"type": "n1", "n": infantry}, {"type": "n2a", "n": per_side - infantry}])
	setup.enemy_army.assign([{"type": "e1", "n": infantry}, {"type": "e2a", "n": per_side - infantry}])
	return setup

func _check_battles() -> void:
	var small := Factory.create(_setup(200, 1000), _catalog)
	assert(small != null and small._state.arena_size == Config.ARENA_SIZE)
	assert(small._hero.position == Config.HERO_START, "A battle up to 200 a side keeps the hero where he was")
	# The campaign cap (300 a side) puts a big army on the medium field.
	var campaign := Factory.create(_setup(700), _catalog)
	assert(campaign != null and campaign._state.arena_size == MEDIUM)
	var large := Factory.create(_setup(1000, 1000), _catalog)
	assert(large != null and large._state.arena_size == LARGE)
	for session in [campaign, large]:
		var arena: Vector2 = session._state.arena_size
		assert(Rect2(Vector2.ZERO, arena).has_point(session._hero.position))
		for unit in session._state.units:
			assert(unit.position.x >= 0.0 and unit.position.y >= 0.0 and unit.position.x <= arena.x and unit.position.y <= arena.y)
	var siege := _setup(1000, 1000)
	siege.siege = true
	var walled := Factory.create(siege, _catalog)
	assert(walled != null and walled._state.arena_size == Config.ARENA_SIZE, "A siege keeps the field its walls are laid out for")

func _check_vegetation_band() -> void:
	# The base field keeps the browser layout; the band where armies stand grows with a larger field.
	for arena in [MEDIUM, LARGE]:
		for seed_value in [1, 7, 4242]:
			for plant in VegetationSetup.create(arena, seed_value, "grass"):
				if plant.trunk_radius <= 0.0: continue
				var band: float = VegetationSetup.FORMATION_CLEARANCE * arena.y / Config.ARENA_SIZE.y
				var inner: float = VegetationSetup.FORMATION_CLEARANCE * arena.x / Config.ARENA_SIZE.x
				assert(not (absf(plant.position.y - arena.y * 0.5) < band and plant.position.x > inner and plant.position.x < arena.x - inner))
