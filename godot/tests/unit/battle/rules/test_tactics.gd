extends SceneTree
const Tactics = preload("res://core/battle/rules/tactics.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Config = preload("res://core/battle/config.gd")
const Event = preload("res://core/battle/combat_event.gd")

func _initialize() -> void:
	_test_infantry_and_archers()
	_test_cavalry_flank()
	_test_follow()
	_test_relayout()
	_test_squad_charge()
	_test_kite_call_off()
	_test_missile_losses()
	print("Tactics tests passed")
	quit(0)

func _player(battle: State, kind: int, at: Vector2, count: int) -> void:
	for i in count:
		battle.add_grouped_unit(Unit.new(battle.units.size(), 0, at + Vector2(0, i * 20), 100, 0, 1), kind)

func _hero(battle: State, at: Vector2, speed: float) -> Unit:
	var hero := Unit.new(battle.units.size(), 0, at, 100, 0, 1)
	battle.add_unit(hero)
	hero.hero = true
	hero.speed = speed
	return hero

## A lone hero next to the line does not start the charge while the player's squads are far.
func _test_squad_charge() -> void:
	var battle := State.new()
	battle.setup_groups()
	_player(battle, Config.GROUP_INFANTRY, Vector2(600, 800), Config.AI_SQUAD_MIN_UNITS)
	_hero(battle, Vector2(1100, 800), 160.0)
	_enemy(battle, Config.GROUP_INFANTRY, Vector2(1200, 800))
	var infantry = battle.groups[1][Config.GROUP_INFANTRY]
	Tactics.enemy_step(battle, 1, 2.6, 0.1)
	assert(infantry.order == Config.ORDER_HOLD)
	assert(is_equal_approx(infantry.squad_distance, 600.0))
	assert(infantry.center.x < 1200.0, "The line keeps advancing on the squads")
	for unit in battle.groups[0][Config.GROUP_INFANTRY].units:
		unit.position.x = 1000.0
	Tactics.enemy_step(battle, 1, 2.7, Config.AI_SQUAD_SCAN_SECONDS)
	assert(infantry.order == Config.ORDER_CHARGE)
	# Fewer than AI_SQUAD_MIN_UNITS fighters (hero, companions) is no squad: the old nearest-fighter rule applies.
	var small := State.new()
	small.setup_groups()
	_player(small, Config.GROUP_INFANTRY, Vector2(1100, 800), Config.AI_SQUAD_MIN_UNITS - 1)
	_enemy(small, Config.GROUP_INFANTRY, Vector2(1200, 800))
	Tactics.enemy_step(small, 1, 2.6, 0.1)
	assert(small.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE)

func _kite_battle(hero_speed: float, missile_losses: float) -> State:
	var battle := State.new()
	battle.setup_groups()
	_player(battle, Config.GROUP_INFANTRY, Vector2(300, 400), Config.AI_SQUAD_MIN_UNITS)
	_player(battle, Config.GROUP_ARCHERS, Vector2(300, 1300), Config.AI_SQUAD_MIN_UNITS)
	var hero := _hero(battle, Vector2(1000, 800), hero_speed)
	for i in 4:
		var unit := _enemy(battle, Config.GROUP_INFANTRY, Vector2(1200, 790 + i * 5))
		unit.speed = 60.0
		unit.target_handle = hero.unit_handle
	var infantry = battle.groups[1][Config.GROUP_INFANTRY]
	infantry.order = Config.ORDER_CHARGE
	infantry.center = Vector2(1500, 800)
	battle.missile_losses[1] = missile_losses
	return battle

func _test_kite_call_off() -> void:
	var dt := Config.AI_SQUAD_SCAN_SECONDS
	var checks := roundi(Config.AI_KITE_SECONDS / dt)
	var battle := _kite_battle(160.0, 0.0)
	var infantry = battle.groups[1][Config.GROUP_INFANTRY]
	for i in checks:
		Tactics.enemy_step(battle, 1, 3.0 + i * dt, dt)
	assert(infantry.order == Config.ORDER_CHARGE and not infantry.kited)
	Tactics.enemy_step(battle, 1, 3.0 + checks * dt, dt)
	assert(infantry.order == Config.ORDER_HOLD and infantry.kited)
	assert(infantry.focus_kind == Config.GROUP_INFANTRY, "Nearest squad without missile losses")
	assert(infantry.center.distance_to(Vector2(1200, 797.5)) < Config.AI_INFANTRY_ADVANCE_SPEED * dt + 0.01, "Re-formed where the men stand")
	assert(absf(angle_difference(infantry.direction, (Vector2(300, 420) - Vector2(1200, 797.5)).angle())) < 0.01)
	# Kited: the force-charge timer and lone fighters no longer pull the line after the hero.
	Tactics.enemy_step(battle, 1, Config.AI_INFANTRY_FORCE_CHARGE_SECONDS + 1.0, dt)
	assert(infantry.order == Config.ORDER_HOLD)
	# It closes in formation and charges only at contact.
	for unit in battle.groups[0][Config.GROUP_INFANTRY].units:
		unit.position = infantry.center + Vector2(-(Config.AI_KITE_RECHARGE_DISTANCE + Config.AI_INFANTRY_CHARGE_DISTANCE) * 0.5, 0)
	Tactics.enemy_step(battle, 1, 6.0, dt)
	assert(infantry.order == Config.ORDER_HOLD)
	for unit in battle.groups[0][Config.GROUP_INFANTRY].units:
		unit.position = infantry.center + Vector2(-Config.AI_KITE_RECHARGE_DISTANCE * 0.5, 0)
	Tactics.enemy_step(battle, 1, 6.25, dt)
	assert(infantry.order == Config.ORDER_CHARGE)
	var under_fire := _kite_battle(160.0, 10.0)
	for i in checks + 1:
		Tactics.enemy_step(under_fire, 1, 3.0 + i * dt, dt)
	assert(under_fire.groups[1][Config.GROUP_INFANTRY].focus_kind == Config.GROUP_ARCHERS, "Archers first under fire")
	var catchable := _kite_battle(50.0, 0.0)
	for i in checks * 2:
		Tactics.enemy_step(catchable, 1, 3.0 + i * dt, dt)
	assert(catchable.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE, "A slower target is a fair chase")
	var closing := _kite_battle(160.0, 0.0)
	closing.units[Config.AI_SQUAD_MIN_UNITS * 2].position = Vector2(500, 800)
	for i in checks * 2:
		for unit in closing.groups[1][Config.GROUP_INFANTRY].units:
			unit.position.x -= Config.AI_KITE_PROGRESS_DISTANCE + 5.0
		Tactics.enemy_step(closing, 1, 3.0 + i * dt, dt)
	assert(closing.groups[1][Config.GROUP_INFANTRY].order == Config.ORDER_CHARGE, "A closing gap is progress")

func _test_missile_losses() -> void:
	var battle := _battle()
	var shot := _enemy(battle, Config.GROUP_INFANTRY, Vector2(1200, 800))
	var cut := _enemy(battle, Config.GROUP_INFANTRY, Vector2(1200, 820))
	_enemy(battle, Config.GROUP_INFANTRY, Vector2(1200, 840))
	battle.kill(shot, null, null, Event.Attack.PROJECTILE)
	battle.kill(cut, null, null, Event.Attack.MELEE)
	assert(battle.missile_losses == [0.0, 1.0])
	Tactics.enemy_step(battle, 1, 1.0, 0.1)
	assert(battle.missile_losses[1] < 1.0)

func _battle() -> State:
	var battle := State.new()
	battle.setup_groups()
	var foe := Unit.new(0, 0, Vector2(600, 800), 100, 0, 1)
	battle.add_grouped_unit(foe, Config.GROUP_INFANTRY)
	return battle

func _enemy(battle: State, kind: int, at: Vector2) -> Unit:
	var unit := Unit.new(battle.units.size(), 1, at, 100, 0, 1)
	battle.add_grouped_unit(unit, kind)
	battle.groups[1][kind].center = at
	return unit

func _test_infantry_and_archers() -> void:
	var battle := _battle()
	_enemy(battle, Config.GROUP_INFANTRY, Vector2(1200, 800))
	_enemy(battle, Config.GROUP_ARCHERS, Vector2(1300, 800))
	var infantry = battle.groups[1][Config.GROUP_INFANTRY]
	var archers = battle.groups[1][Config.GROUP_ARCHERS]
	Tactics.enemy_step(battle, 1, 2.5, 0.1)
	assert(infantry.center == Vector2(1200, 800))
	assert(archers.center == Vector2(1300, 800))
	Tactics.enemy_step(battle, 1, 2.6, 1.0)
	assert(is_equal_approx(infantry.center.x, 1160.0))
	assert(is_equal_approx(archers.center.x, 1260.0))
	battle.units[0].position = Vector2(1000, 800)
	Tactics.enemy_step(battle, 1, 2.7, 0.1)
	assert(infantry.order == Config.ORDER_CHARGE)
	assert(archers.order == Config.ORDER_HOLD)
	battle.units[0].position = Vector2(1156, 800)
	Tactics.enemy_step(battle, 1, 2.8, 0.1)
	assert(archers.order == Config.ORDER_CHARGE)
	var forced := _battle()
	_enemy(forced, Config.GROUP_INFANTRY, Vector2(1200, 800))
	Tactics.enemy_step(forced, 1, 80.0, 0.1)
	assert(forced.groups[1][0].order == Config.ORDER_HOLD)
	Tactics.enemy_step(forced, 1, 80.1, 0.1)
	assert(forced.groups[1][0].order == Config.ORDER_CHARGE)
	var archers_only := _battle()
	_enemy(archers_only, Config.GROUP_ARCHERS, Vector2(770, 800))
	Tactics.enemy_step(archers_only, 1, 1.0, 0.1)
	assert(archers_only.groups[1][1].order == Config.ORDER_CHARGE)

func _test_cavalry_flank() -> void:
	var battle := _battle()
	_enemy(battle, Config.GROUP_CAVALRY, Vector2(1300, 1100))
	var cavalry = battle.groups[1][Config.GROUP_CAVALRY]
	Tactics.enemy_step(battle, 1, 4.0, 0.1)
	assert(cavalry.tactic_state == Config.AI_TACTIC_WAIT)
	Tactics.enemy_step(battle, 1, 4.1, 0.1)
	assert(cavalry.tactic_state == Config.AI_TACTIC_FLANK)
	assert(cavalry.waypoint.y == 1230.0)
	var before: Vector2 = cavalry.center
	Tactics.enemy_step(battle, 1, 4.2, 1.0)
	assert(is_equal_approx(cavalry.center.distance_to(before), Config.AI_CAVALRY_FLANK_SPEED))
	cavalry.center = cavalry.waypoint + Vector2(50, 0)
	Tactics.enemy_step(battle, 1, 4.3, 0.1)
	assert(cavalry.order == Config.ORDER_CHARGE)

func _test_follow() -> void:
	var battle := _battle()
	battle.units[0].position = Vector2(1200, 800)
	var hero := Unit.new(1, 0, Vector2(900, 800), 100, 0, 1)
	hero.hero = true
	battle.add_unit(hero)
	for group in battle.groups[0]:
		group.order = Config.ORDER_FOLLOW
	Tactics.follow_hero(battle, hero)
	assert(battle.groups[0][0].center == Vector2(850, 800))
	assert(battle.groups[0][1].center == Vector2(765, 800))
	assert(battle.groups[0][2].center == Vector2(840, 970))
	hero.dead = true
	hero.position = Vector2(1000, 800)
	Tactics.follow_hero(battle, hero)
	assert(battle.groups[0][0].center == Vector2(850, 800))

func _test_relayout() -> void:
	var battle := _battle()
	var first: Unit = battle.units[0]
	var second := Unit.new(1, 0, Vector2(600, 900), 100, 0, 1)
	battle.add_grouped_unit(second, Config.GROUP_INFANTRY)
	var group = battle.groups[0][Config.GROUP_INFANTRY]
	first.position = Vector2(600, 700)
	Tactics.relayout(battle, 0.1)
	var first_slot: Vector2 = first.slot_offset
	var second_slot: Vector2 = second.slot_offset
	assert(is_equal_approx(battle.formation_timer, Config.FORMATION_RELAYOUT_SECONDS))
	first.position.y = 950
	second.position.y = 650
	Tactics.relayout(battle, 1.0)
	assert(first.slot_offset == first_slot and second.slot_offset == second_slot)
	Tactics.relayout(battle, Config.FORMATION_RELAYOUT_SECONDS - 1.0)
	assert(first.slot_offset == second_slot and second.slot_offset == first_slot)
	group.order = Config.ORDER_CHARGE
	first.position.y = 600
	second.position.y = 950
	Tactics.relayout(battle, Config.FORMATION_RELAYOUT_SECONDS)
	assert(first.slot_offset == second_slot and second.slot_offset == first_slot)
