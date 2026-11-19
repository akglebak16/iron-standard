extends RefCounted
const Morale = preload("res://core/battle/rules/morale.gd")
const SquadDoctrine = preload("res://core/battle/simulation/ai/squad_doctrine.gd")
const CombatStep = preload("res://core/battle/rules/combat_step.gd")
const Movement = preload("res://core/battle/rules/movement.gd")
const Tactics = preload("res://core/battle/rules/tactics.gd")
const SiegeDefense = preload("res://core/battle/rules/siege_defense.gd")
## Single writer for a running battle. No SceneTree, Input, files or translated text.
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const HeroInput = preload("res://core/battle/application/hero_input.gd")
const HeroControl = preload("res://core/battle/rules/hero_control.gd")
const Config = preload("res://core/battle/config.gd")
const GearCatalog = preload("res://core/equipment/data/gear_catalog.gd")
const HeroGear = preload("res://core/equipment/rules/hero_gear.gd")
const HeroStats = preload("res://core/battle/data/hero_stats.gd")
const BattleResult = preload("res://core/battle/rules/result.gd")
const Event = preload("res://core/battle/combat_event.gd")
const RenderSnapshot = preload("res://core/battle/application/render_snapshot.gd")
const Reinforcements = preload("res://core/battle/data/reinforcements.gd")
const Profiles = preload("res://core/battle/simulation/ai/profiles.gd")
const DecisionSchedule = preload("res://core/battle/simulation/ai/decision_schedule.gd")
const DecisionTrace = preload("res://core/battle/simulation/ai/decision_trace.gd")
const FieldAssessment = preload("res://core/battle/simulation/ai/field_assessment.gd")
const AiDebugSnapshot = preload("res://core/battle/application/ai_debug_snapshot.gd")
const WEAPON_SLOT_MELEE := HeroGear.MELEE
const WEAPON_SLOT_RANGED := HeroGear.RANGED
enum Outcome { RUNNING, HERO_DOWN, VICTORY, DEFEAT }

var _state: State
var _hero: Unit
var _rng: RandomNumberGenerator
var _input: Dictionary = {}
var _orders: Array[Dictionary] = []
var _outcome: Outcome = Outcome.RUNNING
var _battle_over_at: float = -1.0
var _battle_won: bool = false
var _result: Dictionary = {}
var _tick: int = 0
var _elapsed_seconds: float = 0.0
var _gear_catalog: GearCatalog
var _hero_profile: Dictionary = {}
var _swap_held: bool = false
var _requested_slot := ""
var _slot_request_ticks := 0
var _weapon_names: Dictionary = {}
var _retreat_requested := false
var _starting_ally_strength := 0.0
var _companion_survival: float
var _events: Array[Dictionary] = []
var _companion_dialogue: Dictionary
var _previous_positions := PackedVector2Array()
## AI per side (ADR-022): profile ids from BattleSetup and their brains; a null brain follows player orders.
var _ai_profiles: Array[String] = [Config.AI_PROFILE_PLAYER, Config.AI_PROFILE_REFERENCE]
var _brains: Array[Script] = [null, Tactics]
## Diagnostics only: refreshes the field assessment for the debug snapshot on commander ticks.
var _schedule := DecisionSchedule.new()
var _assessment: Dictionary = {}
var _assessment_tick := -1

## Fixed production tick; advance(dt) remains for the legacy differential fixtures.
func step() -> void:
	advance(1.0 / 60.0)

