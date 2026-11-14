extends SceneTree

const Config = preload("res://battle/config.gd")
const Unit = preload("res://battle/model/unit.gd")
const BattleState = preload("res://battle/model/state.gd")
const HeroControl = preload("res://battle/rules/hero_control.gd")

func _initialize() -> void:
	var battle = BattleState.new()
	battle.setup_groups()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var hero = Unit.new(0, 0, Vector2(100, 100), 120, 10, 3)
	hero.hero = true
	hero.speed = 100.0
	hero.damage = 100.0
	hero.attack_interval = 0.5
	var enemy = Unit.new(1, 1, Vector2(150, 100), 50, 0, 1)
	battle.add_unit(hero)
	battle.add_grouped_unit(enemy, Config.GROUP_INFANTRY)
	HeroControl.step(battle, hero, {"move": Vector2(2, 0), "face": 0.0, "sprint": true}, 0.1, rng)
	assert(hero.position.x > 100.0)
	assert(hero.stamina < Config.HERO_MAX_STAMINA)
	assert(hero.velocity.length() <= hero.speed * Config.HERO_FOOT_SPRINT_MULTIPLIER)
	var moving_stamina: float = hero.stamina
	HeroControl.step(battle, hero, {"move": Vector2.ZERO, "block": true}, 0.1, rng)
	assert(hero.blocking)
	assert(hero.stamina > moving_stamina)
	assert(not enemy.dead)
	HeroControl.step(battle, hero, {"face": 0.0, "attack": true}, 0.2, rng)
	assert(not hero.blocking)
	assert(enemy.dead)
	assert(hero.kills == 1)
	print("Hero control tests passed")
	quit(0)
