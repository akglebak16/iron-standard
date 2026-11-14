extends RefCounted
## Port of src/03_battle.js chargeHit(), called from the melee movement mode.
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Block = preload("res://battle/rules/block.gd")

static func can_hit(attacker: Unit, target: Unit) -> bool:
	if not attacker.mounted or attacker.attack_range > 0.0 or attacker.charge_cooldown > 0.0 or attacker.velocity.length() <= Config.CHARGE_MIN_SPEED:
		return false
	if target == null or target.side == attacker.side or target.dead or target.gone:
		return false
	return attacker.position.distance_to(target.position) < attacker.collision_radius + target.collision_radius + attacker.melee_reach + Config.CHARGE_EXTRA_REACH

static func hit(battle: State, attacker: Unit, target: Unit, rng: RandomNumberGenerator) -> int:
	var speed := attacker.velocity.length()
	attacker.charge_cooldown = Config.CHARGE_COOLDOWN
	var damage: float = attacker.damage * (Config.CHARGE_BASE_DAMAGE + speed / Config.CHARGE_SPEED_DAMAGE_DIVISOR)
	var incoming := (attacker.position - target.position).angle()
	var front := absf(wrapf(incoming - target.facing, -PI, PI)) < Config.CHARGE_FRONT_ARC
	if target.anti_cavalry and front and not target.fleeing:
		damage *= Config.CHARGE_ANTI_DAMAGE_MULTIPLIER
		battle.hurt(attacker, Config.CHARGE_COUNTER_DAMAGE * rng.randf_range(Config.CHARGE_COUNTER_RANDOM_MIN, Config.CHARGE_COUNTER_RANDOM_MAX), target)
	elif front and Block.check(target, incoming, false, rng):
		damage *= Config.CHARGE_BLOCK_DAMAGE_MULTIPLIER
	target.position -= Vector2(cos(incoming), sin(incoming)) * (Config.CHARGE_KNOCKBACK / target.mass)
	attacker.velocity *= Config.CHARGE_ATTACKER_VELOCITY_MULTIPLIER
	attacker.attack_cooldown = maxf(attacker.attack_cooldown, Config.CHARGE_ATTACK_COOLDOWN)
	return battle.hurt(target, damage, attacker) if not target.dead and not target.gone else 0
