extends SceneTree
## TERRAIN.md 4.4 (stage Р1а): the terrain rules on made-up grids (speed by cover and slope with its floor, no charge,
## shooting range from higher ground, sight into the forest, blows from higher ground and from a ford, cover from
## arrows), and the open field: without terrain, and with the rules switched on over open, flat ground, the battle is
## bit for bit the one without terrain on both backends.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const TerrainGrid = preload("res://core/battle/model/terrain_grid.gd")
const TerrainRules = preload("res://core/battle/rules/terrain_rules.gd")
const Combat = preload("res://core/battle/rules/combat.gd")
const Charge = preload("res://core/battle/rules/charge.gd")
const Event = preload("res://core/battle/combat_event.gd")
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
const NativeColumns = preload("res://adapters/godot/native/columns.gd")
const Templates = preload("res://core/battle/data/terrain_templates.gd")

const CELL := Config.TERRAIN_CELL
const AT := Vector2(1000, 800)

func _initialize() -> void:
	_check_speed()
	_check_fighting_rules()
	_check_arrows()
	_check_blows()
	_check_open_field()
	print("Terrain rule tests passed")
	quit(0)

static func _grid() -> TerrainGrid:
	var grid := TerrainGrid.create(Config.ARENA_SIZE)
	grid.refresh()
	return grid

static func _lay(grid: TerrainGrid, at: Vector2, cover: int, height := -1) -> void:
	grid.cover[grid.index(at)] = cover
	if height >= 0:
		grid.elevation[grid.index(at)] = height
	grid.refresh()

## A slope rising along +x through AT: the cells left and right of AT differ by `rise` bytes.
static func _slope(grid: TerrainGrid, rise: int) -> void:
	for y in grid.height:
		for x in grid.width:
			grid.elevation[y * grid.width + x] = clampi(100 + (x - grid.index(AT) % grid.width) * rise / 2, 0, 255)
	grid.refresh()

func _check_speed() -> void:
	var grid := _grid()
	var east := Vector2(100, 0)
	assert(TerrainRules.speed_scale(grid, AT, east, 100.0) == 1.0, "Open, flat ground does not change the speed")
	for cover in TerrainGrid.Cover.values():
		_lay(grid, AT, cover)
		assert(TerrainRules.speed_scale(grid, AT, east, 100.0) == maxf(Config.TERRAIN_MIN_SPEED, Config.TERRAIN_COVER_SPEED[cover]))
	_lay(grid, AT, TerrainGrid.Cover.FOREST)
	assert(is_equal_approx(TerrainRules.speed_scale(grid, AT, east, 100.0), 0.75) and is_equal_approx(Config.TERRAIN_COVER_SPEED[TerrainGrid.Cover.FORD], 0.5))
	_slope(grid, 8)
	var forest_up := TerrainRules.speed_scale(grid, AT, east, 100.0)
	assert(is_equal_approx(forest_up, 0.75 * Config.TERRAIN_UPHILL_SPEED), "Uphill in the forest: %s" % forest_up)
	assert(is_equal_approx(TerrainRules.speed_scale(grid, AT, -east, 100.0), 0.75 * Config.TERRAIN_DOWNHILL_SPEED), "Downhill")
	assert(TerrainRules.speed_scale(grid, AT, Vector2(0, 100), 100.0) == 0.75, "Along the slope it is flat")
	_slope(grid, int(Config.TERRAIN_SLOPE_STEP) - 2)
	assert(TerrainRules.speed_scale(grid, AT, east, 100.0) == 0.75, "A gentler rise is no slope")
	_slope(grid, 8)
	_lay(grid, AT, TerrainGrid.Cover.WATER)
	assert(TerrainRules.speed_scale(grid, AT, east, 100.0) == Config.TERRAIN_MIN_SPEED, "Never below the floor")

