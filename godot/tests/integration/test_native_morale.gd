extends SceneTree
## ADR-026 acceptance: the native morale kernel (core/battle/api/native/morale_kernel.hpp) against the GDScript reference
## (rules/morale.gd, simulation/ai/field_assessment.gd) on every morale check, bit for bit: every column (the morale
## fields, the steps of a fighter, slot offsets of the groups men rallied into), the notices in order, the active
## counts, the group summaries and State.assessment. No tolerance: one ULP is a porting error.
##
## Two equal battles, `a` without a column backend (the reference) and `b` with the native one; both move with the
## native movement kernel (itself compared with its reference by test_native_movement.gd), so the morale check is the
## only part that differs. Between the checks both run the same code:
## RNG and events are compared every tick, the columns at every check (before it in _check, which compares them after). The session's own schedule is switched off and
## the test runs the check itself every MORALE_TICK_SECONDS, so it can read the state just before each check and prove
## from it that every rule decided something (a rule that never fires proves nothing by equal columns).
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const NativeColumns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
const Config = preload("res://core/battle/config.gd")
const Event = preload("res://core/battle/combat_event.gd")
const Morale = preload("res://core/battle/rules/morale.gd")
const FieldAssessment = preload("res://core/battle/simulation/ai/field_assessment.gd")
const TerrainGrid = preload("res://core/battle/model/terrain_grid.gd")
const DT := 1.0 / 60.0
const CHECK_TICKS := 60 # MORALE_TICK_SECONDS at 60 ticks a second.
const LOW_BASE := 30.0
# Rules each scenario must prove. Together they cover ADR-026: wavered, fled, rallied, panic, the collapse of a side,
# pursuit, the help of a leader, the edge of the field, the limit of rallies, immune fighters, allies (#243), the loose
# charge (mean facing), terrain in the assessment and a large field.
const SCENARIOS := {
	"rout": ["wavered", "fled", "rallied", "panic", "pursued", "leader", "loose", "recovered"],
	"collapse": ["collapse", "fled"],
	"edge": ["edge", "limit", "rallied"],
	"undead": ["immune", "wavered"],
	"allies": ["allies"],
	"terrain": ["terrain", "wavered"],
	"large": ["fled", "panic", "wavered"],
}

var _catalog: Catalog

func _initialize() -> void:
	_catalog = Catalog.new()
	assert(Loader.populate(_catalog))
	var columns = NativeColumns.create()
	assert(columns != null and columns._morale != null, "the native morale kernel is in the library")
	for scenario in SCENARIOS:
		_run(scenario)
	print("Native morale parity tests passed")
	quit(0)

