extends SceneTree
## Stage 1b morale (DESIGN.md 4.5): steps of a fighter (steady, wavering, fleeing, rallied), what a wavering fighter
## does worse, blows and charges from the flank and rear, threat to a group from the field assessment, panic and the
## rally of an unpursued fugitive. Both sides, synthetic units with unrelated IDs.
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Morale = preload("res://core/battle/rules/morale.gd")
const AiDecision = preload("res://core/battle/rules/ai_decision.gd")
const Combat = preload("res://core/battle/rules/combat.gd")
const Block = preload("res://core/battle/rules/block.gd")
const Charge = preload("res://core/battle/rules/charge.gd")
const Damage = preload("res://core/battle/rules/damage.gd")
const Event = preload("res://core/battle/combat_event.gd")

const MIDDLE := Vector2(1300, 850)
const FAR := 1000.0 # Beyond AI_FIELD_THREAT_RADIUS and MORALE_PURSUIT_RADIUS: no threat, no pursuit.

func _initialize() -> void:
	for side in 2:
		_check_steps(side)
		_check_plan(side)
		_check_hit_direction(side)
		_check_rally(side)
		_check_pursuit(side)
	_check_effects()
	_check_charge_shock()
	_check_threat()
	_check_panic()
	print("Morale stage tests passed")
	quit(0)

static func _forward(side: int) -> Vector2:
	return Vector2.RIGHT if side == 0 else Vector2.LEFT

static func _state() -> State:
	var state := State.new()
	state.setup_groups()
	return state

static func _unit(state: State, id: int, side: int, at: Vector2, kind := Config.GROUP_INFANTRY) -> Unit:
	var unit := Unit.new(id, side, at, 100, 0, 1)
	unit.speed = 50.0
	unit.facing = _forward(side).angle()
	state.add_grouped_unit(unit, kind)
	return unit

static func _kinds(state: State, kind: Event.Kind) -> int:
	return state.take_events().filter(func(event): return event.kind == kind).size()

## Steady below MORALE_WAVER_SHARE of the base wavers, steady again only from MORALE_STEADY_SHARE; the notice goes out
## once; at zero he flees, no longer wavering, his morale clamped to [-MORALE_RALLY_SHARE of the base, 0].
func _check_steps(side: int) -> void:
	var state := _state()
	var unit := _unit(state, 913, side, MIDDLE)
	_unit(state, 27, 1 - side, MIDDLE + _forward(side) * FAR)
	var waver: float = unit.base_morale * Config.MORALE_WAVER_SHARE
	var steady: float = unit.base_morale * Config.MORALE_STEADY_SHARE
	unit.morale = waver - Config.MORALE_EVEN_RECOVERY - 1.0
	Morale.tick(state)
	assert(unit.wavering and not unit.fleeing)
	assert(_kinds(state, Event.Kind.WAVERED) == 1)
	# Even odds recover MORALE_EVEN_RECOVERY per check: below the steady threshold he keeps wavering.
	unit.morale = steady - Config.MORALE_EVEN_RECOVERY - 1.0
	Morale.tick(state)
	assert(unit.wavering, "hysteresis: still wavering under MORALE_STEADY_SHARE")
	unit.morale = steady - Config.MORALE_EVEN_RECOVERY + 0.5
	Morale.tick(state)
	assert(not unit.wavering, "steady again from MORALE_STEADY_SHARE")
	unit.morale = 3.0
	Morale.tick(state)
	assert(unit.wavering and _kinds(state, Event.Kind.WAVERED) == 0, "the notice goes out once per fighter")
	unit.morale = -80.0
	Morale.tick(state)
	assert(unit.fleeing and not unit.wavering)
	assert(unit.morale == -unit.base_morale * Config.MORALE_RALLY_SHARE, "a deep rout is clamped")
	assert(_kinds(state, Event.Kind.FLED) == 1)

