extends RefCounted
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Group = preload("res://core/battle/model/group.gd")
const Targeting = preload("res://core/battle/rules/targeting.gd")
const SpatialIndex = preload("res://core/battle/rules/spatial_index.gd")
const Charge = preload("res://core/battle/rules/charge.gd")
const AiDecision = preload("res://core/battle/rules/ai_decision.gd")
const CombatStep = preload("res://core/battle/rules/combat_step.gd")
const CollisionGrid = preload("res://core/battle/rules/collision_grid.gd")
const TerrainRules = preload("res://core/battle/rules/terrain_rules.gd")

const COLLISION_SLACK := Config.CONTACT_QUERY_SLACK

static func step(battle: State, dt: float, rng: RandomNumberGenerator) -> void:
	assert(rng != null, "A simulation tick requires the battle RNG")
	if battle.movement_solver.is_valid() and dt > 0.0:
		_step_batch(battle, dt, rng)
	else:
		_step(battle, dt, rng)

## Isolates formation movement and collisions for comparison with the pre-index fixture.
static func step_formation_only(battle: State, dt: float) -> SpatialIndex:
	return _step(battle, dt, null, true)

static func _step(battle: State, dt: float, rng: RandomNumberGenerator, keep_index := false) -> SpatialIndex:
	if dt <= 0.0:
		return null
	var index: SpatialIndex = null
	if battle.use_spatial_index and battle.active_units.size() >= Config.SPATIAL_MIN_UNITS:
		if battle.movement_index == null:
			battle.movement_index = SpatialIndex.new(battle.active_units, battle.arena_size, battle.motion)
		else:
			battle.movement_index.synchronize()
		index = battle.movement_index
		index.terrain = battle.terrain_rules
	if rng != null:
		_prepare_ai(battle)
	battle.profiler.mark("movement_index")
	var positions := battle.motion.positions
	var velocities := battle.motion.velocities
	var wall_x: float = battle.wall.x if battle.wall != null else INF
	var terrain = battle.terrain_rules # TERRAIN.md 4.4 (stage Р1а): null on an open, flat field.
	for unit_index in battle.active_units.size():
		var unit: Unit = battle.active_units[unit_index]
		if unit.dead or unit.gone or unit.hero:
			continue
		var sampled := battle.profiler.detailed and battle.profiler.clock.is_valid() and unit_index % 32 == battle.profiler.sample_lane
		var probe := int(battle.profiler.clock.call()) if sampled else 0
		unit.charge_cooldown -= dt
		if rng != null:
			unit.attack_cooldown -= dt
		var group: Group = battle.groups[unit.side][unit.group_kind]
		var destination: Vector2 = group.slot_position(unit, battle.arena_size)
		var velocity_scale := 1.0
		var ai_face := unit.facing
		var target: Unit = null
		var target_distance := INF
		if sampled: probe = battle.profiler.probe("sample_slot", probe)
		if unit.fleeing:
			destination = Vector2(battle.arena_size.x + Config.FLEE_DESTINATION_PADDING if unit.side == 1 else -Config.FLEE_DESTINATION_PADDING, unit.position.y)
			velocity_scale = Config.FLEE_SPEED_MULTIPLIER
		elif rng != null:
			target = Targeting.refresh(battle, unit, dt, rng, index)
			if sampled: probe = battle.profiler.probe("sample_target", probe)
			var range_scale := TerrainRules.range_scale(terrain, unit.position, target.position) if terrain != null and target != null and unit.attack_range > 0.0 else 1.0
			AiDecision.plan_into(unit, group, target, battle.arena_size, destination, battle.formation_centers[unit.side * 3 + unit.group_kind], dt, battle.formation_centers[unit.side * 3 + Config.GROUP_INFANTRY], wall_x, range_scale)
			if sampled: probe = battle.profiler.probe("sample_plan", probe)
			destination = unit.plan_destination
			velocity_scale = unit.plan_speed
			ai_face = unit.plan_face
			target_distance = unit.plan_distance
			if unit.ai_mode == Config.AI_MODE_MELEE and target != null and Charge.can_hit(unit, target, terrain):
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
		if sampled: probe = battle.profiler.probe("sample_charge_route", probe)
		velocities[unit_index] = _steer(unit, positions[unit_index], velocities[unit_index], destination, unit.speed * velocity_scale, dt, terrain)
		if sampled: probe = battle.profiler.probe("sample_steer", probe)
		if unit.fleeing:
			unit.facing = unit.velocity.angle()
			if unit.position.x < -Config.FLEE_EXIT_PADDING or unit.position.x > battle.arena_size.x + Config.FLEE_EXIT_PADDING:
				battle.mark_gone(unit)
		elif rng != null:
			unit.facing = ai_face
			CombatStep.advance_unit(battle, unit, target, target_distance, dt, rng)
		if sampled: probe = battle.profiler.probe("sample_attack", probe)
		positions[unit_index] += velocities[unit_index] * dt
		if index != null:
			index.update(unit_index)
		if sampled: battle.profiler.probe("sample_integrate_index", probe)
	battle.profiler.mark("ai_movement_combat")
	_resolve_unit_collisions(battle, index, keep_index)
	battle.profiler.mark("contacts")
	return index

