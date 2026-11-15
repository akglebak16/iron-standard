extends RefCounted
const Morale = preload("res://battle/rules/morale.gd")
const CombatStep = preload("res://battle/rules/combat_step.gd")
const Movement = preload("res://battle/rules/movement.gd")
const Tactics = preload("res://battle/rules/tactics.gd")
const SiegeDefense = preload("res://battle/rules/siege_defense.gd")
## Single writer for a running battle. No SceneTree, Input, files or translated text.
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const HeroInput = preload("res://battle/application/hero_input.gd")
const HeroControl = preload("res://battle/rules/hero_control.gd")
const Config = preload("res://battle/config.gd")
const NativeSwitch = preload("res://battle/rules/native_switch.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const HeroGear = preload("res://equipment/rules/hero_gear.gd")
const HeroStats = preload("res://battle/data/hero_stats.gd")
const BattleResult = preload("res://battle/rules/result.gd")
const Event = preload("res://battle/combat_event.gd")
const Reinforcements = preload("res://battle/data/reinforcements.gd")
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

func _init(state: State, hero: Unit, rng: RandomNumberGenerator, gear_catalog: GearCatalog = null, hero_profile: Dictionary = {}, companion_survival: float = 0.0, companion_dialogue: Dictionary = {}) -> void:
	assert(state != null and hero != null and rng != null)
	assert(hero.hero and hero in state.units)
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
	if _state.wall == null:
		Tactics.enemy_step(_state, 1, _elapsed_seconds, dt)
	else:
		Tactics.siege_step(_state, _elapsed_seconds)
		SiegeDefense.step(_state, dt, _rng)
	Tactics.follow_hero(_state, _hero)
	Tactics.relayout(_state, dt)
	_handle_swap()
	HeroControl.step(_state, _hero, _input, dt, _rng)
	Movement.step(_state, dt, _rng)
	CombatStep.resolve_projectiles(_state, dt, _rng)
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
	_events = _state.take_events()

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

## Transfers the most recent tick's events once. Advance replaces unread events.
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
	for unit: Unit in _state.units:
		if unit.side == side and not unit.dead and not unit.gone and not unit.fleeing:
			return true
	return false

## live: for the battle view, which draws fighters from "render"; ordinary fighters' dictionaries may then be
## reused from an earlier frame with stale moving fields (BattleCore.frame_values). Native path only.
func snapshot(live := false) -> Dictionary:
	# Detached values: presentation cannot mutate simulation through this query.
	var units: Array[Dictionary] = []
	var counts := [0, 0]
	var focus_sum := [Vector2.ZERO, Vector2.ZERO]
	var focus_count := [0, 0]
	var enemy_strength := 0.0
	var ally_strength := 0.0
	var group_strength := PackedFloat64Array()
	group_strength.resize(Config.GROUP_KINDS)
	var render := PackedFloat64Array()
	if NativeSwitch.on:
		var stats: Array = BattleCore.frame_stats(_state.units, Config.GROUP_KINDS)
		counts = stats[0]
		focus_sum = stats[1]
		focus_count = stats[2]
		enemy_strength = stats[3]
		ally_strength = stats[4]
		group_strength = stats[5]
		_sync_templates()
		if live:
			units.assign(BattleCore.frame_values(_state.units, _template_list, _look_list, _frame_cache, _frame_kinds))
		else:
			units.assign(BattleCore.unit_values(_state.units, _template_list, _look_list))
		render = BattleCore.render_data(_state.units)
	else:
		for unit: Unit in _state.units:
			if not unit.dead and not unit.gone:
				counts[unit.side] += 1
				if not unit.fleeing:
					focus_sum[unit.side] += unit.position
					focus_count[unit.side] += 1
					if unit.side == 1:
						enemy_strength += unit.weight
					else:
						ally_strength += unit.weight
						if not unit.hero and unit.group_kind >= 0 and unit.group_kind < Config.GROUP_KINDS:
							group_strength[unit.group_kind] += unit.weight
			units.append(_unit_values(unit))
	var camera_target := _camera_target(focus_sum, focus_count)
	var enemy_center: Vector2 = focus_sum[1] / focus_count[1] if focus_count[1] else Vector2.INF
	var ready_groups: Array[int] = []
	for weight in group_strength:
		ready_groups.append(roundi(weight))
	return {"tick": _tick, "outcome": _outcome, "hero_down": _hero.dead, "arena_size": _state.arena_size, "hero_position": _hero.position, "camera_target": camera_target, "stamina": _hero.stamina, "counts": counts, "units": units, "render": render, "shots": _shot_values(), "walls": _wall_rects(), "wall_defense": _wall_defense_values(),
		"enemy_center": enemy_center, "reserve": [_state.reserve[0].size(), _state.reserve[1].size()], "enemy_strength": roundi(enemy_strength), "decided": _battle_over_at >= 0.0,
		"hero_weapon_name": _hero.hero_weapon.get("name", ""), "elapsed_seconds": _elapsed_seconds,
		"ally_strength": roundi(ally_strength), "group_strength": ready_groups,
		"army_share": ally_strength / maxf(1.0, _starting_ally_strength),
		"hero_status": {"name": str(_hero_profile.get("name", "")), "hp": _hero.hp, "max_hp": _hero.max_hp,
			"armor": _hero.armor, "block": _hero.block_chance, "slot": _hero.hero_weapon.get("slot", ""),
			"weapon_names": _weapon_names.duplicate()}}

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
var _template_list: Array = [] # per State.units index, for the native snapshot
var _look_list: Array = []
var _frame_cache: Array = [] # BattleCore.frame_values: unit dictionaries by index and the kind each was made for
var _frame_kinds: Array = []

## Keeps the per-unit templates and looks the native snapshot copies; the hero's are rebuilt every frame.
func _sync_templates() -> void:
	var units := _state.units
	for i in range(_template_list.size(), units.size()):
		var unit: Unit = units[i]
		_template_list.append(_template(unit))
		_look_list.append(unit.appearance.duplicate(true))
	for i in units.size():
		var unit: Unit = units[i]
		if unit.hero:
			_template_list[i] = _template(unit)
			_look_list[i] = unit.appearance.duplicate(true)

func _template(unit: Unit) -> Dictionary:
	return {
		"id": unit.id, "position": unit.position, "radius": unit.collision_radius,
		"side": unit.side, "faction": unit.faction, "hero": unit.hero, "companion": unit.companion,
		"group_kind": unit.group_kind, "leader": unit.leader,
		"companion_name": unit.name if unit.companion else "",
		"health_fraction": 0.0, "dead": false, "gone": false, "mounted": unit.mounted, "fleeing": false,
		"facing": 0.0, "speed": 0.0, "blocking": false, "windup": 0.0, "look": {},
	}

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
		"cauldrons": _state.siege_defense.cauldrons.map(func(c): return {"gap": c.gap, "charged": c.charges > 0})}
