extends RefCounted

const Damage = preload("res://battle/damage.gd")
const Group = preload("res://battle/group.gd")
const Config = preload("res://battle/config.gd")
const Unit = preload("res://battle/unit.gd")

var units: Array = []
var arena_size := Config.ARENA_SIZE
var groups: Array = []

func spawn_army(side: int, stacks: Array, faction: String, catalog: RefCounted, rng: RandomNumberGenerator) -> bool:
	if side < 0 or side > 1 or groups.size() != 2:
		return false
	var total := 0
	for stack in stacks:
		if not stack is Dictionary or not stack.has("type") or not stack.has("n") or int(stack.n) < 1 or catalog.get_troop(str(stack.type)).is_empty():
			return false
		total += int(stack.n)
	var cap := Config.unit_cap(faction)
	var scale := minf(1.0, float(cap) / total) if total > 0 else 1.0
	for stack in stacks:
		var troop: Dictionary = catalog.get_troop(str(stack.type))
		var count := maxi(1, roundi(int(stack.n) * scale)) if scale < 1.0 else int(stack.n)
		var weight := float(stack.n) / count
		for i in count:
			var kind: int = troop.grp
			var center: Vector2 = groups[side][kind].center
			var jitter := Vector2(rng.randf_range(-Config.SPAWN_JITTER, Config.SPAWN_JITTER), rng.randf_range(-Config.SPAWN_JITTER, Config.SPAWN_JITTER))
			var unit = Unit.new(units.size(), side, center + jitter, float(troop.hp) * weight, float(troop.arm), int(troop.tier))
			unit.troop_id = str(stack.type)
			unit.weight = weight
			unit.damage = float(troop.dmg) * weight
			unit.speed = float(troop.spd) * rng.randf_range(Config.SPEED_RANDOM_MIN, Config.SPEED_RANDOM_MAX)
			unit.attack_range = float(troop.get("range", 0))
			unit.mounted = bool(troop.mounted)
			add_grouped_unit(unit, kind)
	return true

func setup_groups(cavalry_flank: int = 1) -> void:
	groups.clear()
	for side in 2:
		var forward := -1.0 if side == 1 else 1.0
		var facing := PI if side == 1 else 0.0
		var x := arena_size.x - Config.FRONT_X if side == 1 else Config.FRONT_X
		groups.append([
			Group.new(side, Config.GROUP_INFANTRY, Vector2(x, Config.CENTER_Y), facing),
			Group.new(side, Config.GROUP_ARCHERS, Vector2(x - forward * Config.ARCHER_REAR_OFFSET, Config.CENTER_Y), facing),
			Group.new(side, Config.GROUP_CAVALRY, Vector2(x - forward * Config.CAVALRY_REAR_OFFSET, Config.CENTER_Y + cavalry_flank * Config.CAVALRY_FLANK_OFFSET), facing),
		])

func add_grouped_unit(unit: RefCounted, kind: int) -> void:
	unit.group_kind = kind
	add_unit(unit)
	groups[unit.side][kind].units.append(unit)

func place_units() -> void:
	for side_groups in groups:
		for group in side_groups:
			group.layout(true)
			for unit in group.active_units():
				unit.position = group.slot_position(unit, arena_size)

func give_order(order: String, point: Vector2, selection: int = Config.ALL_GROUPS) -> bool:
	if not order in [Config.ORDER_HOLD, Config.ORDER_FOLLOW, Config.ORDER_CHARGE, Config.ORDER_RETREAT] or selection < 0 or selection > Config.ALL_GROUPS:
		return false
	var foe := _centroid(1)
	var changed := false
	for group in groups[0]:
		if selection != Config.ALL_GROUPS and group.kind != selection or group.active_units().is_empty():
			continue
		changed = true
		if order == Config.ORDER_HOLD:
			group.order = Config.ORDER_HOLD
			group.center = point
			if selection == Config.ALL_GROUPS:
				var face: float = (foe - point).angle() if foe != Vector2.INF else 0.0
				group.center -= Vector2(cos(face), sin(face)) * (Config.HOLD_ARCHER_OFFSET if group.kind == Config.GROUP_ARCHERS else 0.0)
				group.center += Vector2(sin(face), -cos(face)) * (Config.HOLD_CAVALRY_OFFSET if group.kind == Config.GROUP_CAVALRY else 0.0)
			if foe != Vector2.INF:
				group.direction = (foe - group.center).angle()
			group.layout()
		elif order == Config.ORDER_RETREAT:
			group.order = Config.ORDER_HOLD
			group.backing = true
			var face: float = (foe - group.center).angle() if foe != Vector2.INF else 0.0
			group.center = (group.centroid() - Vector2(cos(face), sin(face)) * Config.RETREAT_DISTANCE).clamp(Vector2.ONE * Config.RETREAT_EDGE, arena_size - Vector2.ONE * Config.RETREAT_EDGE)
			group.layout()
		else:
			group.order = order
			if order == Config.ORDER_FOLLOW:
				group.layout()
		if order != Config.ORDER_RETREAT:
			group.backing = false
	return changed

func _centroid(side: int) -> Vector2:
	var count := 0
	var total := Vector2.ZERO
	for unit in units:
		if unit.side == side and not unit.dead and not unit.gone:
			total += unit.position
			count += 1
	return total / count if count else Vector2.INF

func add_unit(unit: RefCounted) -> void:
	units.append(unit)

func hurt(target: RefCounted, raw_damage: float, source: RefCounted = null, pierce: float = 0.0) -> int:
	if target.dead:
		return 0
	var amount: int = Damage.after_armor(raw_damage, target.armor, pierce)
	target.hp -= amount
	target.morale -= amount * Config.HIT_MORALE_PER_DAMAGE
	if target.hp <= 0.0:
		kill(target, source)
	return amount

func kill(target: RefCounted, source: RefCounted = null) -> void:
	if target.dead:
		return
	target.dead = true
	target.hp = 0.0
	if source != null:
		source.kills += 1
		source.morale = minf(source.base_morale, source.morale + Config.KILL_MORALE_BONUS)
	for unit in units:
		if unit.dead or unit.gone or unit.position.distance_to(target.position) > Config.DEATH_MORALE_RADIUS:
			continue
		if unit.side == target.side:
			unit.morale -= Config.LEADER_DEATH_MORALE if target.leader or target.hero else Config.ALLY_DEATH_MORALE + target.tier * Config.ALLY_DEATH_MORALE_PER_TIER
		else:
			unit.morale = minf(unit.base_morale, unit.morale + Config.ENEMY_DEATH_MORALE_BONUS)
