extends SceneTree
## DESIGN.md 1.4, stage K: a fast hero circling in front of the enemy line must not drag the enemy
## infantry around while the player's squads stand still; the line goes for the squads instead.
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const HeroInput = preload("res://core/battle/application/hero_input.gd")
const Config = preload("res://core/battle/config.gd")

const TICK_SECONDS := 1.0 / 60.0
const ORBIT_CENTER := Vector2(1180, 850)
const ORBIT_RADIUS := 150.0
const HERO_SPEED := 160.0 # A good horse; faster than any infantry (42-64).
const ENEMY_LINE := Vector2(1380, 850)
const PLAYER_INFANTRY := Vector2(700, 650)
const PLAYER_ARCHERS := Vector2(700, 1050)

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	_test_lone_hero_does_not_start_charge(catalog)
	_test_hopeless_chase_called_off(catalog)
	print("AI kite tests passed")
	quit(0)

func _session(catalog: Catalog, charge: bool):
	var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	setup.player_army.assign([{"type": "n1", "n": 15}, {"type": "n2a", "n": 20}])
	setup.enemy_army.assign([{"type": "e1", "n": 30}])
	setup.hero_position = ORBIT_CENTER + Vector2(ORBIT_RADIUS, 0)
	var session = Factory.create(setup, catalog)
	assert(session != null)
	var state = session._state
	_place(state, state.groups[0][Config.GROUP_INFANTRY], PLAYER_INFANTRY, 0.0)
	_place(state, state.groups[0][Config.GROUP_ARCHERS], PLAYER_ARCHERS, 0.0)
	_place(state, state.groups[1][Config.GROUP_INFANTRY], ENEMY_LINE, PI)
	for group in state.groups[0]:
		group.order = Config.ORDER_HOLD
	var hero = session._hero
	hero.speed = HERO_SPEED
	hero.max_hp = 1000000.0
	hero.hp = hero.max_hp
	if charge:
		state.groups[1][Config.GROUP_INFANTRY].order = Config.ORDER_CHARGE
	return session

func _place(state, group, at: Vector2, facing: float) -> void:
	group.center = at
	group.direction = facing
	group.layout(true)
	for unit in group.units:
		unit.position = group.slot_position(unit, state.arena_size)
		unit.velocity = Vector2.ZERO

## Scripted kite: the hero rides a circle in front of the enemy line.
func _circle_step(session, input: HeroInput) -> void:
	var hero = session._hero
	var offset: Vector2 = hero.position - ORBIT_CENTER
	var radial := offset.normalized() if offset.length() > 1.0 else Vector2.RIGHT
	var move := Vector2(-radial.y, radial.x) + radial * clampf((ORBIT_RADIUS - offset.length()) / 40.0, -1.0, 1.0)
	input.move = move.normalized()
	input.face = move.angle()
	assert(session.set_hero_input(input))
	session.step()

func _ready_units(group) -> Array:
	return group.units.filter(func(u): return not u.dead and not u.gone and not u.fleeing)

func _nearest_squad_distance(state, point: Vector2) -> float:
	var closest := INF
	for group in state.groups[0]:
		for unit in _ready_units(group):
			closest = minf(closest, point.distance_to(unit.position))
	return closest

## Fighters running after the hero beyond striking distance.
func _hero_chasers(session, group) -> float:
	var ready := _ready_units(group)
	var chasing := 0
	for unit in ready:
		if unit.target_handle == session._hero.unit_handle and unit.ai_mode == Config.AI_MODE_MELEE and unit.position.distance_to(session._hero.position) > Config.AI_KITE_CONTACT_DISTANCE:
			chasing += 1
	return float(chasing) / maxf(1.0, ready.size())

func _test_lone_hero_does_not_start_charge(catalog: Catalog) -> void:
	var session = _session(catalog, false)
	var state = session._state
	var infantry = state.groups[1][Config.GROUP_INFANTRY]
	var input := HeroInput.new()
	var tempted := false
	for tick in 360:
		_circle_step(session, input)
		if session._hero.position.distance_to(infantry.center) < Config.AI_INFANTRY_CHARGE_DISTANCE:
			tempted = true
		if infantry.order == Config.ORDER_CHARGE:
			assert(_nearest_squad_distance(state, infantry.center) < Config.AI_INFANTRY_CHARGE_DISTANCE + Config.AI_INFANTRY_ADVANCE_SPEED, "Charged at tick %d without a squad in reach" % tick)
	assert(tempted, "The hero must ride within the old single-fighter charge distance")
	assert(infantry.order == Config.ORDER_HOLD)
	assert(infantry.center.x < ENEMY_LINE.x - Config.AI_INFANTRY_ADVANCE_SPEED, "The line keeps marching on the squads")

func _test_hopeless_chase_called_off(catalog: Catalog) -> void:
	var session = _session(catalog, true)
	var state = session._state
	var infantry = state.groups[1][Config.GROUP_INFANTRY]
	var input := HeroInput.new()
	var called_off := -1
	var reached := -1
	var peak_chasers := 0.0
	for tick in 1800:
		_circle_step(session, input)
		if called_off < 0:
			peak_chasers = maxf(peak_chasers, _hero_chasers(session, infantry))
			if infantry.kited:
				called_off = tick
				assert(infantry.focus_kind in [Config.GROUP_INFANTRY, Config.GROUP_ARCHERS])
				print("Kite called off at %.2f s, focus %d, missile losses %.2f" % [tick * TICK_SECONDS, infantry.focus_kind, state.missile_losses[1]])
		elif reached < 0 and _nearest_squad_distance(state, infantry.centroid()) < Config.AI_INFANTRY_CHARGE_DISTANCE:
			reached = tick
			print("Enemy line reached the player's squads at %.2f s" % (tick * TICK_SECONDS))
	assert(peak_chasers > Config.AI_KITE_CHASER_SHARE, "The forced charge must first run after the hero")
	assert(called_off >= 0 and called_off * TICK_SECONDS < Config.AI_KITE_SECONDS + 5.0, "The hopeless chase must be called off within a few seconds")
	assert(reached >= 0, "After calling off the chase the line must reach the player's squads")
	var chasers := _hero_chasers(session, infantry)
	print("Share still chasing the hero at the end: %.2f" % chasers)
	assert(chasers < 0.25)