## A wavering fighter in a loose charge stands his ground against a far enemy and fights a near one, slower; a steady one
## charges; a wavering archer approaches slower; a formed line keeps its own rules.
func _check_plan(side: int) -> void:
	var state := _state()
	var group = state.groups[side][Config.GROUP_INFANTRY]
	group.order = Config.ORDER_CHARGE
	group.direction = _forward(side).angle()
	var fighter := _unit(state, 5021, side, MIDDLE)
	var foe := _unit(state, 77, 1 - side, MIDDLE)
	var forward := _forward(side)
	var slot: Vector2 = group.slot_position(fighter, state.arena_size)
	for mounted in [false, true]:
		fighter.mounted = mounted
		var engage: float = Config.AI_MOUNTED_ENGAGE_DISTANCE if mounted else Config.AI_FOOT_ENGAGE_DISTANCE
		foe.position = MIDDLE + forward * (engage + 40.0)
		fighter.wavering = false
		AiDecision.plan_into(fighter, group, foe, state.arena_size, slot)
		assert(fighter.ai_mode == Config.AI_MODE_MELEE and fighter.plan_speed == 1.0, "a steady fighter charges")
		fighter.wavering = true
		AiDecision.plan_into(fighter, group, foe, state.arena_size, slot)
		assert(fighter.ai_mode == Config.AI_MODE_SLOT and fighter.plan_destination == fighter.position, "a wavering one stands")
		assert(is_equal_approx(fighter.plan_face, forward.angle()), "facing the enemy")
		foe.position = MIDDLE + forward * (engage - 20.0)
		AiDecision.plan_into(fighter, group, foe, state.arena_size, slot)
		assert(fighter.ai_mode == Config.AI_MODE_MELEE and fighter.plan_destination == foe.position)
		assert(fighter.plan_speed == Config.MORALE_WAVER_SPEED_MULTIPLIER, "and closes in slower")
	fighter.mounted = false
	# A wavering archer of a charging group closes in to shoot, slower.
	fighter.attack_range = 300.0
	foe.position = MIDDLE + forward * 500.0
	AiDecision.plan_into(fighter, group, foe, state.arena_size, slot)
	assert(fighter.ai_mode == Config.AI_MODE_SHOOT and fighter.plan_speed == Config.MORALE_WAVER_SPEED_MULTIPLIER)
	fighter.attack_range = 0.0
	# In a formed line the rear ranks wait in their ranks whatever their morale.
	group.formed = true
	fighter.slot_offset = Vector2(0, -2.0 * Config.AI_FORMATION_FRONT_DEPTH)
	foe.position = MIDDLE + forward * 200.0
	AiDecision.plan_into(fighter, group, foe, state.arena_size, slot)
	assert(fighter.ai_mode == Config.AI_MODE_RANK)

## Morale cost of a blow by the side it comes from: the group's facing while the group holds, the fighter's own facing
## in a loose charge.
func _check_hit_direction(side: int) -> void:
	var state := _state()
	var group = state.groups[side][Config.GROUP_INFANTRY]
	group.order = Config.ORDER_HOLD
	var forward := _forward(side)
	group.direction = forward.angle()
	var target := _unit(state, 640, side, MIDDLE)
	target.facing = forward.rotated(PI * 0.5).angle() # Turned to the side: the group's facing counts while it holds.
	var lateral := forward.rotated(PI * 0.5)
	assert(state.hit_morale_multiplier(target, MIDDLE + forward * 50.0) == 1.0)
	assert(state.hit_morale_multiplier(target, MIDDLE + lateral * 50.0) == Config.MORALE_FLANK_HIT_MULTIPLIER)
	assert(state.hit_morale_multiplier(target, MIDDLE - forward * 50.0) == Config.MORALE_REAR_HIT_MULTIPLIER)
	group.order = Config.ORDER_CHARGE
	assert(state.hit_morale_multiplier(target, MIDDLE + lateral * 50.0) == 1.0, "a loose charge: his own facing")
	group.formed = true
	assert(state.hit_morale_multiplier(target, MIDDLE + lateral * 50.0) == Config.MORALE_FLANK_HIT_MULTIPLIER, "a formed line: the group")
	# The same blow in State.hurt: from the rear it costs MORALE_REAR_HIT_MULTIPLIER times the morale.
	group.order = Config.ORDER_HOLD
	var front_source := _unit(state, 12, 1 - side, MIDDLE + forward * 30.0)
	var rear_source := _unit(state, 13, 1 - side, MIDDLE - forward * 30.0)
	var before := target.morale
	var amount := state.hurt(target, 20.0, front_source)
	var front_loss := before - target.morale
	before = target.morale
	assert(state.hurt(target, 20.0, rear_source) == amount)
	assert(is_equal_approx(before - target.morale, front_loss * Config.MORALE_REAR_HIT_MULTIPLIER))
	assert(is_equal_approx(front_loss, amount * Config.HIT_MORALE_PER_DAMAGE))

