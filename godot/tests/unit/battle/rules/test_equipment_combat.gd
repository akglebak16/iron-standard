extends SceneTree
const Config = preload("res://core/battle/config.gd")
const EquipmentConfig = preload("res://core/equipment/config.gd")
const Damage = preload("res://core/battle/rules/damage.gd")
const DamageType = preload("res://core/equipment/rules/damage_type.gd")
const Combat = preload("res://core/battle/rules/combat.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")

func _initialize() -> void:
	_test_equipped_melee()
	_test_projectile_captures_damage_type()
	print("Equipment combat tests passed")
	quit(0)

func _test_equipped_melee() -> void:
	var battle := State.new()
	var attacker := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	attacker.damage = 40.0
	attacker.damage_type = EquipmentConfig.DAMAGE_TYPE_PIERCE
	attacker.pierce = 0.1
	var target := Unit.new(1, 1, Vector2(120, 100), 100, 20, 1)
	target.facing = PI
	battle.add_unit(attacker)
	battle.add_unit(target)
	var rng := RandomNumberGenerator.new()
	rng.seed = 32
	var reference := RandomNumberGenerator.new()
	reference.seed = 32
	var raw: float = attacker.damage * reference.randf_range(Config.MELEE_DAMAGE_MIN, Config.MELEE_DAMAGE_MAX)
	var expected := Damage.after_armor(raw, target.armor, DamageType.pierce(attacker.damage_type, target.armor, attacker.pierce))
	assert(Combat.strike(battle, attacker, target, rng) == expected)
	assert(target.hp == 100.0 - expected)

func _test_projectile_captures_damage_type() -> void:
	var battle := State.new()
	var attacker := Unit.new(0, 0, Vector2(100, 100), 100, 0, 1)
	attacker.damage = 40.0
	attacker.damage_type = EquipmentConfig.DAMAGE_TYPE_CUT
	attacker.pierce = 0.05
	var target := Unit.new(1, 1, Vector2(200, 100), 100, 8, 1)
	battle.add_unit(attacker)
	battle.add_unit(target)
	var rng := RandomNumberGenerator.new()
	rng.seed = 72
	var shot: Dictionary = Combat.shoot(attacker, target, rng)
	attacker.damage_type = EquipmentConfig.DAMAGE_TYPE_BLUNT
	var reference := RandomNumberGenerator.new()
	reference.seed = 72
	for draw in 4:
		reference.randf()
	var raw: float = shot.damage * reference.randf_range(Config.ARROW_DAMAGE_MIN, Config.ARROW_DAMAGE_MAX) * DamageType.multiplier(EquipmentConfig.DAMAGE_TYPE_CUT, target.armor)
	var expected := Damage.after_armor(raw, target.armor, DamageType.pierce(EquipmentConfig.DAMAGE_TYPE_CUT, target.armor, shot.pierce))
	assert(shot.damage_type == EquipmentConfig.DAMAGE_TYPE_CUT)
	assert(Combat.arrow_hit(battle, shot, target, rng) == expected)
	assert(target.hp == 100.0 - expected)
