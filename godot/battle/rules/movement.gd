extends RefCounted
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Group = preload("res://battle/model/group.gd")
const Targeting = preload("res://battle/rules/targeting.gd")
const SpatialIndex = preload("res://battle/rules/spatial_index.gd")
const Charge = preload("res://battle/rules/charge.gd")
const AiDecision = preload("res://battle/rules/ai_decision.gd")
const CombatStep = preload("res://battle/rules/combat_step.gd")
const CollisionGrid = preload("res://battle/rules/collision_grid.gd")

const COLLISION_SLACK := 10.0

static func step(battle: State, dt: float, rng: RandomNumberGenerator) -> void:
	assert(rng != null, "A simulation tick requires the battle RNG")
	_step(battle, dt, rng)

## Isolates formation movement and collisions for comparison with the pre-index fixture.
static func step_formation_only(battle: State, dt: float) -> SpatialIndex:
	return _step(battle, dt, null, true)

static func _step(battle: State, dt: float, rng: RandomNumberGenerator, keep_index := false) -> SpatialIndex:
	if dt <= 0.0:
		return null
	var index: SpatialIndex = null
	if battle.use_spatial_index and battle.units.size() >= Config.SPATIAL_MIN_UNITS:
		if battle.movement_index == null:
			battle.movement_index = SpatialIndex.new(battle.units, battle.arena_size)
		else:
			battle.movement_index.synchronize()
		index = battle.movement_index
	battle.profiler.mark("movement_index")
	for unit_index in battle.units.size():
		var unit: Unit = battle.units[unit_index]
		if unit.dead or unit.gone or unit.hero:
			continue
		unit.charge_cooldown -= dt
		if rng != null:
			unit.attack_cooldown -= dt
		var group: Group = battle.groups[unit.side][unit.group_kind]
		var destination: Vector2 = group.slot_position(unit, battle.arena_size)
		var velocity_scale := 1.0
		var ai_face := unit.facing
		var target: Unit = null
		var target_distance := INF
		if unit.fleeing:
			destination = Vector2(battle.arena_size.x + Config.FLEE_DESTINATION_PADDING if unit.side == 1 else -Config.FLEE_DESTINATION_PADDING, unit.position.y)
			velocity_scale = Config.FLEE_SPEED_MULTIPLIER
		elif rng != null:
			target = Targeting.refresh(battle, unit, dt, rng, index)
			AiDecision.plan_into(unit, group, target, battle.arena_size, destination)
			destination = unit.plan_destination
			velocity_scale = unit.plan_speed
			ai_face = unit.plan_face
			target_distance = unit.plan_distance
			if unit.ai_mode == Config.AI_MODE_MELEE and target != null and Charge.can_hit(unit, target):
				unit.facing = ai_face
				Charge.hit(battle, unit, target, rng)
				if destination != unit.position:
					destination = target.position
				if index != null:
					index.update(target.battle_index)
		elif group.order == Config.ORDER_CHARGE:
			var enemy: Unit = Targeting.nearest_enemy(battle, unit, index)
			if enemy != null:
				destination = enemy.position
		if battle.wall != null:
			destination = battle.wall.route(unit, destination)
		_steer(unit, destination, unit.speed * velocity_scale, dt)
		if unit.fleeing:
			unit.facing = unit.velocity.angle()
			if unit.position.x < -Config.FLEE_EXIT_PADDING or unit.position.x > battle.arena_size.x + Config.FLEE_EXIT_PADDING:
				unit.gone = true
		elif rng != null:
			unit.facing = ai_face
			CombatStep.advance_unit(battle, unit, target, target_distance, dt, rng)
		unit.position += unit.velocity * dt
		if index != null:
			index.update(unit_index)
	battle.profiler.mark("ai_movement_combat")
	_resolve_unit_collisions(battle, index, keep_index)
	battle.profiler.mark("contacts")
	return index

static func _steer(unit: Unit, destination: Vector2, speed: float, dt: float) -> void:
	var delta: Vector2 = destination - unit.position
	var distance := delta.length()
	var desired := Vector2.ZERO
	if distance > Config.ARRIVAL_DISTANCE and speed > 0.0:
		desired = delta / distance * minf(speed, distance * Config.ARRIVAL_BRAKE)
	var rate := Config.HORSE_STEERING_RATE if unit.mounted else Config.FOOT_STEERING_RATE
	unit.velocity = unit.velocity.lerp(desired, minf(1.0, rate * dt))
	if unit.velocity.length_squared() > 0.0:
		unit.facing = unit.velocity.angle()

static func _resolve_unit_collisions(battle: State, index: SpatialIndex, keep_index := true) -> void:
	if index != null:
		_resolve_packed(battle, index if keep_index else null)
		return
	for i in battle.units.size():
		var a: Unit = battle.units[i]
		if a.dead or a.gone:
			continue
		for j in range(i + 1, battle.units.size()):
			_separate(a, battle.units[j])
		_finish_unit(a, battle)

