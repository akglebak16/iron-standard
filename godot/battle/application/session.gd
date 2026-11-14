extends RefCounted
const Morale = preload("res://battle/rules/morale.gd")
const CombatStep = preload("res://battle/rules/combat_step.gd")
const Movement = preload("res://battle/rules/movement.gd")
const Tactics = preload("res://battle/rules/tactics.gd")
## Single writer for a running battle. No SceneTree, Input, files or translated text.
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const HeroInput = preload("res://battle/application/hero_input.gd")
const HeroControl = preload("res://battle/rules/hero_control.gd")
const Config = preload("res://battle/config.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const HeroGear = preload("res://equipment/rules/hero_gear.gd")
const HeroStats = preload("res://battle/data/hero_stats.gd")
const BattleResult = preload("res://battle/rules/result.gd")
const Event = preload("res://battle/combat_event.gd")
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
			_state.record_notice(Event.Kind.ORDER_APPLIED, {"order": command.order, "selection": command.selection})
	_orders.clear()
	_elapsed_seconds += dt
	if _state.wall == null:
		Tactics.enemy_step(_state, 1, _elapsed_seconds, dt)
	else:
		Tactics.siege_step(_state, _elapsed_seconds)
	Tactics.follow_hero(_state, _hero)
	Tactics.relayout(_state, dt)
	_handle_swap()
	HeroControl.step(_state, _hero, _input, dt, _rng)
	Movement.step(_state, dt, _rng)
	CombatStep.resolve_projectiles(_state, dt, _rng)
	var morale_checked: bool = Morale.advance(_state, dt)
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
	if pressed and not _swap_held and _gear_catalog != null and not _hero_profile.is_empty() and _hero.attack_windup < 0.0:
		var selection := "melee" if _hero_profile.get("sel", "melee") == "ranged" else "ranged"
		var candidate: Dictionary = _hero_profile.duplicate(true)
		candidate.sel = selection
		var gear: Dictionary = HeroGear.resolve(candidate, _gear_catalog)
		if not gear.is_empty() and (selection == "melee" or gear.weapon.get("slot") == "ranged") and HeroStats.apply(_hero, candidate, gear, false):
			_hero_profile = candidate
			_hero.attack_cooldown = maxf(_hero.attack_cooldown, Config.HERO_SWAP_COOLDOWN_FLOOR)
	_swap_held = pressed

func _side_alive(side: int) -> bool:
	for unit: Unit in _state.units:
		if unit.side == side and not unit.dead and not unit.gone and not unit.fleeing:
			return true
	return false

func snapshot() -> Dictionary:
	# Detached values: presentation cannot mutate simulation through this query.
	var units: Array[Dictionary] = []
	var counts := [0, 0]
	var focus_sum := [Vector2.ZERO, Vector2.ZERO]
	var focus_count := [0, 0]
	for unit: Unit in _state.units:
		if not unit.dead and not unit.gone:
			counts[unit.side] += 1
			if not unit.fleeing:
				focus_sum[unit.side] += unit.position
				focus_count[unit.side] += 1
		units.append({
			"id": unit.id, "position": unit.position, "radius": unit.collision_radius,
			"side": unit.side, "faction": unit.faction, "hero": unit.hero, "companion": unit.companion,
			"group_kind": unit.group_kind, "leader": unit.leader,
			"companion_name": unit.name if unit.companion else "",
			"health_fraction": clampf(unit.hp / unit.max_hp, 0.0, 1.0) if unit.max_hp > 0.0 else 0.0,
			"dead": unit.dead, "gone": unit.gone, "mounted": unit.mounted, "fleeing": unit.fleeing,
			"facing": unit.facing, "speed": unit.velocity.length(), "blocking": unit.blocking,
			"windup": unit.attack_windup if unit.hero else unit.ai_windup,
			"look": unit.appearance.duplicate(true),
		})
	var camera_target: Vector2 = _hero.position
	if _hero.dead:
		if focus_count[0] > 0 and focus_count[1] > 0:
			camera_target = (focus_sum[0] / focus_count[0] + focus_sum[1] / focus_count[1]) / 2.0
		elif focus_count[0] > 0:
			camera_target = focus_sum[0] / focus_count[0]
		elif focus_count[1] > 0:
			camera_target = focus_sum[1] / focus_count[1]
	var shots: Array[Dictionary] = []
	for shot in _state.projectiles:
		shots.append({"origin": shot.origin, "impact": shot.impact, "progress": clampf(shot.time / shot.duration, 0.0, 1.0), "throwing": shot.throwing, "crossbow": shot.crossbow})
	var walls: Array[Rect2] = []
	if _state.wall != null:
		walls = _state.wall.segments()
	return {"tick": _tick, "outcome": _outcome, "hero_down": _hero.dead, "arena_size": _state.arena_size, "hero_position": _hero.position, "camera_target": camera_target, "stamina": _hero.stamina, "counts": counts, "units": units, "shots": shots, "walls": walls}
