extends SceneTree
## Stage Р3 (TERRAIN.md 7): the AI uses the terrain, for both sides, only on a field with terrain rules.
## Fighter: a shooter prefers a target he hits better (not in cover, lower than himself); "I will not catch him" weighs
## the own cell's speed. Group: infantry in the forest charges loose; shock cavalry rallies where its run-up is open and
## an AI flank waypoint moves to open ground; AI archers in range take the nearest high ground or forest edge, the
## player's stay where he ordered. Field assessment: the terrain layer (group heights and cover, hill tops, forests,
## crossings). The C++ half of the fighter weights is compared in test_native_movement.gd (scenario "terrain").
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const TerrainGrid = preload("res://core/battle/model/terrain_grid.gd")
const SpatialIndex = preload("res://core/battle/rules/spatial_index.gd")
const Targeting = preload("res://core/battle/rules/targeting.gd")
const SquadDoctrine = preload("res://core/battle/simulation/ai/squad_doctrine.gd")
const FieldAssessment = preload("res://core/battle/simulation/ai/field_assessment.gd")

const CENTER := Vector2(1100, 850)
const PERIOD := Config.AI_SQUAD_PERIOD_SECONDS

func _initialize() -> void:
	for side in 2:
		_check_aim(side)
		_check_outrun(side)
		_check_forest_loose(side)
		_check_rally(side)
		_check_waypoint(side)
		_check_post_high(side)
		_check_post_edge(side)
	_check_survey()
	print("Terrain AI tests passed")
	quit(0)

func _forward(side: int) -> Vector2:
	return Vector2.RIGHT if side == 0 else Vector2.LEFT

func _state() -> State:
	var state := State.new()
	state.setup_groups()
	return state

## Fills cells whose centre `inside` accepts with `cover`, then makes the grid the battle's terrain.
func _lay(state: State, grid: TerrainGrid) -> void:
	state.set_terrain(grid)
	assert(state.terrain_rules == grid)

func _fill(grid: TerrainGrid, rect: Rect2, cover: int) -> void:
	for y in grid.height:
		for x in grid.width:
			if rect.has_point(grid.cell_center(x, y)):
				grid.cover[y * grid.width + x] = cover

func _hill(grid: TerrainGrid, top: Vector2, peak: float, radius: float) -> void:
	for y in grid.height:
		for x in grid.width:
			var d: float = grid.cell_center(x, y).distance_to(top) / radius
			grid.elevation[y * grid.width + x] = clampi(roundi(peak * exp(-d * d * 2.0)), 0, 255)

func _unit(state: State, side: int, kind: int, id: int, at: Vector2) -> Unit:
	var unit := Unit.new(id, side, at, 100, 0, 1)
	unit.speed = 55.0
	state.add_grouped_unit(unit, kind)
	unit.position = at
	return unit

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

func _steps(state: State, count: int, ai := true) -> void:
	for i in count:
		SquadDoctrine.step(state, PERIOD, ai, ai)

## The brain's picture of an enemy squad (tactics.gd _scan): the doctrine reads it for the archers' post.
func _scan(group, at: Vector2) -> void:
	group.scan_points = PackedVector2Array([at, at + Vector2(0, 30), at - Vector2(0, 30)])
	group.scan_count = group.scan_points.size()
	group.scan_center = at

