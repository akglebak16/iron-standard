extends SceneTree
## Stage 1v (DESIGN.md 4.3, decision 14): group decisions of the troop type doctrines, the same for both sides.
## Infantry in a charge forms a line in the field (centre moved with the formation, turning at a limited rate) and goes
## loose near a siege wall, with its targets across it, in a pursuit, by order and when too small; a switch holds
## AI_FORMATION_SWITCH_SECONDS. A holding infantry group screens its archers from closing riders. Shock cavalry stuck in
## foot melee rallies away from its targets and charges again; contact with archers alone is no reason to rally.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const SiegeWall = preload("res://core/battle/model/siege_wall.gd")
const SquadDoctrine = preload("res://core/battle/simulation/ai/squad_doctrine.gd")

const CENTER := Vector2(1100, 850)
const PERIOD := Config.AI_SQUAD_PERIOD_SECONDS

func _initialize() -> void:
	for side in 2:
		_check_formed_line(side)
		_check_turn(side)
		_check_loose(side)
		_check_screen(side)
		_check_cavalry_cycle(side)
	print("Squad doctrine tests passed")
	quit(0)

func _forward(side: int) -> Vector2:
	return Vector2.RIGHT if side == 0 else Vector2.LEFT

## A group of `count` fighters in formation at `at`, facing the enemy side; ids unrelated to positions.
func _group(state: State, side: int, kind: int, count: int, at: Vector2, first_id: int) -> Array:
	var group = state.groups[side][kind]
	group.center = at
	group.direction = _forward(side).angle()
	var units: Array = []
	for i in count:
		var unit := Unit.new(first_id + i * 37, side, at, 100, 0, 1)
		unit.speed = 55.0
		unit.mounted = kind == Config.GROUP_CAVALRY
		state.add_grouped_unit(unit, kind)
		units.append(unit)
	group.layout(true)
	for unit in units:
		unit.position = group.slot_position(unit, state.arena_size)
	return units

func _target_all(units: Array, targets: Array) -> void:
	for i in units.size():
		units[i].target_handle = targets[i % targets.size()].unit_handle

func _steps(state: State, count: int) -> void:
	for i in count:
		SquadDoctrine.step(state, PERIOD)

func _check_formed_line(side: int) -> void:
	var state := State.new()
	state.setup_groups()
	var men := _group(state, side, Config.GROUP_INFANTRY, 24, CENTER, 501)
	var foes := _group(state, 1 - side, Config.GROUP_INFANTRY, 24, CENTER + _forward(side) * 400.0, 9001)
	_target_all(men, foes)
	var group = state.groups[side][Config.GROUP_INFANTRY]
	_steps(state, 1)
	assert(not group.formed and group.screen == Vector2.INF, "holding: no line, no screen without riders")
	group.order = Config.ORDER_CHARGE
	SquadDoctrine.step(state, 1.0 / 60.0) # An order change is decided at once.
	assert(group.formed, "a charge in the field forms a line")
	var fitted: Vector2 = group.center
	_steps(state, 1)
	assert(group.center.distance_to(fitted + _forward(side) * Config.AI_FORMATION_LEAD) < 1.0, "the slots are AI_FORMATION_LEAD ahead of the line")
	# The line keeps its men: rear ranks stay behind the front.
	var front := 0
	for unit in men:
		if unit.slot_offset.y >= -Config.AI_FORMATION_FRONT_DEPTH: front += 1
	assert(front > 0 and front < men.size())
	# A new order ends the line.
	group.order = Config.ORDER_HOLD
	SquadDoctrine.step(state, 1.0 / 60.0)
	assert(not group.formed)