func _run(scenario: String) -> void:
	var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.companion_profiles.clear()
	setup.hero_profile.clear() # The hero stays on the field (a leader for the rally); his gear needs catalogs.
	match scenario:
		"rout", "terrain":
			setup.player_army.assign([{"type": "n1", "n": 40}, {"type": "n2a", "n": 16}, {"type": "n3c", "n": 10}])
			setup.enemy_army.assign([{"type": "e1", "n": 50}, {"type": "e2a", "n": 16}, {"type": "e3c", "n": 16}])
		"collapse", "edge":
			setup.player_army.assign([{"type": "n1", "n": 40}, {"type": "n2a", "n": 12}, {"type": "n3c", "n": 8}])
			setup.enemy_army.assign([{"type": "e1", "n": 60}, {"type": "e2a", "n": 16}, {"type": "e3c", "n": 16}])
		"undead":
			setup.player_army.assign([{"type": "n1", "n": 50}, {"type": "n2a", "n": 16}, {"type": "n3c", "n": 14}])
			setup.enemy_army.assign([{"type": "s1", "n": 40}, {"type": "s1a", "n": 12}, {"type": "s2c", "n": 10}])
		"allies":
			var ally_faction := _faction_with_all_kinds([setup.player_faction, setup.enemy_faction])
			assert(not ally_faction.is_empty())
			setup.ally_faction = ally_faction
			setup.ally_army.assign(_army(ally_faction, [16, 6, 4]))
			setup.player_army.assign([{"type": "n1", "n": 20}, {"type": "n2a", "n": 8}, {"type": "n3c", "n": 6}])
			setup.enemy_army.assign([{"type": "e1", "n": 70}, {"type": "e2a", "n": 20}, {"type": "e3c", "n": 18}])
		"large":
			setup.player_army.assign([{"type": "n1", "n": 160}, {"type": "n2a", "n": 60}, {"type": "n3c", "n": 50}])
			setup.enemy_army.assign([{"type": "e1", "n": 160}, {"type": "e2a", "n": 60}, {"type": "e3c", "n": 50}])
	var a := Factory.create(setup, _catalog, null, null, null, Contacts.create(), Movement.create())
	var b := Factory.create(setup, _catalog, null, null, null, Contacts.create(), Movement.create(), NativeColumns.create())
	assert(a != null and b != null and a._state.column_backend == null and b._state.column_backend != null)
	assert(a._state.movement_solver.is_valid() and b._state.movement_solver.is_valid())
	for battle in [a, b]:
		_prepare(scenario, battle)
	var fired := {}
	for key in SCENARIOS[scenario]: fired[key] = false
	var ticks := 900 if scenario == "large" else 1200
	if scenario == "edge":
		_check(scenario, a, b, fired, -1) # The fugitives stand where the scenario put them.
	for tick in ticks:
		if scenario == "collapse" and tick == 240:
			# Most of the player's side falls at once: the rest is a fifth of the start and half the enemy.
			for battle in [a, b]:
				var lost := 0
				for unit in battle._state.active_units.duplicate():
					if unit.side == 0 and not unit.hero and not unit.dead and lost < 52:
						battle._state.kill(unit)
						lost += 1
		a.step()
		b.step()
		assert(a._rng.state == b._rng.state, "RNG %s tick %d" % [scenario, tick])
		assert(a.take_events() == b.take_events(), "Events %s tick %d" % [scenario, tick])
		if tick % CHECK_TICKS == CHECK_TICKS - 1:
			_check(scenario, a, b, fired, tick)
	for key in fired:
		assert(fired[key], "the morale rule %s must decide something in scenario %s: %s" % [key, scenario, fired])
	print("  %s: %s" % [scenario, fired.keys()])

func _prepare(scenario: String, battle) -> void:
	var state = battle._state
	state.morale_timer = INF # The test runs the checks (see _check).
	match scenario:
		"rout", "terrain":
			# Stage 1b: the player's side charges loose with a shaken half and a few men about to run.
			_place(state, state.groups[0][Config.GROUP_INFANTRY], Vector2(1150, 850), 0.0)
			_place(state, state.groups[0][Config.GROUP_ARCHERS], Vector2(1000, 850), 0.0)
			_place(state, state.groups[0][Config.GROUP_CAVALRY], Vector2(1050, 500), 0.0)
			_place(state, state.groups[1][Config.GROUP_INFANTRY], Vector2(1900, 850), PI)
			_place(state, state.groups[1][Config.GROUP_ARCHERS], Vector2(2050, 850), PI)
			_place(state, state.groups[1][Config.GROUP_CAVALRY], Vector2(2000, 1200), PI)
			battle.issue_order("charge", Vector2.ZERO, 3)
			state.groups[0][Config.GROUP_INFANTRY].loose = true
			for unit in state.groups[0][Config.GROUP_INFANTRY].units:
				if unit.id % 2 == 0:
					unit.base_morale = LOW_BASE
					unit.morale = LOW_BASE * 0.3
				elif unit.id % 7 == 1:
					unit.morale = -5.0
			if scenario == "terrain":
				_place(state, state.groups[0][Config.GROUP_CAVALRY], Vector2(1050, 1150), 0.0) # In the forest, on the hill.
				state.set_terrain(_terrain_grid(state.arena_size))
		"collapse":
			battle.issue_order("charge", Vector2.ZERO, 3)
		"edge":
			# Fugitives far from any enemy: at the left edge with morale enough to rally, in the field after their last
			# rally, in the field ready to turn back.
			for group in state.groups[1]: group.order = Config.ORDER_HOLD
			for group in state.groups[0]: group.order = Config.ORDER_HOLD
			var infantry: Array = state.groups[0][Config.GROUP_INFANTRY].units
			for n in infantry.size():
				var unit = infantry[n]
				unit.fleeing = true
				unit.morale = unit.base_morale * 0.6
				match n % 3:
					0: unit.position = Vector2(40.0 + n, 300.0 + 12.0 * n)
					1:
						unit.position = Vector2(500.0 + n, 300.0 + 12.0 * n)
						unit.rallies = Config.MORALE_RALLY_LIMIT
					2: unit.position = Vector2(520.0 + n, 300.0 + 12.0 * n)
		"undead", "allies", "large":
			battle.issue_order("charge", Vector2.ZERO, 3)
			if scenario == "undead":
				for unit in state.groups[0][Config.GROUP_INFANTRY].units: unit.morale = unit.base_morale * 0.3
			if scenario == "large":
				for unit in state.active_units:
					# A third shaken, every tenth about to run in the middle of his rank: flights and panic in dense blocks.
					if not unit.hero and unit.side == 0 and unit.id % 3 == 0: unit.morale = unit.base_morale * 0.2
					if not unit.hero and unit.side == 0 and unit.id % 10 == 1: unit.morale = -20.0

