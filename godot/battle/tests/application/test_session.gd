extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Session = preload("res://battle/application/session.gd")
const Factory = preload("res://battle/application/factory.gd")
const HeroInput = preload("res://battle/application/hero_input.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const Config = preload("res://battle/config.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Event = preload("res://battle/combat_event.gd")
const TICK_SECONDS := 1.0 / 60.0
const REPLAY_TICKS := 120

func _initialize() -> void:
	_check_commands_and_lifetime()
	_check_hero_down_continues_battle()
	_check_factory_and_repeatability()
	_check_weapon_swap()
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
	assert(session.snapshot().outcome == Session.Outcome.RUNNING)
	assert(session.result().is_empty())
	session.advance(Config.MORALE_TICK_SECONDS)
	assert(session.snapshot().outcome == Session.Outcome.RUNNING)
	session.advance(Config.BATTLE_END_DELAY_SECONDS - TICK_SECONDS)
	assert(session.snapshot().outcome == Session.Outcome.RUNNING)
	session.advance(TICK_SECONDS * 2.0)
	assert(session.snapshot().outcome == Session.Outcome.VICTORY)
	assert(session.result().win and not session.result().heroDown)
	var detached_result: Dictionary = session.result()
	detached_result.left.clear()
	assert(not session.result().left.is_empty())
	var finished := session.snapshot()
	session.advance(TICK_SECONDS)
	assert(session.snapshot() == finished)
	assert(not session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS))
	assert(not session.set_hero_input(HeroInput.new()))
	# Without any surviving side, the browser resolves a defeat after the battle-end delay.
	var fallen_state := State.new()
	fallen_state.setup_groups()
	var fallen_hero := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	fallen_hero.hero = true
	fallen_state.add_unit(fallen_hero)
	fallen_state.kill(fallen_hero)
	var fallen_session := Session.new(fallen_state, fallen_hero, RandomNumberGenerator.new())
	fallen_session.advance(TICK_SECONDS)
	assert(fallen_session.snapshot().outcome == Session.Outcome.HERO_DOWN)
	fallen_session.advance(Config.BATTLE_END_DELAY_SECONDS + TICK_SECONDS)
	assert(fallen_session.snapshot().outcome == Session.Outcome.DEFEAT)
	assert(fallen_session.snapshot().hero_down)
	assert(fallen_session.snapshot().camera_target == Vector2.INF)

