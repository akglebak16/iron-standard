extends SceneTree
const Config = preload("res://core/battle/config.gd")
const EquipmentConfig = preload("res://core/equipment/config.gd")
const Damage = preload("res://core/battle/rules/damage.gd")
const DamageType = preload("res://core/equipment/rules/damage_type.gd")
const HeroControl = preload("res://core/battle/rules/hero_control.gd")
const Combat = preload("res://core/battle/rules/combat.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const RESOLVE_STEP := 0.01

func _initialize() -> void:
	_test_weapon_shape_damage_and_knockback()
	_test_block_break()
	_test_mounted_reach_and_locked_direction()
	_test_perk_armor_pierce()
	print("Hero strike tests passed")
	quit(0)

func _hero() -> Unit:
	var hero := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	hero.hero = true
	hero.damage = 40.0
	hero.attack_interval = 1.0
	return hero

func _swing(battle: State, hero: Unit, rng: RandomNumberGenerator, resolve_face: float = 0.0) -> void:
	HeroControl.step(battle, hero, {"face": 0.0, "attack": true}, Config.HERO_ATTACK_WINDUP, rng)
	assert(hero.attack_windup == 0.0)
	HeroControl.step(battle, hero, {"face": resolve_face}, RESOLVE_STEP, rng)

func _test_weapon_shape_damage_and_knockback() -> void:
	var battle := State.new()
	var hero := _hero()
	hero.hero_weapon = {"reach": 20.0, "arc": 0.5, "cleave": 2, "fall": 0.4, "kb": 2.0}
	hero.damage_type = EquipmentConfig.DAMAGE_TYPE_PIERCE
	hero.pierce = 0.1
	battle.add_unit(hero)
	var targets := [Vector2(165, 100), Vector2(170, 100), Vector2(160, 100), Vector2(140, 140), Vector2(180, 100)]
	for position in targets:
		var enemy := Unit.new(battle.units.size(), 1, position, 1000, 20, 1)
		enemy.facing = PI
		battle.add_unit(enemy)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var reference := RandomNumberGenerator.new()
	reference.seed = 23
	_swing(battle, hero, rng, PI) # Facing changes after the swing starts; aim stays at zero.
	for index in 2:
		var enemy: Unit = battle.units[index + 1]
		var raw: float = hero.damage * reference.randf_range(Config.HERO_MELEE_DAMAGE_MIN, Config.HERO_MELEE_DAMAGE_MAX)
		if index > 0:
			raw *= 0.4
		var expected: int = Damage.after_armor(raw, enemy.armor, DamageType.pierce(hero.damage_type, enemy.armor, hero.pierce))
		assert(enemy.hp == 1000.0 - expected)
		assert(enemy.position == targets[index] + Vector2(10, 0))
	assert(battle.units[3].hp == 1000.0) # Cleave limit.
	assert(battle.units[4].hp == 1000.0) # Outside weapon arc.
	assert(battle.units[5].hp == 1000.0) # Outside reach.
	assert(hero.damage == 40.0)

func _test_block_break() -> void:
	var battle := State.new()
	var hero := _hero()
	hero.hero_weapon = {"brk": 1.0}
	var shielded := Unit.new(1, 1, Vector2(140, 100), 100, 0, 1)
	shielded.facing = PI
	shielded.block_chance = 1.0
	battle.add_unit(hero)
	battle.add_unit(shielded)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_swing(battle, hero, rng)
	assert(shielded.hp < 100.0)

func _test_mounted_reach_and_locked_direction() -> void:
	var battle := State.new()
	var hero := _hero()
	hero.hero_weapon = {"reach": 0.0}
	var target := Unit.new(1, 1, Vector2(155, 100), 100, 0, 1)
	target.facing = PI
	battle.add_unit(hero)
	battle.add_unit(target)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_swing(battle, hero, rng)
	assert(target.hp == 100.0)
	hero.mounted = true
	hero.attack_cooldown = 0.0
	_swing(battle, hero, rng)
	assert(target.hp < 100.0)

func _test_perk_armor_pierce() -> void:
	for damage_type in [EquipmentConfig.DAMAGE_TYPE_PIERCE, ""]:
		var battle := State.new()
		var hero := _hero()
		hero.damage_type = damage_type
		hero.pierce = 0.1
		hero.perk_effects = {"mpierce": 0.06}
		var target := Unit.new(1, 1, Vector2(140, 100), 100, 50, 1)
		target.facing = PI
		battle.add_unit(hero)
		battle.add_unit(target)
		var rng := RandomNumberGenerator.new()
		rng.seed = 91
		var reference := RandomNumberGenerator.new()
		reference.seed = rng.seed
		var raw: float = hero.damage * reference.randf_range(Config.HERO_MELEE_DAMAGE_MIN, Config.HERO_MELEE_DAMAGE_MAX)
		var expected_pierce: float = DamageType.pierce(damage_type, target.armor, hero.pierce + 0.06) if not damage_type.is_empty() else Config.HERO_UNARMED_PIERCE + 0.06
		var expected: int = Damage.after_armor(raw * (DamageType.multiplier(damage_type, target.armor) if not damage_type.is_empty() else 1.0), target.armor, expected_pierce)
		assert(Combat.hero_strike(battle, hero, target, 0, rng) == expected)
		assert(target.hp == 100 - expected)