## One compared morale check on both battles; proofs are read from the reference battle just before and after it.
func _check(scenario: String, a, b, fired: Dictionary, tick: int) -> void:
	var state = a._state
	var before := {}
	for unit in state.active_units:
		if not unit.dead and not unit.gone:
			before[unit] = [unit.morale, unit.fleeing, unit.rallies, unit.position]
	var collapsed := _collapsed(state)
	var serial: int = state.assessment_serial
	_same_columns(a, b, "%s before the check at tick %d" % [scenario, tick])
	Morale.tick(a._state)
	Morale.tick(b._state)
	var label := "%s check at tick %d" % [scenario, tick]
	_same_columns(a, b, label)
	assert(var_to_bytes(a._state.assessment) == var_to_bytes(b._state.assessment), "Assessment " + label)
	assert(a._state.assessment_serial == serial + 1 and b._state.assessment_serial == serial + 1, "Assessment serial " + label)
	assert(a._state.active_counts == b._state.active_counts, "Active counts " + label)
	assert(var_to_bytes(a._state._events) == var_to_bytes(b._state._events), "Notices " + label)
	for command in a._state.groups.size():
		for kind in a._state.groups[command].size():
			var left = a._state.groups[command][kind]
			var right = b._state.groups[command][kind]
			assert(left.morale_state == right.morale_state and var_to_bytes(left.morale_pressure) == var_to_bytes(right.morale_pressure) \
				and var_to_bytes(left.morale_fleeing_share) == var_to_bytes(right.morale_fleeing_share), "Group summary " + label)
	_prove(scenario, state, before, collapsed, fired)

func _prove(scenario: String, state, before: Dictionary, collapsed: Array, fired: Dictionary) -> void:
	var routers: Array = []
	for notice in state._events:
		if notice.kind == Event.Kind.WAVERED and fired.has("wavered"): fired.wavered = true
		if notice.kind == Event.Kind.RALLIED and fired.has("rallied"): fired.rallied = true
		if notice.kind == Event.Kind.FLED:
			routers.append(notice)
			if fired.has("fled"): fired.fled = true
			if fired.has("collapse") and collapsed[notice.side]: fired.collapse = true
	for unit: Object in before:
		var was: Array = before[unit]
		if unit.dead or unit.gone or unit.hero: continue
		var changed: bool = unit.morale != was[0]
		if unit.morale_immune:
			if fired.has("immune") and not changed: fired.immune = true
			continue
		if fired.has("allies") and unit.command == Config.COMMAND_ALLY and changed: fired.allies = true
		if not was[1]: continue
		# A fugitive before the check.
		var base: float = unit.base_morale
		if was[2] >= Config.MORALE_RALLY_LIMIT:
			if fired.has("limit") and unit.fleeing and not changed: fired.limit = true
			continue
		if fired.has("pursued") and unit.fleeing and not changed and _near(state, unit, 1 - unit.side, Config.MORALE_PURSUIT_RADIUS):
			fired.pursued = true
		if fired.has("leader") and is_equal_approx(unit.morale - was[0], Config.MORALE_ROUT_RECOVERY + Config.MORALE_RALLY_LEADER_BONUS) and unit.morale < base:
			fired.leader = true
		if fired.has("recovered") and is_equal_approx(unit.morale - was[0], Config.MORALE_ROUT_RECOVERY) and unit.fleeing:
			fired.recovered = true
		if unit.fleeing and unit.morale >= base * Config.MORALE_RALLY_SHARE and not collapsed[unit.side]:
			var x: float = was[3].x
			var edge: bool = x < Config.MORALE_RALLY_EDGE or x > state.arena_size.x - Config.MORALE_RALLY_EDGE
			if edge and fired.has("edge"): fired.edge = true
	if fired.has("panic"):
		for notice in routers:
			for unit: Object in before:
				if unit.dead or unit.gone or unit.hero or unit.fleeing or unit.morale_immune or unit.side != notice.side: continue
				if unit.position.distance_to(notice.position) <= Config.MORALE_PANIC_RADIUS:
					fired.panic = true
	if fired.has("loose"):
		for group in state.groups[0]:
			if group.order == Config.ORDER_CHARGE and not group.formed and state.assessment.sides[0].groups[group.kind].count > 0:
				fired.loose = true
	if fired.has("terrain"):
		for side in state.assessment.sides:
			for group in side.groups:
				if group.forest_share > 0.0 and group.height > 0.0: fired.terrain = true