func _check_fighting_rules() -> void:
	var grid := _grid()
	var far := AT + Vector2(400, 0)
	assert(not TerrainRules.no_charge(null, AT) and not TerrainRules.no_charge(grid, AT))
	for cover in [TerrainGrid.Cover.FOREST, TerrainGrid.Cover.FORD, TerrainGrid.Cover.WATER]:
		_lay(grid, AT, cover)
		assert(TerrainRules.no_charge(grid, AT))
	_lay(grid, AT, TerrainGrid.Cover.BRUSH)
	assert(not TerrainRules.no_charge(grid, AT), "Brush does not stop a charge")
	# Sight: deep in the forest is hidden from a shooter, the forest edge within 250 is not.
	_lay(grid, far, TerrainGrid.Cover.FOREST)
	assert(TerrainRules.hidden(grid, far, 400.0) and not TerrainRules.hidden(grid, far, Config.TERRAIN_FOREST_SIGHT))
	assert(not TerrainRules.hidden(grid, AT, 400.0) and not TerrainRules.hidden(null, far, 400.0))
	# Range: higher by TERRAIN_HIGHER_STEP or more.
	assert(TerrainRules.range_scale(grid, AT, far) == 1.0)
	_lay(grid, AT, TerrainGrid.Cover.OPEN, 100 + Config.TERRAIN_HIGHER_STEP)
	_lay(grid, far, TerrainGrid.Cover.OPEN, 100)
	assert(TerrainRules.range_scale(grid, AT, far) == Config.TERRAIN_HIGH_RANGE_MULTIPLIER and TerrainRules.range_scale(grid, far, AT) == 1.0)
	_lay(grid, AT, TerrainGrid.Cover.OPEN, 100 + Config.TERRAIN_HIGHER_STEP - 1)
	assert(TerrainRules.range_scale(grid, AT, far) == 1.0)
	# A rider in the forest does not charge; on the open ground next to it he does.
	var state := _state()
	var rider := _unit(state, 5, 0, AT)
	var foe := _unit(state, 6, 1, AT + Vector2(30, 0))
	rider.mounted = true
	rider.velocity = Vector2(Config.CHARGE_MIN_SPEED + 50.0, 0)
	assert(Charge.can_hit(rider, foe, grid))
	_lay(grid, AT, TerrainGrid.Cover.FOREST)
	assert(not Charge.can_hit(rider, foe, grid) and Charge.can_hit(rider, foe, null))

func _check_arrows() -> void:
	for cover in [TerrainGrid.Cover.OPEN, TerrainGrid.Cover.BRUSH, TerrainGrid.Cover.FOREST]:
		var state := _state()
		var grid := _grid()
		_lay(grid, AT, cover)
		state.set_terrain(grid)
		if cover == TerrainGrid.Cover.OPEN:
			assert(state.terrain_rules == null, "An open grid switches the rules off")
			_lay(grid, AT + Vector2(900, 600), TerrainGrid.Cover.BRUSH)
			state.set_terrain(grid)
		var shooter := _unit(state, 7, 0, AT - Vector2(300, 0))
		var target := _unit(state, 8, 1, AT)
		target.hp = 1e9
		target.max_hp = 1e9
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var hits := 0
		var trials := 3000
		for i in trials:
			var shot := {"side": 0, "source": shooter, "origin": shooter.position, "impact": target.position, "damage": 10.0, "pierce": 0.0, "damage_type": ""}
			if Combat.arrow_hit(state, shot, target, rng) > 0 or state.take_events().any(func(e): return e.kind == Event.Kind.BLOCK):
				hits += 1
		var expected := TerrainRules.hit_chance(state.terrain_rules, AT)
		assert(absf(float(hits) / trials - expected) < 0.03, "Arrows reaching a man in cover %d: %d of %d" % [cover, hits, trials])