func _init(state: State, hero: Unit, rng: RandomNumberGenerator, gear_catalog: GearCatalog = null, hero_profile: Dictionary = {}, companion_survival: float = 0.0, companion_dialogue: Dictionary = {}, ai_profiles: Array[String] = [Config.AI_PROFILE_PLAYER, Config.AI_PROFILE_REFERENCE]) -> void:
	assert(state != null and hero != null and rng != null)
	assert(hero.hero and hero in state.units)
	# Factory validates profiles against the setup; unknown ids here keep the default profiles.
	var known := ai_profiles.size() == 2 and Profiles.is_known(ai_profiles[0]) and Profiles.is_known(ai_profiles[1])
	assert(known, "Unknown AI profile")
	if known:
		_ai_profiles = ai_profiles.duplicate()
	else:
		push_error("Unknown AI profiles %s" % str(ai_profiles))
	_brains = [Profiles.brain(_ai_profiles[0]), Profiles.brain(_ai_profiles[1])]
	_state = state
	_hero = hero
	_rng = rng
	_gear_catalog = gear_catalog
	_hero_profile = hero_profile.duplicate(true)
	if not hero_profile.is_empty() and gear_catalog != null:
		var gear := HeroGear.resolve(_hero_profile, _gear_catalog)
		_weapon_names = gear.get("weapon_names", {})
	for unit in _state.units:
		if unit.side == 0:
			_starting_ally_strength += unit.weight
	_companion_survival = companion_survival
	_companion_dialogue = companion_dialogue.duplicate(true)
	_state.record_notice(Event.Kind.BATTLE_STARTED)

func set_hero_input(input: HeroInput) -> bool:
	if _outcome != Outcome.RUNNING or _hero.dead or input == null or not input.move.is_finite() or not is_finite(input.face):
		return false
	_input = input.to_dictionary()
	return true

func issue_order(order: String, point: Vector2, selection: int) -> bool:
	if _outcome in [Outcome.VICTORY, Outcome.DEFEAT] or not point.is_finite() or selection < 0 or selection > Config.ALL_GROUPS:
		return false
	if order not in [Config.ORDER_HOLD, Config.ORDER_FOLLOW, Config.ORDER_CHARGE, Config.ORDER_RETREAT]:
		return false
	_orders.append({"order": order, "point": point, "selection": selection})
	return true

func advance(dt: float) -> void:
	if _outcome in [Outcome.VICTORY, Outcome.DEFEAT] or not is_finite(dt) or dt <= 0.0:
		return
	_state.profiler.begin()
	_previous_positions.resize(_state.units.size())
	var positions := _state.motion.positions
	if _state.column_backend != null:
		_previous_positions = _state.column_backend.capture(_state.motion, _previous_positions)
		for unit: Unit in _state.retired_render_units:
			_previous_positions[unit.history_index] = unit.position
	else:
		for unit: Unit in _state.render_units():
			_previous_positions[unit.history_index] = positions[unit.battle_index] if unit.battle_index >= 0 else unit.position
	for command in _orders:
		if _state.give_order(command.order, command.point, command.selection):
			_state.record_notice(Event.Kind.ORDER_APPLIED, {"order": command.order, "selection": command.selection, "point": command.point})
	_orders.clear()
	if _retreat_requested:
		_retreat_requested = false
		_battle_over_at = _elapsed_seconds
		_battle_won = false
		_state.record_notice(Event.Kind.BATTLE_RETREATED)
	_elapsed_seconds += dt
	_state.profiler.mark("commands_interpolation")
	if _state.ai_trace != null:
		_state.ai_trace.begin_tick(_tick, _elapsed_seconds)
	var defender: Script = _brains[1]
	if _state.wall == null:
		if defender != null:
			defender.enemy_step(_state, 1, _elapsed_seconds, dt)
	else:
		if defender != null:
			defender.siege_step(_state, _elapsed_seconds, dt)
		SiegeDefense.step(_state, dt, _rng)
	if _brains[0] != null:
		_brains[0].enemy_step(_state, 0, _elapsed_seconds, dt)
	if _state.has_allies():
		Tactics.enemy_step(_state, Config.COMMAND_ALLY, _elapsed_seconds, dt) # the allies' own commander (#243)
	Tactics.follow_hero(_state, _hero)
	SquadDoctrine.step(_state, dt)
	Tactics.relayout(_state, dt)
	_state.profiler.mark("tactics_siege")
	_handle_swap()
	HeroControl.step(_state, _hero, _input, dt, _rng)
	_state.profiler.mark("hero")
	Movement.step(_state, dt, _rng)
	CombatStep.resolve_projectiles(_state, dt, _rng)
	_state.profiler.mark("projectiles")
	var morale_checked: bool = Morale.advance(_state, dt)
	if morale_checked:
		Reinforcements.release(_state, _state.active_counts, _rng, _state.side_factions)
	_tick += 1
	if _hero.dead:
		_outcome = Outcome.HERO_DOWN
	if morale_checked and _battle_over_at < 0.0 and (not _side_alive(0) or not _side_alive(1)):
		_battle_over_at = _elapsed_seconds
		_battle_won = _side_alive(0) and not _side_alive(1)
		_state.record_notice(Event.Kind.BATTLE_DECIDED, {"won": _battle_won})
	if _battle_over_at >= 0.0 and _elapsed_seconds - _battle_over_at > Config.BATTLE_END_DELAY_SECONDS:
		_outcome = Outcome.VICTORY if _battle_won else Outcome.DEFEAT
		_result = BattleResult.build(_state, _hero, _rng, _elapsed_seconds, _battle_won, _companion_survival)
	_events.append_array(_state.take_events())
	_state.profiler.mark("morale_result_events")
	if _state.pending_retirements > 0:
		_state.compact_inactive(_tick)
	_state.profiler.mark("storage_compaction")
	if _state.ai_trace != null and _schedule.commander_due(0, _tick):
		_refresh_assessment()

