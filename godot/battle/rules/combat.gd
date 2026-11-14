extends RefCounted
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")

const Config = preload("res://battle/config.gd")
const Block = preload("res://battle/rules/block.gd")

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
	if attacker.weapon_kind in ["club", "mace"]:
		if target.undead_kind == "skel":
			raw *= Config.SKELETON_BLUNT_MULTIPLIER
		elif target.undead_kind == "zombie":
			raw *= Config.ZOMBIE_BLUNT_MULTIPLIER
	return battle.hurt(target, raw, attacker)

static func shoot(attacker: Unit, target: Unit, rng: RandomNumberGenerator) -> Dictionary:
	var distance: float = attacker.position.distance_to(target.position)
	var is_throw := attacker.weapon_kind == Config.PROJECTILE_THROW_WEAPON
	var speed: float = Config.THROW_SPEED if is_throw else Config.SHOT_SPEED
	var duration: float = distance / speed + Config.PROJECTILE_START_DELAY
	var spread: float = Config.SHOT_BASE_SCATTER + distance * attacker.accuracy
	var impact: Vector2 = target.position + target.velocity * duration * Config.AIM_VELOCITY_LEAD
	impact += Vector2((rng.randf() + rng.randf() - 1.0) * spread, (rng.randf() + rng.randf() - 1.0) * spread)
	return {"side": attacker.side, "source": attacker, "origin": attacker.position - Vector2(0.0, Config.PROJECTILE_START_HEIGHT), "impact": impact, "damage": attacker.damage, "pierce": attacker.pierce, "throwing": is_throw, "crossbow": attacker.weapon_kind == Config.PROJECTILE_CROSSBOW_WEAPON, "time": 0.0, "duration": duration}

static func arrow_hit(battle: State, shot: Dictionary, target: Unit, rng: RandomNumberGenerator) -> int:
	var incoming: float = (shot.origin - target.position).angle()
	if Block.check(target, incoming, true, rng):
		return 0
	var raw: float = shot.damage * rng.randf_range(Config.ARROW_DAMAGE_MIN, Config.ARROW_DAMAGE_MAX)
	if target.undead_kind == "skel":
		raw *= Config.SKELETON_ARROW_MULTIPLIER
	return battle.hurt(target, raw, shot.source, shot.pierce)
