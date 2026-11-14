extends RefCounted
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Combat = preload("res://battle/rules/combat.gd")
const Targeting = preload("res://battle/rules/targeting.gd")
const SpatialIndex = preload("res://battle/rules/spatial_index.gd")

static func step(battle: State, dt: float, rng: RandomNumberGenerator, index: SpatialIndex = null) -> void:
	if dt <= 0.0:
		return
	if index == null and battle.units.size() >= Config.SPATIAL_MIN_UNITS:
		index = SpatialIndex.new(battle.units)
	for unit: Unit in battle.units:
		if unit.dead or unit.gone or unit.fleeing or unit.hero:
			continue
		unit.attack_cooldown -= dt
		var target: Unit = Targeting.current(battle, unit) if unit.ai_mode != Config.AI_MODE_UNASSIGNED else Targeting.nearest_enemy(battle, unit, index)
		advance_unit(battle, unit, target, dt, rng)
	resolve_projectiles(battle, dt, rng)

## Called by Movement after steering and before changing this unit's position.
## The standalone step() above keeps rule-level tests able to exercise attacks without movement.
static func advance_unit(battle: State, unit: Unit, target: Unit, dt: float, rng: RandomNumberGenerator) -> void:
	if unit.dead or unit.gone or unit.fleeing or unit.hero:
		return
	if target != null and unit.attack_cooldown <= 0.0:
		var distance: float = unit.position.distance_to(target.position)
		if unit.ai_mode == Config.AI_MODE_UNASSIGNED:
			# Existing test-only units have no AI plan; preserve their old direct attack path.
			if unit.attack_range > 0.0 and distance <= unit.attack_range and unit.velocity.length() < Config.SHOOT_MOVE_SPEED_LIMIT:
				battle.projectiles.append(Combat.shoot(unit, target, rng))
				unit.attack_cooldown = unit.attack_interval
			elif distance <= unit.collision_radius + target.collision_radius + unit.melee_reach:
				Combat.strike(battle, unit, target, rng)
				unit.attack_cooldown = unit.attack_interval
		elif unit.ai_mode == Config.AI_MODE_MELEE and distance <= unit.collision_radius + target.collision_radius + unit.melee_reach and unit.ai_windup < 0.0:
			unit.ai_windup = Config.AI_MELEE_WINDUP_SECONDS
			unit.ai_wind_target_id = battle.units.find(target)
			unit.attack_cooldown = unit.attack_interval * rng.randf_range(Config.AI_MELEE_COOLDOWN_MIN, Config.AI_MELEE_COOLDOWN_MAX)
		elif _can_shoot(unit, distance):
			battle.projectiles.append(Combat.shoot(unit, target, rng))
			unit.attack_cooldown = unit.attack_interval * rng.randf_range(Config.AI_SHOOT_COOLDOWN_MIN, Config.AI_SHOOT_COOLDOWN_MAX)
	if unit.ai_mode != Config.AI_MODE_UNASSIGNED:
		_advance_wind(battle, unit, dt, rng)

static func resolve_projectiles(battle: State, dt: float, rng: RandomNumberGenerator) -> void:
	if dt <= 0.0:
		return
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

static func _can_shoot(unit: Unit, distance: float) -> bool:
	if unit.attack_range <= 0.0 or distance >= unit.attack_range:
		return false
	if unit.ai_mode == Config.AI_MODE_SKIRMISH:
		return true
	return (unit.ai_mode == Config.AI_MODE_SHOOT or unit.ai_mode == Config.AI_MODE_SHOOT_SLOT) and unit.velocity.length() < Config.SHOOT_MOVE_SPEED_LIMIT

static func _advance_wind(battle: State, unit: Unit, dt: float, rng: RandomNumberGenerator) -> void:
	if unit.ai_windup < 0.0:
		return
	unit.ai_windup -= dt
	if unit.ai_windup >= 0.0:
		return
	if unit.ai_wind_target_id >= 0 and unit.ai_wind_target_id < battle.units.size():
		var target: Unit = battle.units[unit.ai_wind_target_id]
		if not target.dead and not target.gone and unit.position.distance_to(target.position) < unit.collision_radius + target.collision_radius + unit.melee_reach + Config.AI_WIND_HIT_EXTRA_REACH:
			Combat.strike(battle, unit, target, rng)
	unit.ai_wind_target_id = -1