## Stage 1a inputs, once per tick before any fighter moves; begin() in movement_kernel.hpp computes the same:
## the melee attackers and the shooters (aimers, stage 1a-archers) of every target, and for every group the formation centre that fits its ready fighters
## (the mean of position minus formation offset, summed in double precision in row order).
static func _prepare_ai(battle: State) -> void:
	var motion = battle.motion
	var capacity: int = motion.capacity
	var fields = motion.I
	var flags: PackedInt64Array = motion.integer_fields
	var reals: PackedFloat64Array = motion.real_fields
	var vectors: PackedVector2Array = motion.vector_fields
	var positions: PackedVector2Array = motion.positions
	var count := battle.active_units.size()
	var attackers: int = fields.ATTACKERS * capacity
	var aimers: int = fields.AIMERS * capacity
	for row in count:
		flags[attackers + row] = 0
		flags[aimers + row] = 0
	var sums := PackedFloat64Array()
	sums.resize(12)
	var counts := PackedInt32Array()
	counts.resize(6)
	for row in count:
		if flags[fields.DEAD * capacity + row] or flags[fields.GONE * capacity + row] or flags[fields.HERO * capacity + row] or flags[fields.FLEEING * capacity + row]:
			continue
		var side: int = flags[fields.SIDE * capacity + row]
		var slot: int = side * 3 + flags[fields.GROUP_KIND * capacity + row]
		var group: Group = battle.groups[side][slot - side * 3]
		var fitted := group.implied_center(vectors[motion.V.SLOT_OFFSET * capacity + row], positions[row])
		sums[slot * 2] += fitted.x
		sums[slot * 2 + 1] += fitted.y
		counts[slot] += 1
		var target := battle.unit_for(flags[fields.TARGET_HANDLE * capacity + row])
		if target != null and target.side != side and not target.dead and not target.gone:
			flags[(attackers if reals[motion.R.ATTACK_RANGE * capacity + row] <= 0.0 else aimers) + target.battle_index] += 1
	for slot in 6:
		battle.formation_centers[slot] = Vector2(sums[slot * 2] / counts[slot], sums[slot * 2 + 1] / counts[slot]) if counts[slot] > 0 else Vector2.INF

static func _steer(unit: Unit, position: Vector2, velocity: Vector2, destination: Vector2, speed: float, dt: float, terrain = null) -> Vector2:
	var delta: Vector2 = destination - position
	var distance := delta.length()
	var desired := Vector2.ZERO
	if distance > Config.ARRIVAL_DISTANCE and speed > 0.0:
		if terrain != null:
			speed *= TerrainRules.speed_scale(terrain, position, delta, distance)
		desired = delta / distance * minf(speed, distance * Config.ARRIVAL_BRAKE)
	var rate := Config.HORSE_STEERING_RATE if unit.mounted else Config.FOOT_STEERING_RATE
	var next_velocity := velocity.lerp(desired, minf(1.0, rate * dt))
	if next_velocity.length_squared() > 0.0:
		unit.facing = next_velocity.angle()
	return next_velocity

static func _resolve_unit_collisions(battle: State, index: SpatialIndex, keep_index := true) -> void:
	if index != null:
		_resolve_packed(battle, index if keep_index else null)
		return
	for i in battle.active_units.size():
		var a: Unit = battle.active_units[i]
		if a.dead or a.gone:
			continue
		for j in range(i + 1, battle.active_units.size()):
			_separate(a, battle.active_units[j])
		_finish_unit(a, battle)

