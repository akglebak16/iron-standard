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
	_check_cleave_damage()
	print("Hero control tests passed")
	quit(0)

func _check_cleave_damage() -> void:
	var battle := BattleState.new()
	var hero := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	hero.hero = true
	hero.damage = 40
	battle.add_unit(hero)
	for index in Config.HERO_MAX_HITS + 1:
		var enemy := Unit.new(index + 1, 1, Vector2(120, 100), 1000, 0, 1)
		enemy.facing = PI # Frontal hit without block, armor, or rear bonus.
		battle.add_unit(enemy)
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = rng.seed
	HeroControl.step(battle, hero, {"face": 0.0, "attack": true}, Config.HERO_ATTACK_WINDUP, rng)
	for index in Config.HERO_MAX_HITS:
		expected_rng.randf() # Block roll, same consumption order as Combat.strike.
		var scale: float = 1.0 if index == 0 else Config.HERO_FOLLOWUP_DAMAGE
		var raw := hero.damage * scale * expected_rng.randf_range(Config.MELEE_DAMAGE_MIN, Config.MELEE_DAMAGE_MAX)
		var expected: int = preload("res://battle/rules/damage.gd").after_armor(raw, 0)
		assert(battle.units[index + 1].hp == 1000 - expected)
	assert(battle.units.back().hp == 1000) # Hit limit preserved.
	assert(hero.damage == 40) # Follow-up modifier never changes the base stat.
