extends SceneTree
## Stage 1a (DESIGN.md 1.4 step 2): the leash of a charging melee fighter, measured from his place in a formation
## fitted around his group, and only in a chase (the target runs away from him). Soft leash: stop instead of
## running after a target that is still farther away; hard leash or too long a wait: walk back to his place; chase
## again only inside the return distance. Both sides, foot and mounted, synthetic units with unrelated IDs.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const AiDecision = preload("res://core/battle/rules/ai_decision.gd")
const Movement = preload("res://core/battle/rules/movement.gd")

const CENTER := Vector2(1300, 850)
const RUN_SPEED := 40.0 # Away from a fighter of speed 50: a chase from AI_CHARGE_CHASE_SPEED_SHARE (0.5) up.

func _initialize() -> void:
	for side in 2:
		_check_plan(side)
	_check_offset_and_mounted()
	_check_battle()
	print("Charge leash tests passed")
	quit(0)

func _setup(side: int) -> Array:
	var state := State.new()
	state.setup_groups()
	var group = state.groups[side][Config.GROUP_INFANTRY]
	group.order = Config.ORDER_CHARGE
	group.direction = 0.0
	var fighter := Unit.new(4321, side, CENTER, 100, 0, 1)
	fighter.speed = 50.0
	state.add_grouped_unit(fighter, Config.GROUP_INFANTRY)
	var foe := Unit.new(87, 1 - side, CENTER, 100, 0, 1)
	state.add_grouped_unit(foe, Config.GROUP_INFANTRY)
	return [state, group, fighter, foe]

## The foe runs straight away from the fighter at RUN_SPEED unless `run` is false.
func _plan(state: State, group, fighter: Unit, foe: Unit, at: Vector2, foe_at: Vector2, dt := 0.1, center := CENTER, run := true) -> void:
	fighter.position = at
	foe.position = foe_at
	foe.velocity = (foe_at - at).normalized() * RUN_SPEED if run else Vector2.ZERO
	AiDecision.plan_into(fighter, group, foe, state.arena_size, group.slot_position(fighter, state.arena_size), center, dt)

func _check_plan(side: int) -> void:
	var parts := _setup(side)
	var state: State = parts[0]
	var group = parts[1]
	var fighter: Unit = parts[2]
	var foe: Unit = parts[3]
	_plan(state, group, fighter, foe, CENTER + Vector2(100, 0), CENTER + Vector2(300, 0))
	assert(fighter.ai_mode == Config.AI_MODE_MELEE and fighter.plan_destination == foe.position, "inside the soft leash he charges")
	assert(fighter.chase_seconds == 0.0 and not fighter.leashed)
	var out := CENTER + Vector2(Config.AI_CHARGE_FOOT_SOFT_LEASH + 20.0, 0)
	_plan(state, group, fighter, foe, out, out + Vector2(150, 0))
	assert(fighter.ai_mode == Config.AI_MODE_SLOT and fighter.plan_destination == out, "beyond the soft leash he waits")
	assert(is_equal_approx(fighter.chase_seconds, 0.1))
	assert(fighter.plan_face == (foe.position - out).angle(), "waiting, he faces the target")
	_plan(state, group, fighter, foe, out, out + Vector2(150, 0), 0.1, CENTER, false)
	assert(fighter.ai_mode == Config.AI_MODE_MELEE, "a standing target is no chase: the formation may deform in a fight")
	fighter.chase_seconds = 0.0
	_plan(state, group, fighter, foe, out, CENTER + Vector2(60, 0))
	assert(fighter.ai_mode == Config.AI_MODE_MELEE, "a target back towards the group is still attacked")
	_plan(state, group, fighter, foe, out, out + Vector2(20, 0))
	assert(fighter.ai_mode == Config.AI_MODE_MELEE and fighter.plan_destination == out, "in contact he fights")
	# Waiting too long sends him back.
	fighter.chase_seconds = 0.0
	var steps := 0
	while not fighter.leashed:
		_plan(state, group, fighter, foe, out, out + Vector2(150, 0), 0.25)
		steps += 1
		assert(steps < 100)
	assert(steps * 0.25 > Config.AI_CHARGE_CHASE_SECONDS, "the wait lasts AI_CHARGE_CHASE_SECONDS")
	assert(fighter.ai_mode == Config.AI_MODE_SLOT and fighter.plan_destination == CENTER, "he walks back to his place")
	assert(fighter.chase_seconds == 0.0)
	# Hysteresis: back inside the soft leash he still returns, inside the return distance he may chase again.
	var halfway := CENTER + Vector2((Config.AI_CHARGE_FOOT_SOFT_LEASH + Config.AI_CHARGE_FOOT_RETURN_DISTANCE) * 0.5, 0)
	_plan(state, group, fighter, foe, halfway, halfway + Vector2(100, 0))
	assert(fighter.leashed and fighter.ai_mode == Config.AI_MODE_SLOT)
	_plan(state, group, fighter, foe, halfway, halfway + Vector2(20, 0))
	assert(fighter.leashed and fighter.ai_mode == Config.AI_MODE_MELEE, "returning, he still fights back in contact")
	var near := CENTER + Vector2(Config.AI_CHARGE_FOOT_RETURN_DISTANCE - 10.0, 0)
	_plan(state, group, fighter, foe, near, near + Vector2(100, 0))
	assert(not fighter.leashed and fighter.ai_mode == Config.AI_MODE_MELEE)
	# The hard leash sends him back at once, but only in a chase.
	var far := CENTER + Vector2(Config.AI_CHARGE_FOOT_HARD_LEASH + 10.0, 0)
	_plan(state, group, fighter, foe, far, far + Vector2(200, 0), 0.1, CENTER, false)
	assert(not fighter.leashed and fighter.ai_mode == Config.AI_MODE_MELEE)
	_plan(state, group, fighter, foe, far, far + Vector2(200, 0))
	assert(fighter.leashed and fighter.plan_destination == CENTER)
	# No leash without a charge, for ranged fighters and without a fitted centre; the state is cleared.
	group.order = Config.ORDER_HOLD
	_plan(state, group, fighter, foe, far, far + Vector2(60, 0))
	assert(not fighter.leashed and fighter.chase_seconds == 0.0)
	group.order = Config.ORDER_CHARGE
	_plan(state, group, fighter, foe, far, far + Vector2(200, 0), 0.1, Vector2.INF)
	assert(fighter.ai_mode == Config.AI_MODE_MELEE and not fighter.leashed)
	fighter.attack_range = 200.0
	_plan(state, group, fighter, foe, far, far + Vector2(400, 0))
	assert(fighter.ai_mode == Config.AI_MODE_SHOOT and not fighter.leashed)

