extends SceneTree
const Morale = preload("res://battle/rules/morale.gd")

const Config = preload("res://battle/config.gd")
const Unit = preload("res://battle/model/unit.gd")
const BattleState = preload("res://battle/model/state.gd")

func _initialize() -> void:
	var battle = BattleState.new()
	battle.setup_groups()
	var shaken = Unit.new(0, 0, Vector2(100, 100), 40, 0, 1)
	shaken.morale = -5.0
	var hero = Unit.new(1, 0, Vector2(110, 100), 100, 0, 3)
	hero.hero = true
	hero.morale = -10.0
	var companion = Unit.new(2, 0, Vector2(120, 100), 80, 0, 2)
	companion.companion = true
	companion.morale = -10.0
	var undead = Unit.new(3, 0, Vector2(130, 100), 30, 0, 1)
	undead.faction = "undead"
	undead.morale = -10.0
	var foe = Unit.new(4, 1, Vector2(200, 100), 40, 0, 1)
	for unit in [shaken, hero, companion, undead, foe]:
		battle.add_grouped_unit(unit, Config.GROUP_INFANTRY)
	Morale.advance(battle, 0.1)
	assert(shaken.fleeing)
	assert(not hero.fleeing and not companion.fleeing and not undead.fleeing)
	assert(battle.groups[0][Config.GROUP_INFANTRY].active_units().size() == 2)
	var saved_morale: float = foe.morale
	Morale.advance(battle, 0.5)
	assert(foe.morale == saved_morale)
	Morale.advance(battle, 0.5)
	assert(foe.morale != saved_morale)
	var collapse = BattleState.new()
	collapse.setup_groups()
	for i in 10:
		collapse.add_grouped_unit(Unit.new(i, 0, Vector2.ZERO, 40, 0, 1), Config.GROUP_INFANTRY)
		collapse.add_grouped_unit(Unit.new(i + 10, 1, Vector2(100, 0), 40, 0, 1), Config.GROUP_INFANTRY)
	for i in 8:
		collapse.units[i * 2].dead = true
	Morale.advance(collapse, 0.1)
	assert(collapse.units[16].fleeing and collapse.units[18].fleeing)
	print("Morale tests passed")
	quit(0)
