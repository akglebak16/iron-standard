extends RefCounted

const Damage = preload("res://battle/damage.gd")
const Group = preload("res://battle/group.gd")

var units: Array = []
var arena_size := Vector2(2600, 1700)
var groups: Array = []

func setup_groups(cavalry_flank: int = 1) -> void:
	groups.clear()
	for side in 2:
		var forward := -1.0 if side == 1 else 1.0
		var facing := PI if side == 1 else 0.0
		var x := 1960.0 if side == 1 else 640.0
		groups.append([
			Group.new(side, 0, Vector2(x, 850), facing),
			Group.new(side, 1, Vector2(x - forward * 105.0, 850), facing),
			Group.new(side, 2, Vector2(x - forward * 20.0, 850 + cavalry_flank * 380.0), facing),
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

func give_order(order: String, point: Vector2, selection: int = 3) -> bool:
	if not order in ["hold", "follow", "charge", "back"] or selection < 0 or selection > 3:
		return false
	var foe := _centroid(1)
	var changed := false
	for group in groups[0]:
		if selection != 3 and group.kind != selection or group.active_units().is_empty():
			continue
		changed = true
		if order == "hold":
			group.order = "hold"
			group.center = point
			if selection == 3:
				var face: float = (foe - point).angle() if foe != Vector2.INF else 0.0
				group.center -= Vector2(cos(face), sin(face)) * (95.0 if group.kind == 1 else 0.0)
				group.center += Vector2(sin(face), -cos(face)) * (240.0 if group.kind == 2 else 0.0)
			if foe != Vector2.INF:
				group.direction = (foe - group.center).angle()
			group.layout()
		elif order == "back":
			group.order = "hold"
			group.backing = true
			var face: float = (foe - group.center).angle() if foe != Vector2.INF else 0.0
			group.center = (group.centroid() - Vector2(cos(face), sin(face)) * 300.0).clamp(Vector2(80, 80), arena_size - Vector2(80, 80))
			group.layout()
		else:
			group.order = order
			if order == "follow":
				group.layout()
		if order != "back":
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
	target.morale -= amount * 0.12
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
		source.morale = minf(source.base_morale, source.morale + 8.0)
	for unit in units:
		if unit.dead or unit.gone or unit.position.distance_to(target.position) > 170.0:
			continue
		if unit.side == target.side:
			unit.morale -= 9.0 if target.leader or target.hero else 1.6 + target.tier * 0.5
		else:
			unit.morale = minf(unit.base_morale, unit.morale + 3.0)
