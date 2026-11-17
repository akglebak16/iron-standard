extends RefCounted
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")

const Config = preload("res://core/battle/config.gd")
const EquipmentConfig = preload("res://core/equipment/config.gd")
const Block = preload("res://core/battle/rules/block.gd")
const DamageType = preload("res://core/equipment/rules/damage_type.gd")
const Event = preload("res://core/battle/combat_event.gd")
const MELEE_BLOCK_CONTACT := 10.0
const HERO_BLOCK_CONTACT := 8.0
const PROJECTILE_BLOCK_CONTACT_X := 9.0

static func strike(battle: State, attacker: Unit, target: Unit, rng: RandomNumberGenerator, damage_scale: float = 1.0) -> int:
	var incoming: float = (attacker.position - target.position).angle()
	var rear := absf(wrapf(incoming - target.facing, -PI, PI)) > Config.REAR_ANGLE
	var base := attacker.damage
	if attacker.attack_range > 0.0:
		base = attacker.ranged_melee_damage if attacker.ranged_melee_damage > 0.0 else base * Config.RANGED_MELEE_DAMAGE_MULTIPLIER
	var raw: float = base * damage_scale * rng.randf_range(Config.MELEE_DAMAGE_MIN, Config.MELEE_DAMAGE_MAX)
	if not rear and Block.check(target, incoming, false, rng):
		battle.record_event(Event.Kind.BLOCK, target, attacker, Event.Attack.MELEE, 0, Vector2.from_angle(incoming) * MELEE_BLOCK_CONTACT)
		return 0
	if rear:
		raw *= Config.REAR_DAMAGE_MULTIPLIER
	if attacker.wavering:
		raw *= Config.MORALE_WAVER_DAMAGE_MULTIPLIER
	if attacker.anti_cavalry and target.mounted:
		raw *= Config.ANTI_CAVALRY_MULTIPLIER
	if attacker.damage_type == EquipmentConfig.DAMAGE_TYPE_BLUNT or (attacker.damage_type.is_empty() and attacker.blunt_melee):
		raw *= target.blunt_melee_damage_multiplier
	if attacker.damage_type.is_empty():
		return battle.hurt(target, raw, attacker, 0.0, rng, Event.Attack.MELEE)
	return battle.hurt(target, raw * DamageType.multiplier(attacker.damage_type, target.armor), attacker, DamageType.pierce(attacker.damage_type, target.armor, attacker.pierce), rng, Event.Attack.MELEE)

static func hero_strike(battle: State, hero: Unit, target: Unit, previous_hits: int, rng: RandomNumberGenerator) -> int:
	var weapon: Dictionary = hero.hero_weapon
	var bonus_pierce: float = float(hero.perk_effects.get("mpierce", 0.0))
	var direction: float = (target.position - hero.position).angle()
	var incoming: float = (hero.position - target.position).angle()
	var rear := absf(wrapf(incoming - target.facing, -PI, PI)) > Config.REAR_ANGLE
	if not rear and Block.check(target, incoming, false, rng) and rng.randf() < Config.HERO_BLOCK_HOLD_CHANCE - float(weapon.get("brk", 0.0)):
		battle.record_event(Event.Kind.BLOCK, target, hero, Event.Attack.MELEE, 0, -Vector2.from_angle(direction) * HERO_BLOCK_CONTACT)
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
		raw *= target.blunt_melee_damage_multiplier
	if hero.damage_type.is_empty():
		return battle.hurt(target, raw, hero, Config.HERO_UNARMED_PIERCE + bonus_pierce, rng, Event.Attack.MELEE)
	return battle.hurt(target, raw * DamageType.multiplier(hero.damage_type, target.armor), hero, DamageType.pierce(hero.damage_type, target.armor, hero.pierce + bonus_pierce), rng, Event.Attack.MELEE)

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
	return {"side": attacker.side, "source": attacker, "origin": attacker.position - Vector2(0.0, Config.PROJECTILE_START_HEIGHT), "impact": impact, "damage": attacker.damage * (Config.MORALE_WAVER_DAMAGE_MULTIPLIER if attacker.wavering else 1.0), "pierce": attacker.pierce, "damage_type": attacker.damage_type, "throwing": attacker.weapon_kind == Config.PROJECTILE_THROW_WEAPON, "crossbow": attacker.weapon_kind == Config.PROJECTILE_CROSSBOW_WEAPON, "time": 0.0, "duration": duration}

static func arrow_hit(battle: State, shot: Dictionary, target: Unit, rng: RandomNumberGenerator) -> int:
	var incoming: float = (shot.origin - target.position).angle()
	if Block.check(target, incoming, true, rng):
		battle.record_event(Event.Kind.BLOCK, target, shot.source, Event.Attack.PROJECTILE, 0, Vector2(cos(incoming) * PROJECTILE_BLOCK_CONTACT_X, 0))
		return 0
	var raw: float = shot.damage * rng.randf_range(Config.ARROW_DAMAGE_MIN, Config.ARROW_DAMAGE_MAX)
	if battle.wall != null:
		raw *= battle.wall.projectile_multiplier(target, shot.origin, battle.siege_skill)
	raw *= target.projectile_damage_multiplier
	var kind: String = shot.get("damage_type", "")
	if kind.is_empty():
		return battle.hurt(target, raw, shot.source, shot.pierce, rng, Event.Attack.PROJECTILE)
	return battle.hurt(target, raw * DamageType.multiplier(kind, target.armor), shot.source, DamageType.pierce(kind, target.armor, shot.pierce), rng, Event.Attack.PROJECTILE)
