extends RefCounted
const Morale = preload("res://battle/rules/morale.gd")
const CombatStep = preload("res://battle/rules/combat_step.gd")
const Movement = preload("res://battle/rules/movement.gd")
## Single writer for a running battle. No SceneTree, Input, files or translated text.
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const HeroInput = preload("res://battle/application/hero_input.gd")
const HeroControl = preload("res://battle/rules/hero_control.gd")
const Config = preload("res://battle/config.gd")
enum Outcome { RUNNING, HERO_DOWN, VICTORY, DEFEAT }

var _state: State
var _hero: Unit
var _rng: RandomNumberGenerator
var _input: Dictionary = {}
var _orders: Array[Dictionary] = []
var _outcome: Outcome = Outcome.RUNNING
var _tick: int = 0

func _init(state: State, hero: Unit, rng: RandomNumberGenerator) -> void:
	assert(state != null and hero != null and rng != null)
	assert(hero.hero and hero in state.units)
	_state = state
	_hero = hero
	_rng = rng

func set_hero_input(input: HeroInput) -> bool:
	if _outcome != Outcome.RUNNING or input == null or not input.move.is_finite() or not is_finite(input.face):
		return false
	_input = input.to_dictionary()
	return true

func issue_order(order: String, point: Vector2, selection: int) -> bool:
	if _outcome != Outcome.RUNNING or not point.is_finite() or selection < 0 or selection > Config.ALL_GROUPS:
		return false
	if order not in [Config.ORDER_HOLD, Config.ORDER_FOLLOW, Config.ORDER_CHARGE, Config.ORDER_RETREAT]:
		return false
	_orders.append({"order": order, "point": point, "selection": selection})
	return true

func advance(dt: float) -> void:
	if _outcome != Outcome.RUNNING or not is_finite(dt) or dt <= 0.0:
		return
	for command in _orders:
		_state.give_order(command.order, command.point, command.selection)
	_orders.clear()
	HeroControl.step(_state, _hero, _input, dt, _rng)
	var spatial_index = Movement.step(_state, dt, _hero.position, _hero.facing)
	CombatStep.step(_state, dt, _rng, spatial_index)
	Morale.advance(_state, dt)
	_tick += 1
	# Preserve preview behavior; full original post-battle rules are tracked in PARITY.md.
	if _hero.dead:
		_outcome = Outcome.HERO_DOWN
	elif not _side_alive(1):
		_outcome = Outcome.VICTORY
	elif not _side_alive(0):
		_outcome = Outcome.DEFEAT

func _side_alive(side: int) -> bool:
	for unit: Unit in _state.units:
		if unit.side == side and not unit.dead and not unit.gone and not unit.fleeing:
			return true
	return false

func snapshot() -> Dictionary:
	# Detached values: presentation cannot mutate simulation through this query.
	var units: Array[Dictionary] = []
	var counts := [0, 0]
	for unit: Unit in _state.units:
		if not unit.dead and not unit.gone:
			counts[unit.side] += 1
		units.append({"position": unit.position, "radius": unit.collision_radius, "side": unit.side, "hero": unit.hero, "dead": unit.dead, "gone": unit.gone})
	var shots: Array[Vector2] = []
	for shot in _state.projectiles:
		shots.append(shot.impact)
	return {"tick": _tick, "outcome": _outcome, "arena_size": _state.arena_size, "hero_position": _hero.position, "stamina": _hero.stamina, "counts": counts, "units": units, "shots": shots}
