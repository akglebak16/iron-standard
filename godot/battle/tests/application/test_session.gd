extends SceneTree
const Session = preload("res://battle/application/session.gd")
const Factory = preload("res://battle/application/factory.gd")
const HeroInput = preload("res://battle/application/hero_input.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Catalog = preload("res://battle/data/catalog.gd")
const Config = preload("res://battle/config.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const TICK_SECONDS := 1.0 / 60.0
const REPLAY_TICKS := 120

func _initialize() -> void:
	_check_commands_and_lifetime()
	_check_factory_and_repeatability()
	print("Session tests passed")
	quit(0)

func _check_commands_and_lifetime() -> void:
	var state := State.new()
	state.setup_groups()
	var hero := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	hero.hero = true
	hero.speed = 100
	state.add_unit(hero)
	var ally := Unit.new(1, 0, Vector2(300, 300), 100, 0, 1)
	state.add_grouped_unit(ally, Config.GROUP_INFANTRY)
	var enemy := Unit.new(2, 1, Vector2(2000, 1000), 100, 0, 1)
	state.add_grouped_unit(enemy, Config.GROUP_INFANTRY)
	var session := Session.new(state, hero, RandomNumberGenerator.new())
	var frame := session.snapshot()
	frame.units[0].position = Vector2.INF
	frame.counts[0] = 999
	assert(hero.position == Vector2(100, 100))
	assert(session.snapshot().counts == [2, 1])
	assert(not session.issue_order("unknown", Vector2.ZERO, Config.ALL_GROUPS))
	assert(not session.issue_order(Config.ORDER_HOLD, Vector2.INF, Config.ALL_GROUPS))
	assert(not session.issue_order(Config.ORDER_HOLD, Vector2.ZERO, -1))
	var destination := Vector2(400, 400)
	assert(session.issue_order(Config.ORDER_HOLD, destination, Config.GROUP_INFANTRY))
	assert(state.groups[0][0].center != destination)
	var input := HeroInput.new()
	input.move = Vector2.RIGHT
	assert(session.set_hero_input(input))
	input.move = Vector2.LEFT # Commands own a copy of input values.
	for invalid_dt in [0.0, -1.0, NAN, INF]:
		session.advance(invalid_dt)
	assert(session.snapshot().tick == 0)
	session.advance(TICK_SECONDS)
	assert(state.groups[0][0].center == destination)
	assert(hero.position.x > 100)
	input.face = NAN
	assert(not session.set_hero_input(input))
	assert(not session.set_hero_input(null))
	state.kill(enemy)
	session.advance(TICK_SECONDS)
	assert(session.snapshot().outcome == Session.Outcome.VICTORY)
	var finished := session.snapshot()
	session.advance(TICK_SECONDS)
	assert(session.snapshot() == finished)
	assert(not session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS))
	assert(not session.set_hero_input(HeroInput.new()))
	# Hero death takes precedence over simultaneous enemy defeat, as in the preview.
	var fallen_state := State.new()
	fallen_state.setup_groups()
	var fallen_hero := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	fallen_hero.hero = true
	fallen_state.add_unit(fallen_hero)
	fallen_state.kill(fallen_hero)
	var fallen_session := Session.new(fallen_state, fallen_hero, RandomNumberGenerator.new())
	fallen_session.advance(TICK_SECONDS)
	assert(fallen_session.snapshot().outcome == Session.Outcome.HERO_DOWN)

func _check_factory_and_repeatability() -> void:
	var catalog := Catalog.new()
	assert(catalog.load_data())
	var setup: Setup = load("res://battle/data/demo_battle.tres")
	var original_army := setup.player_army.duplicate(true)
	var first := Factory.create(setup, catalog)
	var second := Factory.create(setup, catalog)
	assert(first != null and second != null)
	assert(first.snapshot() == second.snapshot())
	var input := HeroInput.new()
	input.move = Vector2.RIGHT
	input.sprint = true
	first.set_hero_input(input)
	second.set_hero_input(input)
	var untouched := second.snapshot()
	first.advance(TICK_SECONDS)
	assert(second.snapshot() == untouched)
	second.advance(TICK_SECONDS)
	for tick in REPLAY_TICKS:
		first.advance(TICK_SECONDS)
		second.advance(TICK_SECONDS)
		assert(first.snapshot() == second.snapshot())
	assert(setup.player_army == original_army)
	var mutable_setup: Setup = setup.duplicate(true)
	var detached := Factory.create(mutable_setup, catalog)
	var before_edit := detached.snapshot()
	mutable_setup.player_army[0].n = 999
	mutable_setup.hero_position = Vector2.ZERO
	assert(detached.snapshot() == before_edit)
	var invalid: Setup = setup.duplicate(true)
	invalid.hero_troop = "missing"
	assert(Factory.create(invalid, catalog) == null)
	invalid.hero_troop = setup.hero_troop
	invalid.enemy_army = [{"type": "missing", "n": 1}]
	assert(Factory.create(invalid, catalog) == null)
	assert(Factory.create(null, catalog) == null)
