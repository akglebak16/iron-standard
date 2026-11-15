extends SceneTree

const Config = preload("res://core/battle/config.gd")
const EquipmentConfig = preload("res://core/equipment/config.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const BattleState = preload("res://core/battle/model/state.gd")
const HeroControl = preload("res://core/battle/rules/hero_control.gd")
const WIND_RESOLVE_STEP := 0.01

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
	_check_ranged_shot()
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
	assert(hero.attack_windup == 0.0)
	assert(battle.units[1].hp == 1000.0)
	HeroControl.step(battle, hero, {"face": 0.0}, WIND_RESOLVE_STEP, rng)
	for index in Config.HERO_MAX_HITS:
		var scale: float = 1.0 if index == 0 else Config.HERO_FOLLOWUP_DAMAGE
		var raw := hero.damage * scale * expected_rng.randf_range(Config.HERO_MELEE_DAMAGE_MIN, Config.HERO_MELEE_DAMAGE_MAX)
		var expected: int = preload("res://core/battle/rules/damage.gd").after_armor(raw, 0)
		assert(battle.units[index + 1].hp == 1000 - expected)
	assert(battle.units.back().hp == 1000) # Hit limit preserved.
	assert(hero.damage == 40) # Follow-up modifier never changes the base stat.

func _check_ranged_shot() -> void:
	var battle := BattleState.new()
	var hero := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	hero.hero = true
	hero.attack_range = 300.0
	hero.attack_interval = 1.2
	hero.weapon_kind = Config.PROJECTILE_THROW_WEAPON
	hero.damage_type = EquipmentConfig.DAMAGE_TYPE_PIERCE
	var close := Unit.new(1, 1, Vector2(200, 100), 100, 0, 1)
	var off_axis := Unit.new(2, 1, Vector2(170, 200), 100, 0, 1)
	battle.add_unit(hero)
	battle.add_unit(close)
	battle.add_unit(off_axis)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	HeroControl.step(battle, hero, {"face": 0.0, "attack": true}, Config.HERO_RANGED_WINDUP, rng)
	assert(battle.projectiles.is_empty())
	HeroControl.step(battle, hero, {"face": 0.0}, WIND_RESOLVE_STEP, rng)
	assert(battle.projectiles.size() == 1)
	var shot: Dictionary = battle.projectiles[0]
	assert(shot.throwing and shot.damage_type == EquipmentConfig.DAMAGE_TYPE_PIERCE)
	assert(is_equal_approx(shot.duration, 100.0 / Config.THROW_SPEED + Config.PROJECTILE_START_DELAY))
	assert(shot.impact.distance_to(close.position) <= Config.SHOT_BASE_SCATTER * 2.0)
	assert(close.hp == 100.0)
	var miss := BattleState.new()
	var other_hero := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	other_hero.hero = true
	other_hero.attack_range = 300.0
	miss.add_unit(other_hero)
	miss.add_unit(Unit.new(1, 1, Vector2(100, 250), 100, 0, 1))
	HeroControl.step(miss, other_hero, {"face": 0.0, "attack": true}, Config.HERO_RANGED_WINDUP, rng)
	assert(miss.projectiles.is_empty())
	HeroControl.step(miss, other_hero, {"face": 0.0}, WIND_RESOLVE_STEP, rng)
	assert(miss.projectiles.size() == 1)
	var missed: Dictionary = miss.projectiles[0]
	assert(is_equal_approx(missed.duration, 210.0 / Config.SHOT_SPEED + Config.PROJECTILE_START_DELAY))
	assert(missed.impact.distance_to(Vector2(310, 100)) <= Config.SHOT_BASE_SCATTER * 2.0)