func _check_aim(side: int) -> void:
	var state := _state()
	var grid := TerrainGrid.create(state.arena_size)
	var archer := _unit(state, side, Config.GROUP_ARCHERS, 711, CENTER)
	archer.attack_range = 400.0
	archer.damage = 10.0
	var hidden := _unit(state, 1 - side, Config.GROUP_INFANTRY, 9113, CENTER + _forward(side) * 100.0)
	var open := _unit(state, 1 - side, Config.GROUP_INFANTRY, 9277, CENTER + _forward(side) * 130.0 + Vector2(0, 40))
	assert(Targeting.choose(state, archer) == hidden, "the open field: the nearer man first")
	_fill(grid, Rect2(hidden.position - Vector2(10, 10), Vector2(20, 20)), TerrainGrid.Cover.FOREST)
	_lay(state, grid)
	var plain := SpatialIndex.ranged_weight(100.0, archer.id, archer.damage, hidden, false)
	assert(is_equal_approx(SpatialIndex.ranged_weight(100.0, archer.id, archer.damage, hidden, false, archer.position, hidden.position, grid), plain / Config.TERRAIN_FOREST_HIT_CHANCE), "a man in the forest looks farther by the arrow's chance")
	assert(SpatialIndex.ranged_weight(100.0, archer.id, archer.damage, open, false, archer.position, open.position, grid) == SpatialIndex.ranged_weight(100.0, archer.id, archer.damage, open, false), "the open, flat ground changes nothing")
	assert(Targeting.choose(state, archer) == open, "the shooter takes the man he hits better")
	var index := SpatialIndex.new(state.active_units, state.arena_size)
	index.terrain = grid
	assert(index.best_target(archer, null) == open, "the cell index chooses as the plain loop")
	# Relief: a target the shooter does not stand higher than looks TERRAIN_HIGH_RANGE_MULTIPLIER farther.
	_fill(grid, Rect2(Vector2.ZERO, state.arena_size), TerrainGrid.Cover.OPEN)
	_hill(grid, archer.position, 60.0, 120.0)
	_lay(state, grid)
	assert(grid.elevation[grid.index(archer.position)] - grid.elevation[grid.index(open.position)] >= Config.TERRAIN_HIGHER_STEP)
	var level := _unit(state, 1 - side, Config.GROUP_INFANTRY, 9341, archer.position + Vector2(0, 8))
	assert(SpatialIndex.ranged_weight(100.0, archer.id, archer.damage, open, false, archer.position, open.position, grid) == SpatialIndex.ranged_weight(100.0, archer.id, archer.damage, open, false), "a lower target keeps its weight")
	assert(is_equal_approx(SpatialIndex.ranged_weight(100.0, archer.id, archer.damage, level, false, archer.position, level.position, grid), SpatialIndex.ranged_weight(100.0, archer.id, archer.damage, level, false) * Config.TERRAIN_HIGH_RANGE_MULTIPLIER), "a target on the same height looks farther")

func _check_outrun(side: int) -> void:
	var state := _state()
	var grid := TerrainGrid.create(state.arena_size)
	var man := _unit(state, side, Config.GROUP_INFANTRY, 403, CENTER)
	man.speed = 60.0
	var runner := _unit(state, 1 - side, Config.GROUP_INFANTRY, 9905, CENTER + _forward(side) * 100.0)
	runner.velocity = _forward(side) * 50.0
	var raw := man.position.distance_to(runner.position)
	assert(SpatialIndex.melee_weight(100.0, raw, man.position, man.speed, runner, runner.position, false, false, grid) == 100.0, "he catches a slower man on open ground")
	_fill(grid, Rect2(man.position - Vector2(10, 10), Vector2(20, 20)), TerrainGrid.Cover.FOREST)
	var slowed: float = man.speed * Config.TERRAIN_COVER_SPEED[TerrainGrid.Cover.FOREST]
	var expected := 100.0 * (1.0 + Config.TARGET_OUTRUN_MULTIPLIER * (50.0 - slowed) / slowed)
	assert(is_equal_approx(SpatialIndex.melee_weight(100.0, raw, man.position, man.speed, runner, runner.position, false, false, grid), expected), "in the forest he does not catch him")
	assert(SpatialIndex.melee_weight(100.0, raw, man.position, man.speed, runner, runner.position, false) == 100.0, "without terrain, as before")

func _check_forest_loose(side: int) -> void:
	var state := _state()
	var men := _group(state, side, Config.GROUP_INFANTRY, 24, CENTER, 501)
	var foes := _group(state, 1 - side, Config.GROUP_INFANTRY, 24, CENTER + _forward(side) * 400.0, 9001)
	for i in men.size(): men[i].target_handle = foes[i].unit_handle
	var grid := TerrainGrid.create(state.arena_size)
	_fill(grid, Rect2(Vector2(0, 1500), Vector2(state.arena_size.x, 200)), TerrainGrid.Cover.FOREST)
	_lay(state, grid)
	var group = state.groups[side][Config.GROUP_INFANTRY]
	group.order = Config.ORDER_CHARGE
	SquadDoctrine.step(state, 1.0 / 60.0)
	assert(group.formed, "a forest elsewhere: the line forms")
	_fill(grid, Rect2(CENTER - Vector2(300, 300), Vector2(600, 600)), TerrainGrid.Cover.FOREST)
	_steps(state, ceili(Config.AI_FORMATION_SWITCH_SECONDS / PERIOD) + 1)
	assert(not group.formed, "in the forest the line goes loose")
	_fill(grid, Rect2(CENTER - Vector2(300, 300), Vector2(600, 600)), TerrainGrid.Cover.OPEN)
	_steps(state, ceili(Config.AI_FORMATION_SWITCH_SECONDS / PERIOD) + 1)
	assert(group.formed, "out of the forest it forms again")