## The plain pair loop above, run over packed copies: same pair order, same Vector2 arithmetic, same results.
## Candidates come from a fine grid gathered with some slack, so a's small pushes do not force a new query.
static func _resolve_packed(battle: State, index: SpatialIndex) -> void: # index: kept current for callers that reuse it, else null
	var units := battle.active_units
	var n := units.size()
	var workspace := battle.motion
	workspace.resize(n)
	var pos := workspace.positions
	var rad := workspace.radii
	var mass := workspace.masses
	var side := workspace.sides
	var live := workspace.live
	var max_radius := 0.0
	if battle.contact_solver.is_valid():
		var solved: Array = battle.contact_solver.call(workspace, battle.contact_geometry())
		if solved.size() == 2 and solved[0] is PackedVector2Array and solved[1] is PackedVector2Array and solved[0].size() == n and solved[1].size() == n:
			workspace.positions = solved[0]
			workspace.velocities = solved[1]
			if index != null:
				index.synchronize() # Native replaced the packed buffers; refresh borrowed columns too.
			battle.native_contact_steps += 1
			return
		battle.native_contact_failures += 1
	for i in n:
		var u: Unit = units[i]
		rad[i] = u.collision_radius
		mass[i] = u.mass
		side[i] = u.side
		live[i] = 0 if u.dead or u.gone else 1
		max_radius = maxf(max_radius, u.collision_radius)
	if battle.collision_grid == null:
		battle.collision_grid = CollisionGrid.new(pos, battle.arena_size, live)
	else:
		battle.collision_grid.reset(pos, battle.arena_size, live)
	var grid := battle.collision_grid
	var plain_field := battle.wall == null
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
				# A zero vector has no direction; a deterministic axis breaks an exact stack.
				var normal := Vector2.RIGHT if difference == Vector2.ZERO else difference / distance
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
			pa = battle.static_obstacles.constrain(pa, ra)
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
	unit.position = battle.static_obstacles.constrain(unit.position, unit.collision_radius)

static func _separate(a: Unit, b: Unit) -> bool:
	if b.dead or b.gone:
		return false
	var difference: Vector2 = b.position - a.position
	var radius: float = a.collision_radius + b.collision_radius
	if absf(difference.x) >= radius or absf(difference.y) >= radius or difference.length_squared() >= radius * radius:
		return false
	var distance := maxf(difference.length(), Config.MIN_COLLISION_DISTANCE)
	var normal := Vector2.RIGHT if difference == Vector2.ZERO else difference / distance
	var strength := Config.FRIEND_COLLISION_PUSH if a.side == b.side else Config.ENEMY_COLLISION_PUSH
	var overlap := (radius - distance) * strength
	var total_mass: float = a.mass + b.mass
	a.position -= normal * overlap * b.mass / total_mass
	b.position += normal * overlap * a.mass / total_mass
	return true

## Native execution pauses before rule effects; shared state/RNG are published before resolving them.
static func _step_batch(battle: State, dt: float, rng: RandomNumberGenerator) -> void:
	var groups := PackedFloat64Array()
	for side in battle.groups:
		for group: Group in side:
			var sine := sin(group.direction)
			var cosine := cos(group.direction)
			# GROUP_FIELDS in movement_adapter.cpp: frame, order flags, then the stage 1v doctrine (formed, rally, screen).
			groups.append_array(PackedFloat64Array([group.center.x, group.center.y, -sine, cosine, cosine, sine, group.direction, float(group.order == Config.ORDER_CHARGE), float(group.backing),
				float(group.formed), float(group.rally), group.screen.x, group.screen.y, group.screen_lateral.x, group.screen_lateral.y]))
	var context := {"groups": groups, "arena": battle.arena_size,
		"wall_x": battle.wall.x if battle.wall != null else INF,
		"wall_half": battle.wall.half_width if battle.wall != null else 0.0,
		"gaps": PackedVector2Array(battle.wall.gaps()) if battle.wall != null else PackedVector2Array(),
		"all_gaps": PackedVector2Array(battle.wall.all_gaps()) if battle.wall != null else PackedVector2Array()}
	if battle.terrain_rules != null:
		context.merge(battle.terrain_context) # TERRAIN.md 4.4: the grid the kernel's terrain rules read.
	var begin := true
	while true:
		var result: Array = battle.movement_solver.call(battle.motion, context, rng, dt, begin)
		begin = false
		if result.size() != 3:
			battle.native_movement_failures += 1
			push_error("Native movement rejected a batch; cannot replay a partially applied tick")
			return
		if result[0] == 0: break
		battle.native_movement_interactions += 1
		var unit: Unit = battle.active_units[result[1]]
		var target: Unit = battle.active_units[result[2]] if result[2] >= 0 else null
		match result[0]:
			1: Charge.hit(battle, unit, target, rng)
			2: CombatStep.advance_unit(battle, unit, target, unit.plan_distance, dt, rng)
			3: battle.mark_gone(unit)
	battle.native_movement_steps += 1
	battle.profiler.mark("ai_movement_combat")
	if battle.use_spatial_index and battle.active_units.size() >= Config.SPATIAL_MIN_UNITS:
		_resolve_packed(battle, null)
	else:
		_resolve_unit_collisions(battle, null)
	battle.profiler.mark("contacts")