func _check_offset_and_mounted() -> void:
	var parts := _setup(1)
	var state: State = parts[0]
	var group = parts[1]
	var fighter: Unit = parts[2]
	var foe: Unit = parts[3]
	fighter.slot_offset = Vector2(90, -40) # Lateral 90 is +y for direction 0; depth -40 is behind.
	var home := CENTER + Vector2(-40, 90)
	assert(group.formation_point(fighter.slot_offset, CENTER, state.arena_size) == home)
	assert(group.implied_center(fighter.slot_offset, home) == CENTER)
	var out := home + Vector2(0, Config.AI_CHARGE_FOOT_SOFT_LEASH + 20.0)
	_plan(state, group, fighter, foe, out, out + Vector2(0, 150))
	assert(fighter.ai_mode == Config.AI_MODE_SLOT, "the leash is measured from his own place")
	fighter.chase_seconds = 0.0
	fighter.mounted = true
	_plan(state, group, fighter, foe, out, out + Vector2(0, 150))
	assert(fighter.ai_mode == Config.AI_MODE_MELEE, "riders have the longer leash")
	var far := home + Vector2(0, Config.AI_CHARGE_MOUNTED_HARD_LEASH + 10.0)
	_plan(state, group, fighter, foe, far, far + Vector2(0, 150))
	assert(fighter.leashed and fighter.plan_destination == home)

## A whole tick: nine fighters that cannot move hold the group in place while the tenth runs after a fleeing foe
## who is faster. He stops near the soft leash, then walks back, and never goes beyond the hard leash.
func _check_battle() -> void:
	for side in 2:
		var state := State.new()
		state.setup_groups()
		var group = state.groups[side][Config.GROUP_INFANTRY]
		group.order = Config.ORDER_CHARGE
		var forward := 1.0 if side == 0 else -1.0
		group.direction = 0.0 if side == 0 else PI
		group.center = Vector2(700 if side == 0 else 1900, 850) # The runner has the rest of the field to run.
		var chaser: Unit = null
		for i in 10:
			var unit := Unit.new(300 + i * 11, side, Vector2.ZERO, 100, 0, 1)
			unit.speed = 0.0 if i < 9 else 55.0
			state.add_grouped_unit(unit, Config.GROUP_INFANTRY)
			if i == 9: chaser = unit
		group.layout(true)
		for unit in group.units:
			unit.position = group.slot_position(unit, state.arena_size)
		var runner := Unit.new(9001, 1 - side, chaser.position + Vector2(forward * 120.0, 0), 100, 0, 1)
		runner.speed = 140.0
		state.add_grouped_unit(runner, Config.GROUP_CAVALRY)
		state.groups[1 - side][Config.GROUP_CAVALRY].order = Config.ORDER_HOLD
		state.groups[1 - side][Config.GROUP_CAVALRY].center = runner.position + Vector2(forward * 1900.0, 0) # Clamped to the edge.
		var rng := RandomNumberGenerator.new()
		rng.seed = 31 + side
		var farthest := 0.0
		var waited := false
		var leashed_at := -1
		var came_back := false
		for tick in 900:
			Movement.step(state, 1.0 / 60.0, rng)
			var center: Vector2 = state.formation_centers[side * 3 + Config.GROUP_INFANTRY]
			var away := chaser.position.distance_to(group.formation_point(chaser.slot_offset, center, state.arena_size))
			farthest = maxf(farthest, away)
			if chaser.chase_seconds > 0.0: waited = true
			if chaser.leashed and leashed_at < 0: leashed_at = tick
			if leashed_at >= 0 and away < Config.AI_CHARGE_FOOT_RETURN_DISTANCE: came_back = true
		assert(chaser.target_handle == runner.unit_handle)
		assert(waited, "side %d: the chaser waits beyond the soft leash" % side)
		assert(leashed_at >= 0, "side %d: then walks back" % side)
		assert(came_back, "side %d: and reaches his place" % side)
		assert(farthest < Config.AI_CHARGE_FOOT_HARD_LEASH, "side %d: never beyond the hard leash (%.0f)" % [side, farthest])
		assert(runner.position.distance_to(chaser.position) > 300.0, "the runner got away")