func _check_turn(side: int) -> void:
	var state := State.new()
	state.setup_groups()
	var men := _group(state, side, Config.GROUP_INFANTRY, 20, CENTER, 77)
	# The targets stand on the line's flank, at a right angle.
	var foes := _group(state, 1 - side, Config.GROUP_INFANTRY, 20, CENTER + Vector2(0, 500), 3003)
	_target_all(men, foes)
	var group = state.groups[side][Config.GROUP_INFANTRY]
	group.order = Config.ORDER_CHARGE
	group.formed = true # Already a line: no re-forming towards the targets.
	group.doctrine_order = Config.ORDER_CHARGE
	var before: float = group.direction
	_steps(state, 1)
	var turned := absf(wrapf(group.direction - before, -PI, PI))
	assert(turned > 0.0 and turned <= Config.AI_FORMATION_TURN_RATE * PERIOD + 1e-6, "the line wheels at a limited rate")
	var ahead: Vector2 = group.center - SquadDoctrine.sample_group(state, group).fitted(group.direction)
	assert(ahead.length() < Config.AI_FORMATION_LEAD * 0.2, "it does not march off while the targets are on its flank")

func _check_loose(side: int) -> void:
	# Pursuit: most targets flee. The switch waits AI_FORMATION_SWITCH_SECONDS.
	var state := State.new()
	state.setup_groups()
	var men := _group(state, side, Config.GROUP_INFANTRY, 16, CENTER, 1201)
	var foes := _group(state, 1 - side, Config.GROUP_INFANTRY, 16, CENTER + _forward(side) * 300.0, 4401)
	_target_all(men, foes)
	var group = state.groups[side][Config.GROUP_INFANTRY]
	group.order = Config.ORDER_CHARGE
	SquadDoctrine.step(state, 1.0 / 60.0)
	assert(group.formed)
	for foe in foes: foe.fleeing = true
	_steps(state, 1)
	assert(group.formed, "a switch holds AI_FORMATION_SWITCH_SECONDS")
	_steps(state, ceili(Config.AI_FORMATION_SWITCH_SECONDS / PERIOD))
	assert(not group.formed, "a pursuit is loose")
	for foe in foes: foe.fleeing = false
	_steps(state, ceili(Config.AI_FORMATION_SWITCH_SECONDS / PERIOD) + 1)
	assert(group.formed, "the line forms again")
	# Ordered loose.
	group.loose = true
	_steps(state, ceili(Config.AI_FORMATION_SWITCH_SECONDS / PERIOD) + 1)
	assert(not group.formed, "loose by order")
	group.loose = false
	# Too few men.
	var small := State.new()
	small.setup_groups()
	var few := _group(small, side, Config.GROUP_INFANTRY, Config.AI_FORMATION_MIN_UNITS - 1, CENTER, 61)
	_target_all(few, _group(small, 1 - side, Config.GROUP_INFANTRY, 8, CENTER + _forward(side) * 300.0, 6001))
	small.groups[side][Config.GROUP_INFANTRY].order = Config.ORDER_CHARGE
	SquadDoctrine.step(small, 1.0 / 60.0)
	assert(not small.groups[side][Config.GROUP_INFANTRY].formed, "too few for a line")
	# Siege: near the wall, or with the targets across it, the group goes through the gates man by man.
	var siege := State.new()
	siege.setup_groups()
	siege.wall = SiegeWall.new(siege.arena_size)
	var wall_x: float = siege.wall.x
	var outside := Vector2(wall_x - Config.AI_FORMATION_WALL_DISTANCE - 300.0, 850)
	var attackers := _group(siege, 0, Config.GROUP_INFANTRY, 16, outside, 801)
	var defenders := _group(siege, 1, Config.GROUP_INFANTRY, 16, outside + Vector2(250, 0), 2801)
	_target_all(attackers, defenders)
	var line = siege.groups[0][Config.GROUP_INFANTRY]
	line.order = Config.ORDER_CHARGE
	SquadDoctrine.step(siege, 1.0 / 60.0)
	assert(line.formed, "in front of the wall, with the enemy on the same side, a line")
	for unit in defenders: unit.position.x = wall_x + 200.0
	_steps(siege, ceili(Config.AI_FORMATION_SWITCH_SECONDS / PERIOD) + 1)
	assert(not line.formed, "targets behind the wall: loose")
	for unit in defenders: unit.position.x = outside.x + 250.0
	for unit in attackers: unit.position.x += 350.0 # Within AI_FORMATION_WALL_DISTANCE of the wall.
	_steps(siege, ceili(Config.AI_FORMATION_SWITCH_SECONDS / PERIOD) + 1)
	assert(not line.formed, "close to the wall: loose")