func _check_hero_down_continues_battle() -> void:
	var state := State.new()
	state.setup_groups()
	var hero := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	hero.hero = true
	var ally := Unit.new(1, 0, Vector2(400, 100), 100, 0, 1)
	var enemy := Unit.new(2, 1, Vector2(2000, 100), 100, 0, 1)
	state.add_unit(hero)
	state.add_grouped_unit(ally, Config.GROUP_INFANTRY)
	state.add_grouped_unit(enemy, Config.GROUP_INFANTRY)
	state.groups[0][Config.GROUP_INFANTRY].order = Config.ORDER_FOLLOW
	state.kill(hero, enemy)
	assert(state.groups[0][Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE)
	assert(ally.morale == ally.base_morale - Config.HERO_DOWN_MORALE_LOSS)
	var session := Session.new(state, hero, RandomNumberGenerator.new())
	assert(not session.set_hero_input(HeroInput.new()))
	session.advance(TICK_SECONDS)
	assert(session.snapshot().outcome == Session.Outcome.HERO_DOWN)
	assert(session.snapshot().tick == 1)
	assert(session.snapshot().camera_target == (ally.position + enemy.position) * 0.5)
	state.kill(enemy, ally)
	session.advance(Config.MORALE_TICK_SECONDS)
	assert(session.snapshot().outcome == Session.Outcome.HERO_DOWN)
	assert(session.snapshot().camera_target == ally.position)
	session.advance(Config.BATTLE_END_DELAY_SECONDS + TICK_SECONDS)
	assert(session.snapshot().outcome == Session.Outcome.VICTORY)
	assert(session.snapshot().hero_down)
	assert(session.result().win and session.result().heroDown)

func _check_factory_and_repeatability() -> void:
	var catalog := Catalog.new()
	assert(ContentLoader.populate(catalog))
	var setup: Setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.companion_profiles.clear()
	setup.hero_profile.clear()
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

func _check_weapon_swap() -> void:
	var troops := Catalog.new()
	var gear_catalog := GearCatalog.new()
	assert(ContentLoader.populate(troops) and ContentLoader.populate(gear_catalog))
	var setup: Setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.companion_profiles.clear()
	setup.hero_profile = {"str": 3, "vit": 3, "hp": 0.5, "eq": {"head": "head_cap", "body": "body_mail", "melee": "sword_knight", "ranged": "jav_heavy", "shield": "shield_plank"}, "sel": "melee"}
	var session := Factory.create(setup, troops, gear_catalog)
	assert(session != null)
	var hero: Unit = session._hero
	var health: float = hero.hp
	var maximum: float = hero.max_hp
	assert(hero.weapon_kind == "sword" and hero.attack_range == 0.0)
	var input := HeroInput.new()
	input.swap = true
	hero.attack_windup = TICK_SECONDS * 2.0
	assert(session.set_hero_input(input))
	session.advance(TICK_SECONDS)
	assert(hero.hero_weapon.id == "sword_knight")
	assert(not session.take_events().any(func(event): return event.kind == Event.Kind.WEAPON_SWAPPED))
	hero.attack_windup = -1.0
	session.advance(TICK_SECONDS)
	assert(hero.hero_weapon.id == "sword_knight")
	input.swap = false
	assert(session.set_hero_input(input))
	session.advance(TICK_SECONDS)
	input.swap = true
	assert(session.set_hero_input(input))
	setup.hero_profile.eq.ranged = "missing" # Running session owns a detached profile.
	session.advance(TICK_SECONDS)
	assert(hero.weapon_kind == "throw" and hero.attack_range == 480.0)
	assert(hero.hero_weapon.id == "jav_heavy")
	assert(session.snapshot().hero_weapon_name == hero.hero_weapon.name)
	var changed := session.take_events().filter(func(event): return event.kind == Event.Kind.WEAPON_SWAPPED)
	assert(changed.size() == 1 and changed[0].weapon_name == hero.hero_weapon.name and changed[0].target_id == hero.id)
	assert(hero.hp == health and hero.max_hp == maximum)
	assert(hero.attack_cooldown > 0.0)
	session.advance(TICK_SECONDS)
	assert(hero.weapon_kind == "throw") # Holding X does not switch again.
	assert(not session.take_events().any(func(event): return event.kind == Event.Kind.WEAPON_SWAPPED))
	input.swap = false
	session.set_hero_input(input)
	session.advance(TICK_SECONDS)
	input.swap = true
	session.set_hero_input(input)
	session.advance(TICK_SECONDS)
	assert(hero.weapon_kind == "sword" and hero.attack_range == 0.0)
	assert(hero.hero_weapon.id == "sword_knight")
	assert(hero.hp == health)
	var melee_only: Setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	melee_only.companion_profiles.clear()
	melee_only.hero_profile = {"eq": {"melee": "sword_old"}, "sel": "ranged"}
	var no_ranged := Factory.create(melee_only, troops, gear_catalog)
	var no_ranged_input := HeroInput.new()
	no_ranged_input.swap = true
	no_ranged.set_hero_input(no_ranged_input)
	no_ranged.advance(TICK_SECONDS)
	assert(no_ranged._hero.weapon_kind == "sword")
	assert(no_ranged.take_events().any(func(event): return event.kind == Event.Kind.RANGED_WEAPON_UNAVAILABLE))
	no_ranged.advance(TICK_SECONDS)
	assert(not no_ranged.take_events().any(func(event): return event.kind == Event.Kind.RANGED_WEAPON_UNAVAILABLE))
