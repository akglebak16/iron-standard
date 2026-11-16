extends SceneTree
## Stage 1a-archers (DESIGN.md 4.4, decision 15): a shooter does not join a target that already has enough shooters
## (hp / (damage x TARGET_VOLLEY_HIT_SHARE)) and spreads his fire over the front ranks by a fixed share from his id and
## the target's id. Synthetic units with unrelated IDs, both sides, foot and mounted shooters, plain scan and spatial
## index, the per-tick aimer count of Movement, and melee fighters untouched.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Targeting = preload("res://core/battle/rules/targeting.gd")
const SpatialIndex = preload("res://core/battle/rules/spatial_index.gd")
const Movement = preload("res://core/battle/rules/movement.gd")

func _initialize() -> void:
	_check_front_share()
	for side in 2:
		for mounted in [false, true]:
			_check_overkill(side, mounted)
			_check_front_ranks(side, mounted)
	_check_melee_untouched()
	_check_refresh_counts()
	_check_tick_counts()
	print("Archer fire tests passed")
	quit(0)

func _unit(state: State, id: int, side: int, at: Vector2, hp: float = 100.0) -> Unit:
	var unit := Unit.new(id, side, at, hp, 0, 1)
	unit.speed = 50.0
	assert(state.add_unit(unit))
	return unit

func _shooter(state: State, id: int, side: int, at: Vector2, mounted := false) -> Unit:
	var unit := _unit(state, id, side, at)
	unit.attack_range = 700.0
	unit.damage = 10.0
	unit.mounted = mounted
	return unit

## Both searches must agree; returns their choice.
func _choose(state: State, fighter: Unit) -> Unit:
	var plain := Targeting.choose(state, fighter)
	var index := SpatialIndex.new(state.active_units, state.arena_size, state.motion)
	var indexed := index.best_target(fighter, Targeting.current(state, fighter))
	assert(plain == indexed, "plain scan and spatial index disagree")
	return plain

func _check_front_share() -> void:
	var seen := {}
	for own in [3, 17, 4091, 70001]:
		for enemy in range(200, 260):
			var share := SpatialIndex.front_share(own, enemy)
			assert(share >= 0.0 and share < 1.0)
			assert(share == SpatialIndex.front_share(own, enemy), "the share is fixed for a pair")
			seen[share] = true
	assert(seen.size() > 150, "different pairs get different shares, got %d" % seen.size())
	assert(SpatialIndex.front_share(-5, 12) >= 0.0, "negative IDs stay in range")

## Needed shooters for hp 35 and damage 10: 35 / (10 x 0.35) = 10. The tenth is not surplus, the eleventh is.
func _check_overkill(side: int, mounted: bool) -> void:
	var state := State.new()
	var foe := 1 - side
	var base := Vector2(700, 600)
	var shooter := _shooter(state, 5017, side, base, mounted)
	var doomed := _unit(state, 913, foe, base + Vector2(300, 0), 35.0)
	var spare := _unit(state, 64, foe, base + Vector2(0, 420))
	var needed := doomed.hp / (shooter.damage * Config.TARGET_VOLLEY_HIT_SHARE)
	assert(is_equal_approx(needed, 10.0))
	doomed.aimers = 9
	assert(_choose(state, shooter) == doomed, "the shooter who completes the volley still joins it")
	doomed.aimers = 13 # 300 x (1 + 0.5 x 4) = 900 > 420 x 1.15.
	assert(_choose(state, shooter) == spare, "a target with enough shooters looks farther away")
	# The shooter himself is not counted among the aimers of his own target.
	shooter.target_handle = doomed.unit_handle
	doomed.aimers = 10
	assert(_choose(state, shooter) == doomed, "his own aim does not push his target away")
	# A wounded man needs fewer arrows.
	shooter.target_handle = 0
	doomed.aimers = 4
	assert(_choose(state, shooter) == doomed)
	doomed.hp = 7.0 # Needs 2: four aimers plus him are three surplus, 300 x 2.5 = 750 > 483.
	assert(_choose(state, shooter) == spare, "a nearly dead target needs fewer shooters")
	# Without damage there is no estimate and no overkill rule.
	shooter.damage = 0.0
	assert(_choose(state, shooter) == doomed)