## The plain pair loop above, run over packed copies: same pair order, same Vector2 arithmetic, same results.
## Candidates come from a fine grid gathered with some slack, so a's small pushes do not force a new query.
static func _resolve_packed(battle: State, index: SpatialIndex) -> void: # index: kept current for callers that reuse it, else null
	var units := battle.units
	var n := units.size()
	var pos := PackedVector2Array()
	var rad := PackedFloat64Array()
	var mass := PackedFloat64Array()
	var side := PackedInt32Array()
	var live := PackedByteArray()
	pos.resize(n)
	rad.resize(n)
	mass.resize(n)
	side.resize(n)
	live.resize(n)
	var max_radius := 0.0
	for i in n:
		var u: Unit = units[i]
		pos[i] = u.position
		rad[i] = u.collision_radius
		mass[i] = u.mass
		side[i] = u.side
		live[i] = 0 if u.dead or u.gone else 1
		max_radius = maxf(max_radius, u.collision_radius)
	if battle.collision_grid == null:
		battle.collision_grid = CollisionGrid.new(pos, battle.arena_size)
	else:
		battle.collision_grid.reset(pos, battle.arena_size)
	var grid := battle.collision_grid
	var plain_field := battle.wall == null
	var trunk_count := battle.trunks.size()
	var trunk_pos := PackedVector2Array()
	var trunk_rad := PackedFloat64Array()
	for trunk in battle.trunks:
		trunk_pos.append(trunk.position)
		trunk_rad.append(trunk.trunk_radius)
	var slack2 := COLLISION_SLACK * COLLISION_SLACK
	for i in n:
		if live[i] == 0:
			continue
		var pa: Vector2 = pos[i]
		var ra: float = rad[i]
		var ma: float = mass[i]
		var sa: int = side[i]
		var next_index := i + 1
		while next_index < n:
			var origin := pa
			var candidates := battle.collision_candidates
			grid.query_into(origin, ra + max_radius + COLLISION_SLACK, next_index, candidates)
			var moved_far := false
			for j in candidates:
				next_index = j + 1
				if live[j] == 0:
					continue
				var pb: Vector2 = pos[j]
				var difference: Vector2 = pb - pa
				var radius: float = ra + rad[j]
				if absf(difference.x) >= radius or absf(difference.y) >= radius or difference.length_squared() >= radius * radius:
					continue
				var distance := maxf(difference.length(), Config.MIN_COLLISION_DISTANCE)
				var normal := difference / distance
				var strength := Config.FRIEND_COLLISION_PUSH if sa == side[j] else Config.ENEMY_COLLISION_PUSH
				var overlap := (radius - distance) * strength
				var mb: float = mass[j]
				var total_mass: float = ma + mb
				pa -= normal * overlap * mb / total_mass
				pb += normal * overlap * ma / total_mass
				pos[j] = pb
				grid.move(j, pb)
				if pa.distance_squared_to(origin) > slack2:
					moved_far = true
					break
			if not moved_far:
				break
		var a: Unit = units[i]
		if plain_field:
			# _finish_unit without a wall, on the packed value: trunks, then the field clamp.
			for t in trunk_count:
				var reach: float = ra + trunk_rad[t]
				var offset: Vector2 = pa - trunk_pos[t]
				var distance_squared := offset.length_squared()
				if distance_squared >= reach * reach:
					continue
				var normal := Vector2.RIGHT if distance_squared == 0.0 else offset / sqrt(distance_squared)
				pa = trunk_pos[t] + normal * reach
			if not a.fleeing:
				pa.x = clampf(pa.x, Config.FIELD_LEFT_RIGHT_MARGIN, battle.arena_size.x - Config.FIELD_LEFT_RIGHT_MARGIN)
			pa.y = clampf(pa.y, Config.FIELD_TOP_MARGIN, battle.arena_size.y - Config.FIELD_BOTTOM_MARGIN)
			a.position = pa
		else:
			a.position = pa
			_finish_unit(a, battle)
			pa = a.position
		pos[i] = pa
		grid.move(i, pa)
		if index != null:
			index.update(i)
	# Units after i that were pushed get their final position at their own turn; dead ones never move.

static func _finish_unit(a: Unit, battle: State) -> void:
	if battle.wall != null:
		battle.wall.constrain(a)
	_resolve_trunk_collisions(a, battle)
	# Browser battleUpdate clamps after pair collisions and terrain contacts.
	if not a.fleeing:
		a.position.x = clampf(a.position.x, Config.FIELD_LEFT_RIGHT_MARGIN, battle.arena_size.x - Config.FIELD_LEFT_RIGHT_MARGIN)
	a.position.y = clampf(a.position.y, Config.FIELD_TOP_MARGIN, battle.arena_size.y - Config.FIELD_BOTTOM_MARGIN)

static func _resolve_trunk_collisions(unit: Unit, battle: State) -> void:
	for trunk in battle.trunks:
		var reach: float = unit.collision_radius + trunk.trunk_radius
		var offset: Vector2 = unit.position - trunk.position
		var distance_squared := offset.length_squared()
		if distance_squared >= reach * reach:
			continue
		# A unit exactly on the center needs a stable outward direction.
		var normal := Vector2.RIGHT if distance_squared == 0.0 else offset / sqrt(distance_squared)
		unit.position = trunk.position + normal * reach

static func _separate(a: Unit, b: Unit) -> bool:
	if b.dead or b.gone:
		return false
	var difference: Vector2 = b.position - a.position
	var radius: float = a.collision_radius + b.collision_radius
	if absf(difference.x) >= radius or absf(difference.y) >= radius or difference.length_squared() >= radius * radius:
		return false
	var distance := maxf(difference.length(), Config.MIN_COLLISION_DISTANCE)
	var normal := difference / distance
	var strength := Config.FRIEND_COLLISION_PUSH if a.side == b.side else Config.ENEMY_COLLISION_PUSH
	var overlap := (radius - distance) * strength
	var total_mass: float = a.mass + b.mass
	a.position -= normal * overlap * b.mass / total_mass
	b.position += normal * overlap * a.mass / total_mass
	return true
