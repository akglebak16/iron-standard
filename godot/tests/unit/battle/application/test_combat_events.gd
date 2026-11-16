extends SceneTree
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Session = preload("res://core/battle/application/session.gd")
const Event = preload("res://core/battle/combat_event.gd")
const Combat = preload("res://core/battle/rules/combat.gd")
const Charge = preload("res://core/battle/rules/charge.gd")
const Tactics = preload("res://core/battle/rules/tactics.gd")
const Config = preload("res://core/battle/config.gd")
const SiegeSetup = preload("res://core/battle/data/siege_setup.gd")
const STEP := 1.0 / 60.0

func _initialize() -> void:
	var battle := State.new()
	battle.setup_groups()
	var hero := Unit.new(1, 0, Vector2(100, 100), 100, 0, 1)
	hero.hero = true
	hero.damage = 200
	var enemy := Unit.new(2, 1, Vector2(130, 100), 100, 0, 1)
	enemy.block_chance = 1.0
	enemy.facing = PI
	battle.add_unit(hero)
	battle.add_grouped_unit(enemy, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var session := Session.new(battle, hero, rng)
	assert(Combat.strike(battle, hero, enemy, rng) == 0)
	session.advance(STEP)
	var blocked := session.take_events()
	assert(blocked.size() == 2 and blocked[0].kind == Event.Kind.BATTLE_STARTED and blocked[1].kind == Event.Kind.BLOCK)
	assert(blocked[1].attack == Event.Attack.MELEE and enemy.hp == 100)
	assert(session.take_events().is_empty())
	enemy.block_chance = 0
	hero.velocity = Vector2(100, 0)
	var impact := Charge.hit(battle, hero, enemy, rng)
	assert(impact > 100 and enemy.dead)
	session.advance(STEP)
	var events := session.take_events()
	assert(events.size() == 3)
	assert(events[0].kind == Event.Kind.CHARGE and events[0].source_hero)
	assert(events[1].kind == Event.Kind.HIT and events[1].amount == impact)
	assert(events[2].kind == Event.Kind.DOWN and events[2].target_id == enemy.id)
	assert(events[2].attack == Event.Attack.CHARGE)
	assert(events[2].source_alive and events[2].source_id == hero.id)
	var old_position: Vector2 = enemy.position
	events[2].position = Vector2.INF
	assert(enemy.position == old_position)
	battle.kill(enemy)
	session.advance(STEP)
	assert(session.take_events().is_empty())
	_check_notices()
	_check_fatal_hit_metadata()
	print("Combat event tests passed")
	quit(0)

func _check_notices() -> void:
	var battle := State.new()
	battle.setup_groups()
	var hero := Unit.new(0, 0, Vector2(1500, 850), 100, 0, 1)
	hero.hero = true
	var ally := Unit.new(1, 0, hero.position + Vector2(0, 40), 100, 0, 1)
	var enemy := Unit.new(2, 1, Vector2(1900, 850), 100, 0, 1)
	battle.add_grouped_unit(ally, 0)
	battle.add_grouped_unit(enemy, 0)
	battle.add_unit(hero)
	SiegeSetup.apply(battle, 0.0)
	var session := Session.new(battle, hero, RandomNumberGenerator.new())
	assert(session.issue_order("charge", Vector2.ZERO, 1)) # Empty group.
	assert(session.issue_order("follow", Vector2.ZERO, 0))
	session.advance(STEP)
	assert(session.take_events() == [{"kind": Event.Kind.BATTLE_STARTED}, {"kind": Event.Kind.ORDER_APPLIED, "order": "follow", "selection": 0, "point": Vector2.ZERO}, {"kind": Event.Kind.WALL_ALERT}])
	session.advance(STEP)
	assert(session.take_events().is_empty())
	battle.wall.open_main_gate() # The garrison only comes out on time once a way is open.
	Tactics.siege_step(battle, Config.SIEGE_CAVALRY_FORCE_CHARGE_SECONDS + STEP)
	Tactics.siege_step(battle, Config.SIEGE_CAVALRY_FORCE_CHARGE_SECONDS + STEP * 2)
	assert(battle.take_events() == [{"kind": Event.Kind.GARRISON_CAVALRY}])
	battle.kill(enemy)
	session.advance(1.0)
	var decided := session.take_events()
	assert(decided[-1] == {"kind": Event.Kind.BATTLE_DECIDED, "won": true})
	assert(session.result().is_empty())
	session.advance(3.0)
	assert(session.result().win and session.take_events().is_empty())

func _check_fatal_hit_metadata() -> void:
	var battle := State.new()
	var source := Unit.new(1, 0, Vector2.ZERO, 100, 0, 1)
	var target := Unit.new(2, 1, Vector2.RIGHT, 100, 0, 1)
	source.weapon_kind = "club"
	target.hp = 25
	target.appearance = {"helm": "greathelm"}
	battle.hurt(target, 32, source, 0.0, null, Event.Attack.MELEE)
	var events := battle.take_events()
	assert(events.size() == 2 and events[1].kind == Event.Kind.DOWN)
	assert(events[1].melee_impact == Event.MeleeImpact.BLUNT and source.damage_type.is_empty())
	assert(events[1].amount == 32 and is_equal_approx(events[1].damage_fraction, 0.32))
	events[1].target_visual.look.clear()
	assert(target.appearance == {"helm": "greathelm"})
