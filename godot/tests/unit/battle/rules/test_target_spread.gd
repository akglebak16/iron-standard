extends SceneTree
## Stage 1a (DESIGN.md 4.4, 1.4 step 2): a melee fighter weighs a crowded target and one that runs away faster
## than he can follow as farther away. Checked on synthetic units with unrelated IDs, for both sides, with the
## plain scan and the spatial index, and with the per-tick attacker count of Movement.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Targeting = preload("res://core/battle/rules/targeting.gd")
const SpatialIndex = preload("res://core/battle/rules/spatial_index.gd")
const Movement = preload("res://core/battle/rules/movement.gd")

func _initialize() -> void:
	for side in 2:
		_check_crowd(side)
		_check_outrun(side)
	_check_refresh_counts()
	_check_tick_counts()
	print("Target spread tests passed")
	quit(0)

func _unit(state: State, id: int, side: int, at: Vector2) -> Unit:
	var unit := Unit.new(id, side, at, 100, 0, 1)
	unit.speed = 50.0
	assert(state.add_unit(unit))
	return unit

## Both searches must agree; returns their choice.
func _choose(state: State, fighter: Unit) -> Unit:
	var plain := Targeting.choose(state, fighter)
	var index := SpatialIndex.new(state.active_units, state.arena_size, state.motion)
	var indexed := index.best_target(fighter, Targeting.current(state, fighter))
	assert(plain == indexed, "plain scan and spatial index disagree")
	return plain

func _check_crowd(side: int) -> void:
	var state := State.new()
	var foe := 1 - side
	var base := Vector2(800, 600)
	var fighter := _unit(state, 7031, side, base)
	var crowded := _unit(state, 9112, foe, base + Vector2(50, 0))
	var free := _unit(state, 4405, foe, base + Vector2(0, 80))
	crowded.attackers = int(Config.TARGET_CROWD_FREE_ATTACKERS)
	assert(_choose(state, fighter) == crowded, "the free attackers do not push a target away")
	crowded.attackers = int(Config.TARGET_CROWD_FREE_ATTACKERS) + 5 # 50 × (1 + 0.25 × 5) = 112.5 > 80.
	assert(_choose(state, fighter) == free, "a crowded target looks farther away")
	# The fighter himself is not counted among the attackers of his own target.
	fighter.target_handle = crowded.unit_handle
	crowded.attackers = int(Config.TARGET_CROWD_FREE_ATTACKERS) + 1
	assert(_choose(state, fighter) == crowded)
	# Archers do not crowd and are not deterred by a crowd.
	fighter.target_handle = 0
	crowded.attackers = 50
	fighter.attack_range = 200.0
	assert(_choose(state, fighter) == crowded, "a ranged fighter keeps the nearest target")
	# Mounted melee is a melee fighter too.
	fighter.attack_range = 0.0
	fighter.mounted = true
	assert(_choose(state, fighter) == free)

func _check_outrun(side: int) -> void:
	var state := State.new()
	var foe := 1 - side
	var base := Vector2(900, 700)
	var fighter := _unit(state, 15, side, base)
	var runner := _unit(state, 3, foe, base + Vector2(50, 0))
	var slow := _unit(state, 2077, foe, base + Vector2(0, -120))
	runner.velocity = Vector2(150, 0) # Away at 150 against own 50: 50 × (1 + 2 × 100 / 50) = 250 > 120.
	assert(_choose(state, fighter) == slow, "a target running away faster looks farther away")
	runner.velocity = Vector2(-150, 0)
	assert(_choose(state, fighter) == runner, "a target coming closer is not penalised")
	runner.velocity = Vector2(0, 150)
	assert(_choose(state, fighter) == runner, "running across is not running away")
	runner.velocity = Vector2(45, 0)
	assert(_choose(state, fighter) == runner, "a target he can catch is not penalised")
	fighter.speed = 200.0
	runner.velocity = Vector2(150, 0)
	assert(_choose(state, fighter) == runner, "a faster fighter can follow")
	fighter.speed = 50.0
	fighter.attack_range = 180.0
	assert(_choose(state, fighter) == runner, "an archer shoots whoever is nearest")

## Retargeting keeps the counts of the tick current: the old target loses an attacker, the new one gains one.
func _check_refresh_counts() -> void:
	var state := State.new()
	var fighter := _unit(state, 501, 0, Vector2(400, 400))
	var first := _unit(state, 88, 1, Vector2(430, 400))
	var second := _unit(state, 61, 1, Vector2(445, 400))
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	assert(Targeting.refresh(state, fighter, 0.01, rng) == first)
	assert(first.attackers == 1 and second.attackers == 0)
	first.position = Vector2(1400, 400)
	assert(Targeting.refresh(state, fighter, fighter.target_timer, rng) == second)
	assert(first.attackers == 0 and second.attackers == 1)
	var archer := _unit(state, 777, 0, Vector2(400, 420))
	archer.attack_range = 200.0
	assert(Targeting.refresh(state, archer, 0.01, rng) == second)
	assert(second.attackers == 1, "archers are not counted")

## The movement tick recounts melee attackers of live targets for both sides before anyone moves.
func _check_tick_counts() -> void:
	var state := State.new()
	state.setup_groups()
	var hero_side := []
	for i in 6:
		var unit := Unit.new(1000 + i * 37, 0, Vector2(500, 400 + i * 30), 100, 0, 1)
		unit.speed = 50.0
		state.add_grouped_unit(unit, Config.GROUP_INFANTRY)
		hero_side.append(unit)
	var foe := Unit.new(9, 1, Vector2(560, 450), 100, 0, 1)
	foe.speed = 50.0
	state.add_grouped_unit(foe, Config.GROUP_INFANTRY)
	var other := Unit.new(10, 1, Vector2(570, 520), 100, 0, 1)
	other.speed = 50.0
	state.add_grouped_unit(other, Config.GROUP_CAVALRY)
	for i in hero_side.size():
		hero_side[i].target_handle = foe.unit_handle
		hero_side[i].target_timer = 10.0
	hero_side[0].attack_range = 150.0 # Ranged: not counted.
	hero_side[1].fleeing = true # Fleeing: not counted.
	hero_side[2].dead = true # Dead: not counted.
	foe.target_handle = hero_side[3].unit_handle
	foe.target_timer = 10.0
	other.target_handle = hero_side[3].unit_handle
	other.target_timer = 10.0
	foe.attackers = 99 # Stale value from an earlier tick.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	Movement.step(state, 1.0 / 60.0, rng)
	assert(foe.attackers == 3, "three ready melee fighters target the foe, got %d" % foe.attackers)
	assert(hero_side[3].attackers == 2 and other.attackers == 0)
	var center: Vector2 = state.formation_centers[1 * 3 + Config.GROUP_CAVALRY]
	assert(center.is_finite(), "every group with ready fighters gets a fitted centre")
	assert(not state.formation_centers[1 * 3 + Config.GROUP_ARCHERS].is_finite(), "an empty group has none")
