extends RefCounted

const Config = preload("res://battle/config.gd")

static func strike(battle: RefCounted, attacker: RefCounted, target: RefCounted, rng: RandomNumberGenerator) -> int:
	var incoming: float = (attacker.position - target.position).angle()
	var rear := absf(wrapf(incoming - target.facing, -PI, PI)) > Config.REAR_ANGLE
	if not rear and _blocked(target, incoming, rng):
		return 0
	var raw: float = attacker.damage * rng.randf_range(Config.MELEE_DAMAGE_MIN, Config.MELEE_DAMAGE_MAX)
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

static func shoot(attacker: RefCounted, target: RefCounted, rng: RandomNumberGenerator) -> Dictionary:
	var distance: float = attacker.position.distance_to(target.position)
	var speed: float = Config.THROW_SPEED if attacker.weapon_kind == "javelin" else Config.SHOT_SPEED
	var duration: float = distance / speed + Config.PROJECTILE_START_DELAY
	var spread: float = Config.SHOT_BASE_SCATTER + distance * attacker.accuracy
	var impact: Vector2 = target.position + target.velocity * duration * Config.AIM_VELOCITY_LEAD
	impact += Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
	return {"side": attacker.side, "source": attacker, "impact": impact, "damage": attacker.damage, "pierce": attacker.pierce, "time": 0.0, "duration": duration}

static func arrow_hit(battle: RefCounted, shot: Dictionary, target: RefCounted, rng: RandomNumberGenerator) -> int:
	var incoming: float = (shot.source.position - target.position).angle()
	if _blocked(target, incoming, rng):
		return 0
	var raw: float = shot.damage * rng.randf_range(Config.ARROW_DAMAGE_MIN, Config.ARROW_DAMAGE_MAX)
	if target.undead_kind == "skel":
		raw *= Config.SKELETON_ARROW_MULTIPLIER
	return battle.hurt(target, raw, shot.source, shot.pierce)

static func _blocked(target: RefCounted, incoming: float, rng: RandomNumberGenerator) -> bool:
	var chance: float = target.block_chance
	if target.hero:
		chance = minf(Config.HERO_MAX_BLOCK_CHANCE, chance + Config.HERO_ACTIVE_BLOCK_BONUS) if target.blocking else chance * Config.HERO_IDLE_BLOCK_MULTIPLIER
	return absf(wrapf(incoming - target.facing, -PI, PI)) <= Config.BLOCK_ARC and rng.randf() < chance
