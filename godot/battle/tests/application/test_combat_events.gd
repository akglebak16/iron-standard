extends SceneTree
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Session = preload("res://battle/application/session.gd")
const Event = preload("res://battle/combat_event.gd")
const Combat = preload("res://battle/rules/combat.gd")
const Charge = preload("res://battle/rules/charge.gd")
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
	assert(blocked.size() == 1 and blocked[0].kind == Event.Kind.BLOCK)
	assert(blocked[0].attack == Event.Attack.MELEE and enemy.hp == 100)
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
	var old_position: Vector2 = enemy.position
	events[2].position = Vector2.INF
	assert(enemy.position == old_position)
	battle.kill(enemy)
	session.advance(STEP)
	assert(session.take_events().is_empty())
	print("Combat event tests passed")
	quit(0)