func _check_blows() -> void:
	var losses := {}
	for case in ["flat", "high", "low", "ford", "bank"]:
		var state := _state()
		var grid := _grid()
		var attacker := _unit(state, 21, 0, AT)
		var target := _unit(state, 22, 1, AT + Vector2(CELL, 0))
		match case:
			"high": _lay(grid, AT, TerrainGrid.Cover.OPEN, 40)
			"low": _lay(grid, target.position, TerrainGrid.Cover.OPEN, 40)
			"ford": _lay(grid, AT, TerrainGrid.Cover.FORD)
			"bank": _lay(grid, target.position, TerrainGrid.Cover.FORD)
		_lay(grid, Vector2(2500, 1600), TerrainGrid.Cover.BRUSH) # Rules on in every case, far from the fight.
		state.set_terrain(grid)
		target.hp = 1e6
		target.max_hp = 1e6
		target.facing = PI # Facing the attacker; no block chance on synthetic units.
		attacker.damage = 400.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 17
		var before := target.hp
		Combat.strike(state, attacker, target, rng)
		losses[case] = before - target.hp
	assert(absf(losses.high - losses.flat * Config.TERRAIN_HIGH_STRIKE_MULTIPLIER) <= 1.0, "From higher ground: %s" % losses)
	assert(losses.low == losses.flat, "Uphill gives no bonus: %s" % losses)
	assert(absf(losses.ford - losses.flat / Config.TERRAIN_BANK_DEFENSE) <= 1.0, "Against the bank from a ford: %s" % losses)
	assert(losses.bank == losses.flat, "From the bank into the ford: no defence bonus: %s" % losses)

## Bit for bit: a battle on the open field (no terrain), the same battle with an open-description template, and the
## same battle with the rules switched on over open, flat ground (one brush cell in a corner nobody reaches), on the
## GDScript and the native backends. Every rule then multiplies by exactly 1 and draws no random number.
func _check_open_field() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	for native in [false, true]:
		var battles := []
		for variant in ["none", "open", "ruled"]:
			var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
			setup.hero_profile.clear()
			setup.companion_profiles.clear()
			setup.player_army.assign([{"type": "n1", "n": 30}, {"type": "n2a", "n": 20}, {"type": "n3c", "n": 12}])
			setup.enemy_army.assign([{"type": "k1", "n": 30}, {"type": "k2a", "n": 20}, {"type": "k2c", "n": 12}])
			if variant == "open":
				setup.terrain = {"plain": 1.0, "biome": "grass"}
			var battle = Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create() if native else Callable(), NativeColumns.create() if native else null)
			assert(battle != null and battle._state.terrain_rules == null, "No rules on an open field")
			if variant == "ruled":
				var grid := TerrainGrid.create(battle._state.arena_size)
				grid.cover[grid.cover.size() - 1] = TerrainGrid.Cover.BRUSH
				battle._state.set_terrain(grid)
				assert(battle._state.terrain_rules != null and not battle._state.terrain_context.is_empty())
			battle.issue_order("charge", Vector2.ZERO, 3)
			battles.append(battle)
		for tick in 900:
			if tick == 600:
				for battle in battles: battle._state.kill(battle._hero)
			for battle in battles: battle.step()
			var events: Array = battles[0].take_events()
			for k in range(1, battles.size()):
				assert(battles[k]._rng.state == battles[0]._rng.state, "RNG tick %d native %s variant %d" % [tick, native, k])
				assert(battles[k].take_events() == events, "Events tick %d native %s variant %d" % [tick, native, k])
				for field in ["positions", "velocities", "real_fields", "integer_fields"]:
					assert(battles[k]._state.motion.get(field) == battles[0]._state.motion.get(field), "Columns %s tick %d native %s variant %d" % [field, tick, native, k])
		assert(battles[0].snapshot() == battles[2].snapshot())

static func _state() -> State:
	var state := State.new()
	state.setup_groups()
	return state

static func _unit(state: State, id: int, side: int, at: Vector2) -> Unit:
	var unit := Unit.new(id, side, at, 100, 0, 1)
	unit.speed = 50.0
	unit.facing = 0.0 if side == 0 else PI
	state.add_grouped_unit(unit, Config.GROUP_INFANTRY)
	return unit
