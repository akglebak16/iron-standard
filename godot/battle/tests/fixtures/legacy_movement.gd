## Frozen pre-index movement for differential tests. Do not optimize this reference.
extends RefCounted
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Group = preload("res://battle/model/group.gd")
const Targeting = preload("res://battle/rules/targeting.gd")

static func step(battle: State, dt: float, hero_position: Vector2, hero_facing: float = 0.0) -> void:
	if dt <= 0.0:
		return
	var foe := battle.centroid(1)
	for group: Group in battle.groups[0]:
		if group.order != Config.ORDER_FOLLOW:
			continue
		var facing := (foe - hero_position).angle() if foe != Vector2.INF else hero_facing
		group.direction = facing
		var rear: float = Config.FOLLOW_REAR_OFFSET[group.kind]
		var lateral := Config.FOLLOW_CAVALRY_SIDE_OFFSET if group.kind == Config.GROUP_CAVALRY else 0.0
		group.center = hero_position - Vector2(cos(facing), sin(facing)) * rear + Vector2(-sin(facing), cos(facing)) * lateral
	for unit: Unit in battle.units:
		if unit.dead or unit.gone or unit.hero:
			continue
		var group: Group = battle.groups[unit.side][unit.group_kind]
		var destination: Vector2 = group.slot_position(unit, battle.arena_size)
		var velocity_scale := 1.0
		if unit.fleeing:
			destination = Vector2(battle.arena_size.x + Config.FLEE_DESTINATION_PADDING if unit.side == 1 else -Config.FLEE_DESTINATION_PADDING, unit.position.y)
			velocity_scale = Config.FLEE_SPEED_MULTIPLIER
		elif group.order == Config.ORDER_CHARGE:
			var enemy: Unit = Targeting.nearest_enemy(battle, unit)
			if enemy != null:
				destination = enemy.position
		_steer(unit, destination, unit.speed * velocity_scale, dt)
		unit.position += unit.velocity * dt
		if unit.fleeing and (unit.position.x < -Config.FLEE_EXIT_PADDING or unit.position.x > battle.arena_size.x + Config.FLEE_EXIT_PADDING):
			unit.gone = true
		if not unit.fleeing:
			unit.position.x = clampf(unit.position.x, Config.FIELD_LEFT_RIGHT_MARGIN, battle.arena_size.x - Config.FIELD_LEFT_RIGHT_MARGIN)
		unit.position.y = clampf(unit.position.y, Config.FIELD_TOP_MARGIN, battle.arena_size.y - Config.FIELD_BOTTOM_MARGIN)
	_resolve_unit_collisions(battle)

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

static func _resolve_unit_collisions(battle: State) -> void:
	for i in battle.units.size():
		var a: Unit = battle.units[i]
		if a.dead or a.gone:
			continue
		for j in range(i + 1, battle.units.size()):
			var b: Unit = battle.units[j]
			if b.dead or b.gone:
				continue
			var difference: Vector2 = b.position - a.position
			var radius: float = a.collision_radius + b.collision_radius
			if absf(difference.x) >= radius or absf(difference.y) >= radius or difference.length_squared() >= radius * radius:
				continue
			var distance := maxf(difference.length(), Config.MIN_COLLISION_DISTANCE)
			var normal := difference / distance
			var strength := Config.FRIEND_COLLISION_PUSH if a.side == b.side else Config.ENEMY_COLLISION_PUSH
			var overlap := (radius - distance) * strength
			var total_mass: float = a.mass + b.mass
			a.position -= normal * overlap * b.mass / total_mass
			b.position += normal * overlap * a.mass / total_mass