## A fleeing fighter nobody pursues recovers MORALE_ROUT_RECOVERY per check (more near an own leader) and turns back,
## wavering, at MORALE_RALLY_SHARE of his base; pursued, at the field edge, with the side collapsed or past the limit he does not.
func _check_rally(side: int) -> void:
	var forward := _forward(side)
	for leader_near in [false, true]:
		var state := _state()
		var fugitive := _unit(state, 3301, side, MIDDLE)
		for i in 6:
			_unit(state, 200 + i, side, MIDDLE - forward * 600.0 + Vector2(0, i * 30.0))
		_unit(state, 51, 1 - side, MIDDLE + forward * 400.0)
		if leader_near:
			var leader := _unit(state, 9, side, MIDDLE + Vector2(0, Config.MORALE_RALLY_LEADER_RADIUS - 20.0))
			leader.leader = true
			leader.base_morale = Config.LEADER_BASE_MORALE
			leader.morale = leader.base_morale
		fugitive.fleeing = true
		fugitive.morale = 0.0
		var recovery: float = Config.MORALE_ROUT_RECOVERY + (Config.MORALE_RALLY_LEADER_BONUS if leader_near else 0.0)
		var checks := ceili(fugitive.base_morale * Config.MORALE_RALLY_SHARE / recovery)
		for check in checks - 1:
			Morale.tick(state)
			assert(fugitive.fleeing and is_equal_approx(fugitive.morale, recovery * (check + 1)))
		state.take_events()
		Morale.tick(state)
		assert(not fugitive.fleeing and fugitive.wavering and fugitive.rallies == 1, "rallied after %d checks" % checks)
		assert(_kinds(state, Event.Kind.RALLIED) == 1)
		assert(state.groups[side][Config.GROUP_INFANTRY].active_units().has(fugitive), "back in his group")
		# Once is enough: a second flight is for good.
		fugitive.fleeing = true
		fugitive.morale = 0.0
		Morale.tick(state)
		assert(fugitive.fleeing and fugitive.morale == 0.0)
	# Pursued: an enemy within MORALE_PURSUIT_RADIUS stops the recovery.
	var state := _state()
	var fugitive := _unit(state, 3302, side, MIDDLE)
	for i in 6:
		_unit(state, 300 + i, side, MIDDLE - forward * 600.0 + Vector2(0, i * 30.0))
	_unit(state, 52, 1 - side, MIDDLE + forward * (Config.MORALE_PURSUIT_RADIUS - 10.0))
	fugitive.fleeing = true
	fugitive.morale = 0.0
	Morale.tick(state)
	assert(fugitive.morale == 0.0, "pursued: no recovery")
	# At the field edge he recovers but runs on.
	state.active_units[state.active_units.size() - 1].position = MIDDLE + forward * FAR
	fugitive.position = Vector2(Config.MORALE_RALLY_EDGE - 10.0 if side == 0 else state.arena_size.x - Config.MORALE_RALLY_EDGE + 10.0, MIDDLE.y)
	fugitive.morale = fugitive.base_morale * Config.MORALE_RALLY_SHARE
	Morale.tick(state)
	assert(fugitive.fleeing, "no rally at the field edge")
	# A collapsed side does not rally.
	fugitive.position = MIDDLE
	for i in 6:
		state.active_units[1 + i].dead = true
	Morale.tick(state)
	assert(fugitive.fleeing, "no rally while the side has collapsed")

