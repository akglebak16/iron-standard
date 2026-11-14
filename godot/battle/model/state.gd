extends RefCounted

const Damage = preload("res://battle/rules/damage.gd")
const Group = preload("res://battle/model/group.gd")
const Config = preload("res://battle/config.gd")
const Unit = preload("res://battle/model/unit.gd")

var units: Array[Unit] = []
var arena_size := Config.ARENA_SIZE
var groups: Array = []
var projectiles: Array = []
var starting_units := [0, 0]
var morale_timer := 0.0
var formation_timer := 0.0

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

func add_grouped_unit(unit: Unit, kind: int) -> void:
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
	var foe := centroid(1)
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

func centroid(side: int) -> Vector2:
	var count := 0
	var total := Vector2.ZERO
	for unit: Unit in units:
		if unit.side == side and not unit.dead and not unit.gone and not unit.fleeing:
			total += unit.position
			count += 1
	return total / count if count else Vector2.INF

func add_unit(unit: Unit) -> void:
	units.append(unit)
	starting_units[unit.side] += 1

func hurt(target: Unit, raw_damage: float, source: Unit = null, pierce: float = 0.0) -> int:
	if target.dead:
		return 0
	var amount: int = Damage.after_armor(raw_damage, target.armor, pierce)
	target.hp -= amount
	target.morale -= amount * Config.HIT_MORALE_PER_DAMAGE
	if target.hp <= 0.0 and target.hero and not target.last_stand_used:
		var recovery: float = float(target.perk_effects.get("lastStand", 0.0))
		if recovery > 0.0:
			target.last_stand_used = true
			target.hp = maxf(1.0, target.max_hp * recovery)
	if target.hp <= 0.0:
		kill(target, source)
	return amount

func kill(target: Unit, source: Unit = null) -> void:
	if target.dead:
		return
	target.dead = true
	target.hp = 0.0
	if source != null:
		source.kills += 1
		source.morale = minf(source.base_morale, source.morale + Config.KILL_MORALE_BONUS)
		if source.hero:
			var heal: float = float(source.perk_effects.get("killHeal", 0.0))
			if heal > 0.0:
				source.hp = minf(source.max_hp, source.hp + source.max_hp * heal)
	for unit: Unit in units:
		if unit.dead or unit.gone or unit.position.distance_to(target.position) > Config.DEATH_MORALE_RADIUS:
			continue
		if unit.side == target.side:
			unit.morale -= Config.LEADER_DEATH_MORALE if target.leader or target.hero else Config.ALLY_DEATH_MORALE + target.tier * Config.ALLY_DEATH_MORALE_PER_TIER
		else:
			unit.morale = minf(unit.base_morale, unit.morale + Config.ENEMY_DEATH_MORALE_BONUS)