## Debug observation (ADR-022). Enabling starts the decision trace; the battle stays the same battle.
func set_ai_debug(enabled: bool) -> void:
	if enabled == (_state.ai_trace != null):
		return
	_state.ai_trace = DecisionTrace.new() if enabled else null
	_assessment = {}
	_assessment_tick = -1
	if enabled:
		_refresh_assessment()

func ai_debug_enabled() -> bool:
	return _state.ai_trace != null

## Detached plan, orders, modes, morale and last reasons; empty while debugging is off.
func ai_debug_snapshot() -> Dictionary:
	if _state.ai_trace == null:
		return {}
	return AiDebugSnapshot.build(_state, _state.ai_trace, _assessment, _assessment_tick, _ai_profiles, _tick, _elapsed_seconds)

func ai_profiles() -> Array[String]:
	return _ai_profiles.duplicate()

func _refresh_assessment() -> void:
	_assessment = FieldAssessment.assess(_state)
	_assessment_tick = _tick

func result() -> Dictionary:
	return _result.duplicate(true)

func request_weapon_slot(slot: String) -> bool:
	if _outcome != Outcome.RUNNING or _hero.dead or _hero.gone or _weapon_names.get(slot, "").is_empty():
		return false
	if _hero.hero_weapon.get("slot") == slot:
		return false
	_requested_slot = slot
	_slot_request_ticks = Config.HERO_SLOT_REQUEST_TICKS
	return true

func request_retreat() -> bool:
	if _battle_over_at >= 0.0 or _retreat_requested:
		return false
	_retreat_requested = true
	return true

func companion_dialogue() -> Dictionary:
	return _companion_dialogue.duplicate(true)

func vegetation_layout() -> Array[Dictionary]:
	var plants: Array[Dictionary] = []
	for plant in _state.plants:
		plants.append(plant.to_dictionary())
	return plants

## Transfers all unconsumed events once, including every catch-up tick.
func take_events() -> Array[Dictionary]:
	var batch := _events
	_events = []
	return batch

func _handle_swap() -> void:
	var pressed: bool = bool(_input.get("swap", false))
	var requested := pressed and not _swap_held
	_swap_held = pressed
	if _gear_catalog == null or _hero_profile.is_empty() or _hero.dead or _hero.gone:
		return
	if _slot_request_ticks > 0:
		_slot_request_ticks -= 1
		if _hero.attack_windup < 0.0:
			_slot_request_ticks = 0
			if _hero.hero_weapon.get("slot") != _requested_slot:
				_equip_weapon(_requested_slot)
			return
	if not requested or _hero.attack_windup >= 0.0:
		return
	var selection := WEAPON_SLOT_MELEE if _hero.hero_weapon.get("slot") == WEAPON_SLOT_RANGED else WEAPON_SLOT_RANGED
	_equip_weapon(selection)

