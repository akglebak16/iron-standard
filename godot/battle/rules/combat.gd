extends RefCounted
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")

const Config = preload("res://battle/config.gd")
const EquipmentConfig = preload("res://equipment/config.gd")
const Block = preload("res://battle/rules/block.gd")
const DamageType = preload("res://equipment/rules/damage_type.gd")

static func strike(battle: State, attacker: Unit, target: Unit, rng: RandomNumberGenerator, damage_scale: float = 1.0) -> int:
	var incoming: float = (attacker.position - target.position).angle()
	var rear := absf(wrapf(incoming - target.facing, -PI, PI)) > Config.REAR_ANGLE
	var raw: float = attacker.damage * damage_scale * rng.randf_range(Config.MELEE_DAMAGE_MIN, Config.MELEE_DAMAGE_MAX)
	if not rear and Block.check(target, incoming, false, rng):
		return 0
	if attacker.attack_range > 0.0:
		raw *= Config.RANGED_MELEE_DAMAGE_MULTIPLIER
	if rear:
		raw *= Config.REAR_DAMAGE_MULTIPLIER
	if attacker.anti_cavalry and target.mounted:
		raw *= Config.ANTI_CAVALRY_MULTIPLIER
	if attacker.damage_type == EquipmentConfig.DAMAGE_TYPE_BLUNT or (attacker.damage_type.is_empty() and attacker.weapon_kind in ["club", "mace"]):
		if target.undead_kind == "skel":
			raw *= Config.SKELETON_BLUNT_MULTIPLIER
		elif target.undead_kind == "zombie":
			raw *= Config.ZOMBIE_BLUNT_MULTIPLIER
	if attacker.damage_type.is_empty():
		return battle.hurt(target, raw, attacker)
	return battle.hurt(target, raw * DamageType.multiplier(attacker.damage_type, target.armor), attacker, DamageType.pierce(attacker.damage_type, target.armor, attacker.pierce))

static func hero_strike(battle: State, hero: Unit, target: Unit, previous_hits: int, rng: RandomNumberGenerator) -> int:
	var weapon: Dictionary = hero.hero_weapon
	var direction: float = (target.position - hero.position).angle()
	var incoming: float = (hero.position - target.position).angle()
	var rear := absf(wrapf(incoming - target.facing, -PI, PI)) > Config.REAR_ANGLE
	if not rear and Block.check(target, incoming, false, rng) and rng.randf() < Config.HERO_BLOCK_HOLD_CHANCE - float(weapon.get("brk", 0.0)):
		return 0
	var knockback: float = float(weapon.get("kb", Config.HERO_DEFAULT_KNOCKBACK))
	target.position += Vector2(cos(direction), sin(direction)) * Config.HERO_KNOCKBACK_DISTANCE * knockback
	var raw: float = hero.damage * rng.randf_range(Config.HERO_MELEE_DAMAGE_MIN, Config.HERO_MELEE_DAMAGE_MAX)
	if rear:
		raw *= Config.REAR_DAMAGE_MULTIPLIER
	if previous_hits > 0:
		raw *= float(weapon.get("fall", Config.HERO_FOLLOWUP_DAMAGE))
	if hero.anti_cavalry and target.mounted:
		raw *= Config.ANTI_CAVALRY_MULTIPLIER
	if hero.damage_type == EquipmentConfig.DAMAGE_TYPE_BLUNT:
		if target.undead_kind == "skel":
			raw *= Config.SKELETON_BLUNT_MULTIPLIER
		elif target.undead_kind == "zombie":
			raw *= Config.ZOMBIE_BLUNT_MULTIPLIER
	if hero.damage_type.is_empty():
		return battle.hurt(target, raw, hero)
	return battle.hurt(target, raw * DamageType.multiplier(hero.damage_type, target.armor), hero, DamageType.pierce(hero.damage_type, target.armor, hero.pierce))

static func shoot(attacker: Unit, target: Unit, rng: RandomNumberGenerator) -> Dictionary:
	var distance: float = attacker.position.distance_to(target.position)
	var duration: float = _flight_duration(attacker, distance)
	var aim: Vector2 = target.position + target.velocity * duration * Config.AIM_VELOCITY_LEAD
	return _make_projectile(attacker, aim, distance, duration, rng)

static func shoot_aim(attacker: Unit, direction: float, distance: float, rng: RandomNumberGenerator) -> Dictionary:
	var aim := attacker.position + Vector2(cos(direction), sin(direction)) * distance
	return _make_projectile(attacker, aim, distance, _flight_duration(attacker, distance), rng)

static func _flight_duration(attacker: Unit, distance: float) -> float:
	var speed: float = Config.THROW_SPEED if attacker.weapon_kind == Config.PROJECTILE_THROW_WEAPON else Config.SHOT_SPEED
	return distance / speed + Config.PROJECTILE_START_DELAY

static func _make_projectile(attacker: Unit, aim: Vector2, distance: float, duration: float, rng: RandomNumberGenerator) -> Dictionary:
	var spread: float = Config.SHOT_BASE_SCATTER + distance * attacker.accuracy
	var impact: Vector2 = aim
	impact += Vector2((rng.randf() + rng.randf() - 1.0) * spread, (rng.randf() + rng.randf() - 1.0) * spread)
	return {"side": attacker.side, "source": attacker, "origin": attacker.position - Vector2(0.0, Config.PROJECTILE_START_HEIGHT), "impact": impact, "damage": attacker.damage, "pierce": attacker.pierce, "damage_type": attacker.damage_type, "throwing": attacker.weapon_kind == Config.PROJECTILE_THROW_WEAPON, "crossbow": attacker.weapon_kind == Config.PROJECTILE_CROSSBOW_WEAPON, "time": 0.0, "duration": duration}

static func arrow_hit(battle: State, shot: Dictionary, target: Unit, rng: RandomNumberGenerator) -> int:
	var incoming: float = (shot.origin - target.position).angle()
	if Block.check(target, incoming, true, rng):
		return 0
	var raw: float = shot.damage * rng.randf_range(Config.ARROW_DAMAGE_MIN, Config.ARROW_DAMAGE_MAX)
	if target.undead_kind == "skel":
		raw *= Config.SKELETON_ARROW_MULTIPLIER
	var kind: String = shot.get("damage_type", "")
	if kind.is_empty():
		return battle.hurt(target, raw, shot.source, shot.pierce)
	return battle.hurt(target, raw * DamageType.multiplier(kind, target.armor), shot.source, DamageType.pierce(kind, target.armor, shot.pierce))
