## Frozen pre-index traversal for differential tests. Projectile rule follows current parity.
extends RefCounted
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Combat = preload("res://core/battle/rules/combat.gd")
const Targeting = preload("res://core/battle/rules/targeting.gd")

static func step(battle: State, dt: float, rng: RandomNumberGenerator) -> void:
	if dt <= 0.0:
		return
	for unit: Unit in battle.units:
		if unit.dead or unit.gone or unit.fleeing or unit.hero:
			continue
		unit.attack_cooldown -= dt
		if unit.attack_cooldown > 0.0:
			continue
		var target: Unit = Targeting.nearest_enemy(battle, unit)
		if target == null:
			continue
		var distance: float = unit.position.distance_to(target.position)
		if unit.attack_range > 0.0 and distance <= unit.attack_range and unit.velocity.length() < Config.SHOOT_MOVE_SPEED_LIMIT:
			battle.projectiles.append(Combat.shoot(unit, target, rng))
			unit.attack_cooldown = unit.attack_interval
		elif distance <= unit.collision_radius + target.collision_radius + unit.melee_reach:
			Combat.strike(battle, unit, target, rng)
			unit.attack_cooldown = unit.attack_interval
	for i in range(battle.projectiles.size() - 1, -1, -1):
		var shot: Dictionary = battle.projectiles[i]
		shot.time += dt
		if shot.time < shot.duration:
			continue
		battle.projectiles.remove_at(i)
		var victim: Unit = null
		var closest := INF
		for unit: Unit in battle.units:
			if unit.side == shot.side or unit.dead or unit.gone:
				continue
			var distance: float = (unit.position - Vector2(0.0, Config.PROJECTILE_HIT_HEIGHT)).distance_to(shot.impact)
			if distance < unit.collision_radius + Config.PROJECTILE_HIT_PADDING and distance < closest:
				victim = unit
				closest = distance
		if victim != null:
			Combat.arrow_hit(battle, shot, victim, rng)