func _equip_weapon(selection: String) -> void:
	var candidate := _hero_profile.duplicate(true)
	candidate.sel = selection
	var gear := HeroGear.resolve(candidate, _gear_catalog)
	if gear.is_empty():
		return
	if selection == WEAPON_SLOT_RANGED and gear.weapon.get("slot") != WEAPON_SLOT_RANGED:
		_state.record_notice(Event.Kind.RANGED_WEAPON_UNAVAILABLE, {"position": _hero.position})
		return
	if HeroStats.apply(_hero, candidate, gear, false):
		_hero_profile = candidate
		_hero.attack_cooldown = maxf(_hero.attack_cooldown, Config.HERO_SWAP_COOLDOWN_FLOOR)
		_state.record_notice(Event.Kind.WEAPON_SWAPPED, {"position": _hero.position, "weapon_name": gear.weapon.name, "target_id": _hero.id})

func _side_alive(side: int) -> bool:
	for unit: Unit in _state.active_units:
		if unit.side == side and not unit.dead and not unit.gone and not unit.fleeing:
			return true
	return false

## A detached presentation identity map; no visual random state enters simulation/snapshot hashes.
func unit_appearance_ids() -> Dictionary:
	var ids := {}
	for unit: Unit in _state.units:
		if not unit.hero and not unit.companion: ids[unit.id] = unit.troop_id
	return ids

## Read-only presentation query; does not change simulation snapshots or consume battle RNG.
func hero_swing_state() -> Dictionary:
	return {"position": _hero.position, "dead": _hero.dead, "remaining": _hero.swing_timer,
		"facing": _hero.swing_facing, "reach": _hero.melee_reach, "mounted": _hero.mounted}

## Read-only presentation query; does not change simulation snapshots or consume battle RNG.
func selected_orders(selection: int) -> Array[String]:
	var orders: Array[String] = []
	for group in _state.groups[0]:
		if selection != Config.ALL_GROUPS and group.kind != selection: continue
		if not group.has_active_units(): continue
		var order: String = Config.ORDER_RETREAT if group.backing else group.order
		if not orders.has(order): orders.append(order)
	return orders

func snapshot(compact: bool = false) -> Dictionary:
	# Detached values: presentation cannot mutate simulation through this query.
	var units: Array[Dictionary] = []
	var counts := [0, 0]
	var focus_sum := [Vector2.ZERO, Vector2.ZERO]
	var focus_count := [0, 0]
	var enemy_strength := 0.0
	var ally_strength := 0.0
	var group_strength := PackedFloat64Array()
	group_strength.resize(Config.GROUP_KINDS)
	var positions := _state.motion.positions
	if _state.column_backend != null:
		var summary: Array = _state.column_backend.summary(_state.motion)
		counts = summary[0]
		focus_sum = summary[1]
		focus_count = summary[2]
		enemy_strength = summary[3]
		ally_strength = summary[4]
		group_strength = summary[5]
	else:
		for unit: Unit in _state.active_units:
			if not unit.dead and not unit.gone:
				counts[unit.side] += 1
				if not unit.fleeing:
					focus_sum[unit.side] += positions[unit.battle_index]
					focus_count[unit.side] += 1
					if unit.side == 1:
						enemy_strength += unit.weight
					else:
						ally_strength += unit.weight
						if not unit.hero and unit.command == Config.COMMAND_PLAYER and unit.group_kind >= 0 and unit.group_kind < Config.GROUP_KINDS:
							group_strength[unit.group_kind] += unit.weight
	if not compact:
		for unit: Unit in _state.units: units.append(_unit_values(unit))
	var camera_target := _camera_target(focus_sum, focus_count)
	var enemy_center: Vector2 = focus_sum[1] / focus_count[1] if focus_count[1] else Vector2.INF
	var ready_groups: Array[int] = []
	for weight in group_strength:
		ready_groups.append(roundi(weight))
	var frame := {"tick": _tick, "outcome": _outcome, "hero_down": _hero.dead, "arena_size": _state.arena_size, "hero_position": _hero.position, "camera_target": camera_target, "stamina": _hero.stamina, "counts": counts, "units": units, "shots": _shot_values(), "walls": _wall_rects(), "wall_defense": _wall_defense_values(), "player_groups": _player_group_values(),
		"enemy_center": enemy_center, "reserve": [_state.reserve[0].size(), _state.reserve[1].size()], "enemy_strength": roundi(enemy_strength), "decided": _battle_over_at >= 0.0,
		"hero_weapon_name": _hero.hero_weapon.get("name", ""), "elapsed_seconds": _elapsed_seconds,
		"ally_strength": roundi(ally_strength), "group_strength": ready_groups,
		"army_share": ally_strength / maxf(1.0, _starting_ally_strength),
		"hero_status": {"name": str(_hero_profile.get("name", "")), "hp": _hero.hp, "max_hp": _hero.max_hp,
			"armor": _hero.armor, "block": _hero.block_chance, "slot": _hero.hero_weapon.get("slot", ""),
			"weapon_names": _weapon_names.duplicate()}}
	if compact:
		frame.erase("units")
		frame.render = _render_snapshot()
	return frame

