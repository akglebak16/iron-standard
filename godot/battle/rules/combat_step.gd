extends RefCounted
const Config = preload("res://battle/config.gd")
const Event = preload("res://battle/combat_event.gd")
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
		var distance := unit.position.distance_to(target.position) if target != null else INF
		advance_unit(battle, unit, target, distance, dt, rng)
	resolve_projectiles(battle, dt, rng)

## Called by Movement after steering and before changing this unit's position.
## The standalone step() above keeps rule-level tests able to exercise attacks without movement.
static func advance_unit(battle: State, unit: Unit, target: Unit, distance: float, dt: float, rng: RandomNumberGenerator) -> void:
	if unit.dead or unit.gone or unit.fleeing or unit.hero:
		return
	if target != null and unit.attack_cooldown <= 0.0:
		if unit.ai_mode == Config.AI_MODE_UNASSIGNED:
			# Existing test-only units have no AI plan; preserve their old direct attack path.
			if unit.attack_range > 0.0 and distance <= unit.attack_range and unit.velocity.length() < Config.SHOOT_MOVE_SPEED_LIMIT:
				battle.launch_projectile(Combat.shoot(unit, target, rng))
				unit.attack_cooldown = unit.attack_interval
			elif distance <= unit.collision_radius + target.collision_radius + unit.melee_reach:
				Combat.strike(battle, unit, target, rng)
				unit.attack_cooldown = unit.attack_interval
		elif unit.ai_mode == Config.AI_MODE_MELEE and distance <= unit.collision_radius + target.collision_radius + unit.melee_reach and unit.ai_windup < 0.0:
			unit.ai_windup = Config.AI_MELEE_WINDUP_SECONDS
			unit.ai_wind_target_index = target.battle_index
			unit.attack_cooldown = unit.attack_interval * rng.randf_range(Config.AI_MELEE_COOLDOWN_MIN, Config.AI_MELEE_COOLDOWN_MAX)
		elif _can_shoot(unit, distance):
			battle.launch_projectile(Combat.shoot(unit, target, rng))
			unit.attack_cooldown = unit.attack_interval * rng.randf_range(Config.AI_SHOOT_COOLDOWN_MIN, Config.AI_SHOOT_COOLDOWN_MAX)
	if unit.ai_mode != Config.AI_MODE_UNASSIGNED:
		_advance_wind(battle, unit, dt, rng)

static func resolve_projectiles(battle: State, dt: float, rng: RandomNumberGenerator, use_spatial: bool = true) -> void:
	if dt <= 0.0:
		return
	# Build only when a projectile actually lands, after movement/contact corrections.
	# Reusing the pre-movement target grid would miss units pushed across cell boundaries.
	var index: SpatialIndex = null
	var hit_radius := Config.PROJECTILE_HIT_PADDING
	if use_spatial and battle.units.size() >= Config.SPATIAL_MIN_UNITS:
		for shot in battle.projectiles:
			if shot.time + dt >= shot.duration:
				index = SpatialIndex.new(battle.units, battle.arena_size)
				for unit in battle.units: hit_radius = maxf(hit_radius, unit.collision_radius + Config.PROJECTILE_HIT_PADDING)
				break
	for i in range(battle.projectiles.size() - 1, -1, -1):
		var shot: Dictionary = battle.projectiles[i]
		shot.time += dt
		if shot.time < shot.duration:
			continue
		battle.projectiles.remove_at(i)
		var victim: Unit = null
		var closest := INF
		var candidates: Array[int] = []
		if index != null:
			candidates = index.nearby(shot.impact + Vector2(0.0, Config.PROJECTILE_HIT_HEIGHT), hit_radius, 0)
		if index == null:
			for unit_index in battle.units.size(): candidates.append(unit_index)
		for unit_index in candidates:
			var unit: Unit = battle.units[unit_index]
			if unit.side == shot.side or unit.dead or unit.gone:
				continue
			var distance: float = (unit.position - Vector2(0.0, Config.PROJECTILE_HIT_HEIGHT)).distance_to(shot.impact)
			if distance < unit.collision_radius + Config.PROJECTILE_HIT_PADDING and distance < closest:
				victim = unit
				closest = distance
		if victim != null:
			Combat.arrow_hit(battle, shot, victim, rng)
		else:
			battle.record_notice(Event.Kind.PROJECTILE_MISSED, {
				"position": shot.impact, "trajectory": shot.impact - shot.origin, "throwing": shot.get("throwing", false),
			})

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
	if unit.ai_wind_target_index >= 0 and unit.ai_wind_target_index < battle.units.size():
		var target: Unit = battle.units[unit.ai_wind_target_index]
		if not target.dead and not target.gone and unit.position.distance_to(target.position) < unit.collision_radius + target.collision_radius + unit.melee_reach + Config.AI_WIND_HIT_EXTRA_REACH:
			Combat.strike(battle, unit, target, rng)
	unit.ai_wind_target_index = -1
