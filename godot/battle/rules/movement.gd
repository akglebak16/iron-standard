extends RefCounted
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Group = preload("res://battle/model/group.gd")
const Targeting = preload("res://battle/rules/targeting.gd")
const SpatialIndex = preload("res://battle/rules/spatial_index.gd")
const Charge = preload("res://battle/rules/charge.gd")
const AiDecision = preload("res://battle/rules/ai_decision.gd")

static func step(battle: State, dt: float, hero_position: Vector2, hero_facing: float = 0.0, rng: RandomNumberGenerator = null) -> SpatialIndex:
	if dt <= 0.0:
		return null
	var index: SpatialIndex = SpatialIndex.new(battle.units) if battle.units.size() >= Config.SPATIAL_MIN_UNITS else null
	for unit_index in battle.units.size():
		var unit: Unit = battle.units[unit_index]
		if unit.dead or unit.gone or unit.hero:
			continue
		unit.charge_cooldown -= dt
		var group: Group = battle.groups[unit.side][unit.group_kind]
		var destination: Vector2 = group.slot_position(unit, battle.arena_size)
		var velocity_scale := 1.0
		var ai_face := unit.facing
		if unit.fleeing:
			destination = Vector2(battle.arena_size.x + Config.FLEE_DESTINATION_PADDING if unit.side == 1 else -Config.FLEE_DESTINATION_PADDING, unit.position.y)
			velocity_scale = Config.FLEE_SPEED_MULTIPLIER
		elif rng != null:
			var enemy := Targeting.refresh(battle, unit, dt, rng)
			var plan := AiDecision.plan(unit, group, enemy, battle.arena_size)
			unit.ai_mode = plan.mode
			destination = plan.destination
			velocity_scale = plan.speed_scale
			ai_face = plan.face
			if unit.ai_mode == Config.AI_MODE_MELEE and enemy != null and Charge.can_hit(unit, enemy):
				Charge.hit(battle, unit, enemy, rng)
				if destination != unit.position:
					destination = enemy.position
				if index != null:
					index.update(battle.units.find(enemy))
		elif group.order == Config.ORDER_CHARGE:
			var enemy: Unit = Targeting.nearest_enemy(battle, unit, index)
			if enemy != null:
				destination = enemy.position
				if rng != null and Charge.can_hit(unit, enemy):
					Charge.hit(battle, unit, enemy, rng)
					destination = enemy.position
					if index != null:
						index.update(battle.units.find(enemy))
		_steer(unit, destination, unit.speed * velocity_scale, dt)
		if rng != null and not unit.fleeing:
			unit.facing = ai_face
		unit.position += unit.velocity * dt
		if unit.fleeing and (unit.position.x < -Config.FLEE_EXIT_PADDING or unit.position.x > battle.arena_size.x + Config.FLEE_EXIT_PADDING):
			unit.gone = true
		if index != null:
			index.update(unit_index)
	_resolve_unit_collisions(battle, index)
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

static func _resolve_unit_collisions(battle: State, index: SpatialIndex) -> void:
	var max_radius := 0.0
	if index != null:
		for unit: Unit in battle.units:
			max_radius = maxf(max_radius, unit.collision_radius)
	for i in battle.units.size():
		var a: Unit = battle.units[i]
		if a.dead or a.gone:
			continue
		if index == null:
			for j in range(i + 1, battle.units.size()):
				_separate(a, battle.units[j])
		else:
			var next_index := i + 1
			while next_index < battle.units.size():
				var candidates := index.nearby(a.position, a.collision_radius + max_radius, next_index)
				var collided := false
				for j in candidates:
					next_index = j + 1
					if not _separate(a, battle.units[j]):
						continue
					index.update(i)
					index.update(j)
					collided = true
					break # A moved: refresh candidates for later indices.
				if not collided:
					break
		# Browser battleUpdate clamps each unit after resolving its pair collisions.
		if not a.fleeing:
			a.position.x = clampf(a.position.x, Config.FIELD_LEFT_RIGHT_MARGIN, battle.arena_size.x - Config.FIELD_LEFT_RIGHT_MARGIN)
		a.position.y = clampf(a.position.y, Config.FIELD_TOP_MARGIN, battle.arena_size.y - Config.FIELD_BOTTOM_MARGIN)
		if index != null:
			index.update(i)

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