var _render_definitions: Array[Dictionary] = []
var _render_special_flags := PackedInt32Array()

func _render_snapshot() -> RenderSnapshot:
	var frame := RenderSnapshot.new()
	var positions := _state.motion.positions
	var velocities := _state.motion.velocities
	for i in range(_render_definitions.size(), _state.units.size()):
		_render_definitions.append(_render_definition(_state.units[i]))
		_render_special_flags.append(RenderSnapshot.COMPANION if _state.units[i].companion else 0)
	_render_definitions[_hero.history_index] = _render_definition(_hero)
	var visible := _state.render_units()
	if _state.column_backend != null:
		var packed: Array = _state.column_backend.render(_state.motion, _previous_positions, _render_special_flags, _render_definitions)
		frame._render_positions = packed[0].duplicate()
		frame._render_previous = packed[1]
		frame._render_sides = packed[2]
		frame._render_groups = packed[3]
		frame._render_flags = packed[4]
		frame._render_dynamic = packed[5]
		frame._render_ids = packed[7]
		frame._render_definitions = packed[8]
		if _hero.battle_index >= 0: frame._render_dynamic[_hero.battle_index * RenderSnapshot.STRIDE + 4] = _hero.attack_windup
		var histories: PackedInt32Array = packed[6]
		for unit: Unit in _state.retired_render_units:
			var row := histories.bsearch(unit.history_index)
			histories.insert(row, unit.history_index)
			_insert_retired_render_row(frame, unit, row)
		return frame
	var capacity := visible.size()
	var out_positions := PackedVector2Array()
	var previous := PackedVector2Array()
	var sides := PackedInt32Array()
	var groups := PackedInt32Array()
	var flags := PackedInt32Array()
	var dynamic := PackedFloat64Array()
	var definitions: Array[Dictionary] = []
	out_positions.resize(capacity)
	previous.resize(capacity)
	sides.resize(capacity)
	groups.resize(capacity)
	flags.resize(capacity)
	dynamic.resize(capacity * RenderSnapshot.STRIDE)
	definitions.resize(capacity)
	var row := 0
	# Dead ordinary soldiers leave the render stream. Their DOWN event owns corpse data.
	for unit: Unit in visible:
		if unit.gone or (unit.dead and not unit.hero and not unit.companion): continue
		var dense := unit.battle_index
		var history := unit.history_index
		var at := positions[dense] if dense >= 0 else unit.position
		definitions[row] = _render_definitions[history]
		frame._render_ids.append(unit.id)
		out_positions[row] = at
		previous[row] = at if history >= _previous_positions.size() or unit.retired_tick >= 0 and unit.retired_tick < _tick else _previous_positions[history]
		sides[row] = unit.side
		groups[row] = unit.group_kind
		flags[row] = (int(unit.dead) * RenderSnapshot.DEAD | int(unit.gone) * RenderSnapshot.GONE
			| int(unit.hero) * RenderSnapshot.HERO | int(unit.companion) * RenderSnapshot.COMPANION
			| int(unit.mounted) * RenderSnapshot.MOUNTED | int(unit.fleeing) * RenderSnapshot.FLEEING
			| int(unit.blocking) * RenderSnapshot.BLOCKING | int(unit.leader) * RenderSnapshot.LEADER)
		var offset := row * RenderSnapshot.STRIDE
		dynamic[offset] = unit.collision_radius
		dynamic[offset + 1] = clampf(unit.hp / unit.max_hp, 0.0, 1.0) if unit.max_hp > 0.0 else 0.0
		dynamic[offset + 2] = unit.facing
		dynamic[offset + 3] = velocities[dense].length() if dense >= 0 else unit.velocity.length()
		dynamic[offset + 4] = unit.attack_windup if unit.hero else unit.ai_windup
		row += 1
	if row < capacity:
		out_positions.resize(row)
		previous.resize(row)
		sides.resize(row)
		groups.resize(row)
		flags.resize(row)
		dynamic.resize(row * RenderSnapshot.STRIDE)
		definitions.resize(row)
	frame._render_positions = out_positions
	frame._render_previous = previous
	frame._render_sides = sides
	frame._render_groups = groups
	frame._render_flags = flags
	frame._render_dynamic = dynamic
	frame._render_definitions = definitions
	return frame