static func _near(state, unit, side: int, radius: float) -> bool:
	for other in state.active_units:
		if other.side == side and not other.dead and not other.gone and not other.fleeing and other.position.distance_to(unit.position) < radius:
			return true
	return false

## Morale.tick's collapse of a side, read before the check.
static func _collapsed(state) -> Array:
	var active := [0, 0]
	for unit in state.active_units:
		if not unit.dead and not unit.gone and not unit.fleeing: active[unit.side] += 1
	var out := [false, false]
	for side in 2:
		var enemies: float = maxf(Config.MORALE_OPPONENT_FLOOR, active[1 - side])
		out[side] = active[side] <= state.starting_units[side] * Config.MORALE_FORCE_FLEE_START_SHARE and active[side] < enemies * Config.MORALE_FORCE_FLEE_ENEMY_SHARE and state.starting_units[side] > Config.MORALE_FORCE_FLEE_MIN_START
	return out

static func _same_columns(a, b, label: String) -> void:
	var left = a._state.motion
	var right = b._state.motion
	assert(left.capacity == right.capacity, "Capacity " + label)
	assert(left.positions.to_byte_array() == right.positions.to_byte_array(), "Positions " + label)
	assert(left.velocities.to_byte_array() == right.velocities.to_byte_array(), "Velocities " + label)
	assert(left.real_fields.to_byte_array() == right.real_fields.to_byte_array(), "Real columns " + label)
	assert(left.integer_fields.to_byte_array() == right.integer_fields.to_byte_array(), "Integer columns " + label)
	assert(left.vector_fields.to_byte_array() == right.vector_fields.to_byte_array(), "Vector columns " + label)

static func _place(state, group, at: Vector2, facing: float) -> void:
	group.center = at
	group.direction = facing
	group.layout(true)
	for unit in group.units:
		unit.position = group.slot_position(unit, state.arena_size)
		unit.velocity = Vector2.ZERO

## Forest along the lower edge, brush on the enemy's flank, a river with a ford, and a hill under the player's archers.
static func _terrain_grid(arena: Vector2):
	var grid = TerrainGrid.create(arena)
	for y in grid.height:
		for x in grid.width:
			var center: Vector2 = grid.cell_center(x, y)
			var k: int = y * grid.width + x
			if center.y > 1000.0: grid.cover[k] = TerrainGrid.Cover.FOREST
			elif center.y > 900.0 and center.x > 1700.0: grid.cover[k] = TerrainGrid.Cover.BRUSH
			if center.x >= 1500.0 and center.x < 1600.0 and center.y <= 1000.0:
				grid.cover[k] = TerrainGrid.Cover.FORD if center.y < 700.0 else TerrainGrid.Cover.WATER
			var d := center.distance_to(Vector2(1000, 950)) / 450.0
			grid.elevation[k] = clampi(roundi(220.0 * exp(-d * d * 2.0)), 0, 255)
	return grid

func _faction_with_all_kinds(skip: Array) -> String:
	for faction in ["dom", "khan", "gal", "rus", "nord", "emp"]:
		if faction in skip:
			continue
		var kinds := {}
		for troop in _catalog.for_faction(faction):
			kinds[int(troop.grp)] = true
		if kinds.size() == 3:
			return faction
	return ""

func _army(faction: String, counts: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind in 3:
		for troop in _catalog.for_faction(faction):
			if int(troop.grp) == kind:
				out.append({"type": troop.id, "n": counts[kind]})
				break
	return out