## Wavering: blows and arrows MORALE_WAVER_DAMAGE_MULTIPLIER as strong, blocks MORALE_WAVER_BLOCK_MULTIPLIER as likely.
func _check_effects() -> void:
	var losses := []
	for wavering in [false, true]:
		var state := _state()
		var attacker := _unit(state, 61, 0, MIDDLE)
		var target := _unit(state, 62, 1, MIDDLE + Vector2(20, 0))
		target.hp = 10000.0
		target.max_hp = 10000.0
		attacker.damage = 400.0
		attacker.wavering = wavering
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var before := target.hp
		Combat.strike(state, attacker, target, rng)
		losses.append(before - target.hp)
		attacker.attack_range = 200.0
		var shot := Combat.shoot(attacker, target, rng)
		assert(shot.damage == 400.0 * (Config.MORALE_WAVER_DAMAGE_MULTIPLIER if wavering else 1.0))
	assert(absf(losses[1] - losses[0] * Config.MORALE_WAVER_DAMAGE_MULTIPLIER) <= 1.0, "a wavering blow: %s" % str(losses))
	var state := _state()
	var target := _unit(state, 63, 1, MIDDLE)
	target.block_chance = 0.9
	var blocks := [0, 0]
	for wavering in [0, 1]:
		target.wavering = wavering == 1
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for trial in 2000:
			if Block.check(target, target.facing, false, rng): blocks[wavering] += 1
	assert(blocks[1] < blocks[0] * 0.9 and blocks[1] > blocks[0] * 0.7, "a wavering fighter blocks less: %s" % str(blocks))

## A cavalry charge shakes its victim (MORALE_CHARGE_SHOCK on top of the blow), but not a spearman meeting it face on.
func _check_charge_shock() -> void:
	for spear in [false, true]:
		var state := _state()
		state.groups[1][Config.GROUP_INFANTRY].direction = PI
		var rider := _unit(state, 71, 0, MIDDLE - Vector2(30, 0), Config.GROUP_CAVALRY)
		rider.mounted = true
		rider.damage = 30.0
		rider.velocity = Vector2(150, 0)
		var target := _unit(state, 72, 1, MIDDLE)
		target.hp = 1000.0
		target.max_hp = 1000.0
		target.anti_cavalry = spear
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var morale := target.morale
		var hp := target.hp
		Charge.hit(state, rider, target, rng)
		var blow := (morale - target.morale) - (hp - target.hp) * Config.HIT_MORALE_PER_DAMAGE
		assert(is_equal_approx(blow, 0.0 if spear else Config.MORALE_CHARGE_SHOCK), "charge shock %s: %f" % [spear, blow])

## Threat from the field assessment: an enemy squad twice as strong on the flank or in the rear costs morale every check,
## the same squad in front does not, an overwhelming one in front does. In a loose charge the front is where the men
## look, not the heading of the order.
func _check_threat() -> void:
	var losses := {}
	for where in ["front", "flank", "rear", "crushing", "loose"]:
		var state := _state()
		var own = state.groups[0][Config.GROUP_INFANTRY]
		own.direction = 0.0
		for i in 10:
			var man := _unit(state, 1000 + i, 0, Vector2(800, 800 + i * 10))
			if where == "loose": man.facing = PI * 0.5 # Turned to the enemy on the flank of the order's heading.
		if where == "loose": own.order = Config.ORDER_CHARGE
		var offset: Vector2 = {"front": Vector2(250, 0), "flank": Vector2(0, 250), "rear": Vector2(-250, 0), "crushing": Vector2(250, 0), "loose": Vector2(0, 250)}[where]
		for i in (80 if where == "crushing" else 20):
			_unit(state, 3000 + i, 1, Vector2(800, 850) + offset + Vector2(0, (i % 5) * 10))
		var per_group := Morale._group_losses(state)
		losses[where] = per_group[Config.GROUP_INFANTRY]
		assert((own.morale_pressure > 0.0) == (where in ["flank", "rear", "crushing"]), "%s pressure %f" % [where, own.morale_pressure])
	assert(losses.front == 0.0 and losses.flank > 0.0 and losses.rear > losses.flank and losses.crushing > 0.0, "threat losses %s" % str(losses))
	assert(losses.loose == 0.0, "a loose charge faces where its men look")