func _render_definition(unit: Unit) -> Dictionary:
	var definition := {"id": unit.id, "side": unit.side, "faction": unit.faction,
		"hero": unit.hero, "companion": unit.companion,
		"companion_name": unit.name if unit.companion else "", "look": unit.appearance.duplicate(true)}
	RenderSnapshot.freeze(definition)
	return definition

func _previous_position(unit: Unit) -> Vector2:
	if unit.retired_tick >= 0 and unit.retired_tick < _tick: return unit.position
	return _previous_positions[unit.history_index] if unit.history_index >= 0 and unit.history_index < _previous_positions.size() else unit.position

## Appearance copies are cached: only the hero changes looks (weapon swap), and a deep copy of every unit's look
## every frame was a large part of a mass battle's frame time.
var _looks := {}

func _look(unit: Unit) -> Dictionary:
	if unit.hero:
		return unit.appearance.duplicate(true)
	var cached = _looks.get(unit.id)
	if cached == null:
		cached = unit.appearance.duplicate(true)
		_looks[unit.id] = cached
	return cached.duplicate() # a shallow copy keeps every snapshot detached

var _templates := {}

## A fresh dictionary per unit and frame (snapshots stay detached), copied from a per-unit template of the
## fields that never change, which is much cheaper than building all of them every frame.
func _unit_values(unit: Unit) -> Dictionary:
	var template = _templates.get(unit.id)
	if template == null or unit.hero:
		template = {
			"id": unit.id, "position": unit.position, "radius": unit.collision_radius,
			"side": unit.side, "faction": unit.faction, "hero": unit.hero, "companion": unit.companion,
			"group_kind": unit.group_kind, "leader": unit.leader,
			"companion_name": unit.name if unit.companion else "",
			"health_fraction": 0.0, "dead": false, "gone": false, "mounted": unit.mounted, "fleeing": false,
			"facing": 0.0, "speed": 0.0, "blocking": false, "windup": 0.0, "look": {},
		}
		if not unit.hero:
			_templates[unit.id] = template
	var values: Dictionary = template.duplicate()
	values.position = unit.position
	values.previous_position = _previous_position(unit)
	values.radius = unit.collision_radius
	values.group_kind = unit.group_kind
	values.leader = unit.leader
	values.mounted = unit.mounted
	values.health_fraction = clampf(unit.hp / unit.max_hp, 0.0, 1.0) if unit.max_hp > 0.0 else 0.0
	values.dead = unit.dead
	values.gone = unit.gone
	values.fleeing = unit.fleeing
	values.facing = unit.facing
	values.speed = unit.velocity.length()
	values.blocking = unit.blocking
	values.windup = unit.attack_windup if unit.hero else unit.ai_windup
	values.look = _look(unit)
	return values