func _check_rally(side: int) -> void:
	var state := _state()
	var start := CENTER - _forward(side) * 50.0
	var riders := _group(state, side, Config.GROUP_CAVALRY, 10, start, 7301)
	var foes := _group(state, 1 - side, Config.GROUP_INFANTRY, 10, start + _forward(side) * 30.0, 8801)
	var group = state.groups[side][Config.GROUP_CAVALRY]
	group.order = Config.ORDER_CHARGE
	for i in riders.size():
		riders[i].target_handle = foes[i].unit_handle
		riders[i].position = foes[i].position - _forward(side) * 30.0
	# Forest straight behind the riders, where the plain rally point would be.
	var grid := TerrainGrid.create(state.arena_size)
	var behind := CENTER - _forward(side) * Config.AI_CAVALRY_RALLY_DISTANCE
	_fill(grid, Rect2(behind - Vector2(140, 90), Vector2(280, 180)), TerrainGrid.Cover.FOREST)
	_lay(state, grid)
	while not group.rally:
		_steps(state, 1)
	assert(not TerrainGrid.Cover.FOREST == grid.cover_at(group.center), "the rally point is not in the forest")
	assert(SquadDoctrine.open_run(grid, group.center, CENTER + _forward(side) * 30.0, INF), "the run-up from it is open")
	assert((group.center - CENTER).dot(-_forward(side)) > 0.0, "still away from the targets")

func _check_waypoint(side: int) -> void:
	var state := _state()
	_group(state, side, Config.GROUP_CAVALRY, 8, CENTER - _forward(side) * 300.0 + Vector2(0, 400), 6101)
	_group(state, 1 - side, Config.GROUP_INFANTRY, 8, CENTER + _forward(side) * 300.0, 6601)
	var group = state.groups[side][Config.GROUP_CAVALRY]
	var grid := TerrainGrid.create(state.arena_size)
	_fill(grid, Rect2(Vector2(0, 1350), Vector2(state.arena_size.x, 400)), TerrainGrid.Cover.FOREST)
	_lay(state, grid)
	var waypoint := Vector2(CENTER.x, 1500)
	group.waypoint = waypoint
	_steps(state, 1)
	assert(group.waypoint == waypoint, "the player's cavalry has no flank waypoint to move")
	group.tactic_state = Config.AI_TACTIC_FLANK
	_steps(state, 1)
	assert(group.waypoint.x == waypoint.x and group.waypoint.y < 1350.0, "the waypoint moves out of the forest towards the middle")
	assert(SquadDoctrine.open_run(grid, group.waypoint, state.centroid(1 - side), Config.AI_CAVALRY_CHARGE_DISTANCE))
	var moved: Vector2 = group.waypoint
	_steps(state, 1)
	assert(group.waypoint == moved, "checked once per waypoint")

## AI archers holding in range step onto the nearest ground higher than the enemy; the player's stay.
func _check_post_high(side: int) -> void:
	for ai in [false, true]:
		var state := _state()
		var anchor := CENTER
		_group(state, side, Config.GROUP_ARCHERS, 12, anchor, 3101)
		var foe_at := anchor + _forward(side) * 280.0
		_group(state, 1 - side, Config.GROUP_INFANTRY, 12, foe_at, 3601)
		_scan(state.groups[1 - side][Config.GROUP_INFANTRY], foe_at)
		var grid := TerrainGrid.create(state.arena_size)
		var hill := anchor + Vector2(0, 120)
		_hill(grid, hill, 40.0, 60.0)
		_lay(state, grid)
		var group = state.groups[side][Config.GROUP_ARCHERS]
		_steps(state, 2, ai)
		if not ai:
			assert(group.center == anchor, "the player's archers stand where he ordered")
			continue
		assert(group.center != anchor and group.center.distance_to(anchor) <= Config.AI_TERRAIN_POST_RADIUS, "the post is near")
		assert(grid.height_at(group.center) >= grid.height_at(foe_at) + Config.TERRAIN_HIGHER_STEP, "the post is higher than the enemy")
		var posted: Vector2 = group.center
		_steps(state, 2, ai)
		assert(group.center == posted, "posted once")
		group.center = anchor + _forward(side) * 20.0 # The brain advances: the post is sought anew where it stops.
		_steps(state, 1, ai)
		assert(group.center == anchor + _forward(side) * 20.0)
		_steps(state, 1, ai)
		assert(grid.height_at(group.center) >= grid.height_at(foe_at) + Config.TERRAIN_HIGHER_STEP)
		group.order = Config.ORDER_CHARGE
		_steps(state, 1, ai)
		assert(group.post == Vector2.INF, "a charge forgets the post")