## A line of equally close enemies and a rear rank: shooters spread over the front line and do not shoot past it.
func _check_front_ranks(side: int, mounted: bool) -> void:
	var state := State.new()
	var foe := 1 - side
	var sign := 1.0 if side == 0 else -1.0
	var front: Array[Unit] = []
	var rear: Array[Unit] = []
	for k in 8:
		front.append(_unit(state, 3000 + k * 7, foe, Vector2(1300 + sign * 400, 500 + k * 22)))
		rear.append(_unit(state, 5000 + k * 11, foe, Vector2(1300 + sign * 520, 500 + k * 22)))
	var chosen := {}
	var nearest := {}
	for k in 24:
		var shooter := _shooter(state, 200 + k * 13, side, Vector2(1300, 560 + (k % 4) * 6), mounted)
		var target := _choose(state, shooter)
		assert(target in front, "a shooter keeps to the front rank")
		chosen[target] = true
		nearest[Targeting.nearest_enemy(state, shooter)] = true
	assert(chosen.size() >= 4 and chosen.size() > nearest.size(), "fire spreads over the front: %d targets, %d nearest" % [chosen.size(), nearest.size()])
	# The current target stays sticky: the same shooter keeps it while the line stands.
	var shooter := _shooter(state, 9001, side, Vector2(1300, 570), mounted)
	var first := _choose(state, shooter)
	shooter.target_handle = first.unit_handle
	assert(_choose(state, shooter) == first)

## Melee fighters keep the stage 1a rules only: no overkill count and no front share.
func _check_melee_untouched() -> void:
	var state := State.new()
	var fighter := _unit(state, 71, 0, Vector2(800, 600))
	fighter.damage = 10.0
	var near := _unit(state, 72, 1, Vector2(850, 600), 5.0)
	var far := _unit(state, 73, 1, Vector2(800, 652))
	near.aimers = 500
	assert(_choose(state, fighter) == near, "aimers do not deter a melee fighter")
	assert(SpatialIndex.ranged_weight(10.0, 1, 0.0, far, false) >= 10.0, "the ranged weight never lowers a distance")

## Retargeting keeps the aimer counts of the tick current; melee and ranged counts stay apart.
func _check_refresh_counts() -> void:
	var state := State.new()
	var archer := _shooter(state, 4321, 0, Vector2(400, 400))
	var first := _unit(state, 88, 1, Vector2(430, 400))
	var second := _unit(state, 61, 1, Vector2(445, 400))
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	assert(Targeting.refresh(state, archer, 0.01, rng) == first)
	assert(first.aimers == 1 and second.aimers == 0 and first.attackers == 0)
	first.position = Vector2(1400, 400)
	assert(Targeting.refresh(state, archer, archer.target_timer, rng) == second)
	assert(first.aimers == 0 and second.aimers == 1)
	var fighter := _unit(state, 777, 0, Vector2(400, 420))
	assert(Targeting.refresh(state, fighter, 0.01, rng) == second)
	assert(second.aimers == 1 and second.attackers == 1, "a melee fighter counts as an attacker, not an aimer")

## The movement tick recounts the shooters of live targets for both sides before anyone moves.
func _check_tick_counts() -> void:
	var state := State.new()
	state.setup_groups()
	var shooters := []
	for i in 6:
		var unit := Unit.new(1000 + i * 37, 0, Vector2(500, 400 + i * 30), 100, 0, 1)
		unit.speed = 50.0
		unit.attack_range = 600.0
		unit.damage = 10.0
		state.add_grouped_unit(unit, Config.GROUP_ARCHERS)
		shooters.append(unit)
	var foe := Unit.new(9, 1, Vector2(900, 450), 100, 0, 1)
	foe.speed = 50.0
	state.add_grouped_unit(foe, Config.GROUP_INFANTRY)
	var rider := Unit.new(10, 1, Vector2(920, 520), 100, 0, 1)
	rider.speed = 120.0
	rider.mounted = true
	rider.attack_range = 500.0
	rider.damage = 12.0
	state.add_grouped_unit(rider, Config.GROUP_CAVALRY)
	for unit in shooters:
		unit.target_handle = foe.unit_handle
		unit.target_timer = 10.0
	shooters[0].attack_range = 0.0 # Melee: an attacker, not an aimer.
	shooters[1].fleeing = true # Fleeing: not counted.
	shooters[2].dead = true # Dead: not counted.
	rider.target_handle = shooters[3].unit_handle
	rider.target_timer = 10.0
	foe.aimers = 99 # Stale value from an earlier tick.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	Movement.step(state, 1.0 / 60.0, rng)
	assert(foe.aimers == 3, "three ready shooters target the foe, got %d" % foe.aimers)
	assert(foe.attackers == 1)
	assert(shooters[3].aimers == 1 and rider.aimers == 0, "a horse archer counts as a shooter")