func _check_screen(side: int) -> void:
	var state := State.new()
	state.setup_groups()
	var archers_at := CENTER - _forward(side) * 100.0
	_group(state, side, Config.GROUP_ARCHERS, 10, archers_at, 3301)
	var spears := _group(state, side, Config.GROUP_INFANTRY, 12, CENTER + Vector2(0, -150), 4101)
	for unit in spears: unit.anti_cavalry = true
	var riders := _group(state, 1 - side, Config.GROUP_CAVALRY, 8, archers_at + Vector2(0, 300), 5101)
	var group = state.groups[side][Config.GROUP_INFANTRY]
	for rider in riders: rider.velocity = Vector2(0, -120) # Towards the archers.
	_steps(state, 1)
	var toward: Vector2 = (state.groups[1 - side][Config.GROUP_CAVALRY].units[0].position - archers_at).normalized()
	assert(group.screen.is_finite(), "riders closing in on the archers: a screen")
	assert(group.screen.distance_to(archers_at + Vector2(0, Config.AI_SCREEN_OFFSET)) < 30.0, "between the archers and the riders")
	assert(absf(group.screen_lateral.dot(Vector2(0, 1))) < 0.2, "the line is across the riders' path")
	for rider in riders: rider.velocity = Vector2(0, 120) # Riding away.
	_steps(state, 1)
	assert(not group.screen.is_finite(), "riders riding away: no screen")
	for rider in riders: rider.velocity = Vector2(0, -120)
	for unit in spears: unit.position += Vector2(0, -Config.AI_SCREEN_RANGE)
	_steps(state, 1)
	assert(not group.screen.is_finite(), "the infantry is too far from the archers")
	assert(toward.y > 0.0)

func _check_cavalry_cycle(side: int) -> void:
	var state := State.new()
	state.setup_groups()
	var start := CENTER - _forward(side) * 50.0
	var riders := _group(state, side, Config.GROUP_CAVALRY, 10, start, 7301)
	var foes := _group(state, 1 - side, Config.GROUP_INFANTRY, 10, start + _forward(side) * 30.0, 8801)
	var group = state.groups[side][Config.GROUP_CAVALRY]
	group.order = Config.ORDER_CHARGE
	# In contact with archers only: the cavalry keeps cutting them down.
	for foe in foes: foe.attack_range = 600.0
	for i in riders.size():
		riders[i].target_handle = foes[i].unit_handle
		riders[i].position = foes[i].position - _forward(side) * 30.0
	_steps(state, ceili(Config.AI_CAVALRY_MELEE_SECONDS / PERIOD) + 2)
	assert(not group.rally, "no rally from archers")
	# Stuck in foot melee: rally away from the targets.
	for foe in foes: foe.attack_range = 0.0
	var steps := 0
	while not group.rally:
		_steps(state, 1)
		steps += 1
		assert(steps <= ceili(Config.AI_CAVALRY_MELEE_SECONDS / PERIOD) + 1)
	assert(steps * PERIOD >= Config.AI_CAVALRY_MELEE_SECONDS, "the rally waits AI_CAVALRY_MELEE_SECONDS of contact")
	var away: Vector2 = (group.center - CENTER).normalized()
	assert(away.dot(-_forward(side)) > 0.9, "back the way it came")
	assert(absf(wrapf(group.direction - _forward(side).angle(), -PI, PI)) < 0.2, "facing the enemy at the rally point")
	# Arrived at the slots: a new run-up.
	for unit in riders: unit.position = group.slot_position(unit, state.arena_size)
	_steps(state, 1)
	assert(not group.rally and group.order == Config.ORDER_CHARGE, "re-formed, it charges again")
	# A rally that cannot arrive ends after AI_CAVALRY_RALLY_SECONDS.
	for i in riders.size(): riders[i].position = foes[i].position - _forward(side) * 30.0
	while not group.rally: _steps(state, 1)
	_steps(state, ceili(Config.AI_CAVALRY_RALLY_SECONDS / PERIOD) + 1)
	assert(not group.rally, "the rally has a time limit")
	# A new order ends the rally at once.
	while not group.rally: _steps(state, 1)
	if side == 0:
		assert(state.give_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.GROUP_CAVALRY))
		assert(not group.rally)