func _check_post_edge(side: int) -> void:
	var state := _state()
	var anchor := CENTER
	_group(state, side, Config.GROUP_ARCHERS, 12, anchor, 4101)
	var foe_at := anchor + _forward(side) * 280.0
	_group(state, 1 - side, Config.GROUP_INFANTRY, 12, foe_at, 4601)
	_scan(state.groups[1 - side][Config.GROUP_INFANTRY], foe_at)
	var grid := TerrainGrid.create(state.arena_size)
	_fill(grid, Rect2(Vector2(0, anchor.y + 100), Vector2(state.arena_size.x, 400)), TerrainGrid.Cover.FOREST)
	_lay(state, grid)
	var group = state.groups[side][Config.GROUP_ARCHERS]
	_steps(state, 2)
	assert(grid.cover_at(group.center) == TerrainGrid.Cover.FOREST, "the archers step into the forest edge")
	assert(grid.cover_at(group.center - Vector2(0, Config.TERRAIN_CELL)) != TerrainGrid.Cover.FOREST, "at its edge, not deep inside")
	# Too close to the enemy: the brain would charge from here; no post.
	var near := _state()
	_group(near, side, Config.GROUP_ARCHERS, 12, anchor, 4101)
	_group(near, 1 - side, Config.GROUP_INFANTRY, 12, anchor + _forward(side) * 120.0, 4601)
	_scan(near.groups[1 - side][Config.GROUP_INFANTRY], anchor + _forward(side) * 120.0)
	_lay(near, grid)
	_steps(near, 2)
	assert(near.groups[side][Config.GROUP_ARCHERS].center == anchor)

func _check_survey() -> void:
	var state := _state()
	var open := FieldAssessment.assess(state)
	assert(open.terrain.tops.is_empty() and open.terrain.forests.is_empty() and not open.terrain.relief, "the open field has no terrain layer")
	var grid := TerrainGrid.create(state.arena_size)
	_hill(grid, Vector2(800, 600), 120.0, 300.0)
	_fill(grid, Rect2(Vector2(1500, 1200), Vector2(400, 200)), TerrainGrid.Cover.FOREST)
	_fill(grid, Rect2(Vector2(1300, 100), Vector2(96, 96)), TerrainGrid.Cover.FORD)
	_fill(grid, Rect2(Vector2(10, 10), Vector2(30, 30)), TerrainGrid.Cover.FOREST) # One cell: too small for a forest.
	_lay(state, grid)
	var men := _group(state, 0, Config.GROUP_INFANTRY, 10, Vector2(800, 600), 101)
	var woods := _group(state, 1, Config.GROUP_INFANTRY, 10, Vector2(1700, 1300), 901)
	var report := FieldAssessment.assess(state)
	var terrain: Dictionary = report.terrain
	assert(terrain.relief and terrain.tops.size() == 1 and terrain.tops[0].at.distance_to(Vector2(800, 600)) < Config.TERRAIN_CELL, "one hill top: %s" % [terrain.tops])
	assert(terrain.forests.size() == 1 and terrain.forests[0].rect.encloses(Rect2(Vector2(1520, 1220), Vector2(360, 160))), "one forest")
	assert(terrain.crossings.size() == 1 and not terrain.crossings[0].bridge and terrain.crossings[0].cells == 9, "one ford")
	var hill_group: Dictionary = report.sides[0].groups[Config.GROUP_INFANTRY]
	var wood_group: Dictionary = report.sides[1].groups[Config.GROUP_INFANTRY]
	assert(hill_group.height > wood_group.height + Config.TERRAIN_HIGHER_STEP and hill_group.forest_share == 0.0)
	assert(wood_group.forest_share == 1.0 and wood_group.wading_share == 0.0)
	terrain.tops.clear()
	assert(FieldAssessment.assess(state).terrain.tops.size() == 1, "each report is detached")
	assert(state.terrain_survey_grid == grid, "the survey is cached for the grid")
	assert(men.size() == 10 and woods.size() == 10)