## A new flight costs the friends within MORALE_PANIC_RADIUS MORALE_PANIC_LOSS (capped per check), nobody else; the
## next check the group loses heart by its fleeing share.
func _check_panic() -> void:
	var results := []
	for routers in [0, 1, 4]:
		var state := _state()
		var near := _unit(state, 400, 0, MIDDLE + Vector2(0, 60))
		var far := _unit(state, 401, 0, MIDDLE + Vector2(0, Config.MORALE_PANIC_RADIUS + 60.0))
		var foe := _unit(state, 402, 1, MIDDLE + Vector2(0, -40))
		for k in 4:
			var router := _unit(state, 500 + k, 0, MIDDLE + Vector2(k * 4, 0))
			if k < routers: router.morale = -10.0 # Below zero after this check's recovery.
		Morale.tick(state)
		results.append([near.morale, far.morale, foe.morale])
	assert(is_equal_approx(results[0][0] - results[1][0], Config.MORALE_PANIC_LOSS), "one flight: %s" % str(results))
	assert(is_equal_approx(results[0][0] - results[2][0], Config.MORALE_PANIC_CAP), "four flights, capped: %s" % str(results))
	assert(results[0][1] == results[1][1] and results[0][1] == results[2][1], "outside the radius")
	assert(results[0][2] == results[2][2], "the enemy does not panic")
	# The next check: half the group fled, every ready man loses MORALE_PANIC_SHARE_LOSS times that share.
	var state := _state()
	var men: Array[Unit] = []
	for k in 4:
		men.append(_unit(state, 600 + k, 0, MIDDLE + Vector2(0, k * 400.0)))
	_unit(state, 700, 1, MIDDLE + Vector2(FAR, 0))
	men[0].fleeing = true
	men[1].fleeing = true
	men[0].rallies = Config.MORALE_RALLY_LIMIT
	men[1].rallies = Config.MORALE_RALLY_LIMIT
	var per_group := Morale._group_losses(state)
	assert(is_equal_approx(per_group[Config.GROUP_INFANTRY], Config.MORALE_PANIC_SHARE_LOSS * 0.5))
	assert(state.groups[0][Config.GROUP_INFANTRY].morale_state == Config.MORALE_GROUP_ROUTED)

## Pursuit: a charging fighter runs after a fugitive only on the stage 1a leash, from his place around his group: beyond
## the hard leash he turns back to it.
func _check_pursuit(side: int) -> void:
	var state := _state()
	var group = state.groups[side][Config.GROUP_INFANTRY]
	group.order = Config.ORDER_CHARGE
	group.loose = true
	var forward := _forward(side)
	group.direction = forward.angle()
	var chaser := _unit(state, 7781, side, MIDDLE + forward * (Config.AI_CHARGE_FOOT_HARD_LEASH + 20.0))
	var fugitive := _unit(state, 15, 1 - side, MIDDLE + forward * (Config.AI_CHARGE_FOOT_HARD_LEASH + 60.0))
	fugitive.fleeing = true
	fugitive.velocity = forward * chaser.speed * Config.FLEE_SPEED_MULTIPLIER
	var slot: Vector2 = group.slot_position(chaser, state.arena_size)
	AiDecision.plan_into(chaser, group, fugitive, state.arena_size, slot, MIDDLE, 0.1)
	assert(chaser.leashed and chaser.ai_mode == Config.AI_MODE_SLOT, "the chase ends at the hard leash")
	assert(chaser.plan_destination.distance_to(MIDDLE) < 1.0, "and he walks back to his place")