## Follows the hero; once the hero is down the camera shows the middle of the fighting.
func _camera_target(focus_sum: Array, focus_count: Array) -> Vector2:
	if not _hero.dead:
		return _hero.position
	if focus_count[0] > 0 and focus_count[1] > 0:
		return (focus_sum[0] / focus_count[0] + focus_sum[1] / focus_count[1]) / 2.0
	if focus_count[0] > 0:
		return focus_sum[0] / focus_count[0]
	if focus_count[1] > 0:
		return focus_sum[1] / focus_count[1]
	return Vector2.INF

func _shot_values() -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	for shot in _state.projectiles:
		shots.append({"origin": shot.origin, "impact": shot.impact, "progress": clampf(shot.time / shot.duration, 0.0, 1.0), "throwing": shot.throwing, "crossbow": shot.crossbow})
	return shots

## The player's groups for commandDraw: where a holding group was told to stand and where it actually is.
func _player_group_values() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	if _state.groups.is_empty():
		return values # A bare session without groups (tests, previews).
	for group in _state.groups[0]:
		values.append({"kind": group.kind, "order": group.order, "backing": group.backing, "center": group.center, "direction": group.direction, "centroid": group.centroid()})
	return values

func _wall_rects() -> Array[Rect2]:
	var walls: Array[Rect2] = []
	if _state.wall != null:
		walls = _state.wall.segments()
	return walls

func _wall_defense_values() -> Dictionary:
	if _state.siege_defense == null:
		return {}
	return {"wall_x": _state.wall.x, "stones_left": _state.siege_defense.stones,
		"stones": _state.siege_defense.stones_in_flight.map(func(s): return {"origin": s.origin, "impact": s.impact, "progress": clampf(s.time / s.duration, 0.0, 1.0)}),
		"fires": _state.siege_defense.fires.map(func(f): return {"center": f.center, "half_size": f.half_size, "time": f.time, "duration": f.duration, "pour_from": f.pour_from}),
		"cauldrons": _state.siege_defense.cauldrons.map(func(c): return {"gap": c.gap, "charged": c.charges > 0}),
		"half_width": _state.wall.half_width,
		"gates": _state.wall.gates.map(func(g): return {"gap": g.gap, "hp": g.hp, "max": g.max, "hit": g.hit, "dead": g.dead, "open": g.open})}

func _insert_retired_render_row(frame: RenderSnapshot, unit: Unit, row: int) -> void:
	var history := unit.history_index
	frame._render_positions.insert(row, unit.position)
	frame._render_previous.insert(row, _previous_position(unit))
	frame._render_sides.insert(row, unit.side)
	frame._render_groups.insert(row, unit.group_kind)
	frame._render_flags.insert(row, int(unit.dead) * RenderSnapshot.DEAD | int(unit.gone) * RenderSnapshot.GONE
		| int(unit.hero) * RenderSnapshot.HERO | int(unit.companion) * RenderSnapshot.COMPANION
		| int(unit.mounted) * RenderSnapshot.MOUNTED | int(unit.fleeing) * RenderSnapshot.FLEEING
		| int(unit.blocking) * RenderSnapshot.BLOCKING | int(unit.leader) * RenderSnapshot.LEADER)
	frame._render_ids.insert(row, unit.id)
	frame._render_definitions.insert(row, _render_definitions[history])
	var values := [unit.collision_radius, clampf(unit.hp / unit.max_hp, 0.0, 1.0) if unit.max_hp > 0.0 else 0.0,
		unit.facing, unit.velocity.length(), unit.attack_windup if unit.hero else unit.ai_windup]
	for field in range(RenderSnapshot.STRIDE - 1, -1, -1): frame._render_dynamic.insert(row * RenderSnapshot.STRIDE, values[field])
