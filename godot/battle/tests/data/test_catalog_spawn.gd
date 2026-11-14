extends SceneTree
const ArmyBuilder = preload("res://battle/data/army_builder.gd")

const Config = preload("res://battle/config.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const BattleState = preload("res://battle/model/state.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Factory = preload("res://battle/application/factory.gd")
const Combat = preload("res://battle/rules/combat.gd")
const Unit = preload("res://battle/model/unit.gd")

func _initialize() -> void:
	var catalog = Catalog.new()
	assert(catalog.load_data())
	assert(catalog.size() == 67)
	assert(catalog.get_troop("n1").name == "Бонд")
	assert(catalog.get_troop("n1").hp == 57) # faction health multiplier already applied in source catalog
	assert(catalog.get_troop("e3c").grp == Config.GROUP_CAVALRY)
	assert(catalog.get_troop("s1a").grp == Config.GROUP_ARCHERS)
	var rng = RandomNumberGenerator.new()
	rng.seed = 8123
	var battle = BattleState.new()
	battle.setup_groups()
	assert(not ArmyBuilder.spawn(battle, 0, [{"type": "missing", "n": 2}], "nord", catalog, rng))
	assert(battle.units.is_empty())
	for bad_count in [0, -1, 1.5, NAN, INF, "10"]:
		assert(not ArmyBuilder.spawn(battle, 0, [{"type": "n1", "n": 2}, {"type": "n1", "n": bad_count}], "nord", catalog, rng))
		assert(battle.units.is_empty()) # Whole army is validated before creating any unit.
	assert(ArmyBuilder.spawn(battle, 0, [{"type": "n1", "n": 10}, {"type": "n3c", "n": 5}], "nord", catalog, rng))
	assert(battle.units.size() == 15)
	assert(battle.groups[0][Config.GROUP_INFANTRY].units.size() == 10)
	assert(battle.groups[0][Config.GROUP_CAVALRY].units.size() == 5)
	assert(battle.units[0].hp == 57.0 and battle.units[0].weight == 1.0)
	assert(battle.units[0].melee_reach == Config.DEFAULT_MELEE_REACH + float(catalog.get_troop("n1").reach))
	assert(battle.units[0].shield_block == float(catalog.get_troop("n1").get("shb", 0)))
	var massive = BattleState.new()
	massive.setup_groups()
	rng.seed = 8123
	assert(ArmyBuilder.spawn(massive, 1, [{"type": "e1", "n": 600}], "emp", catalog, rng))
	assert(massive.units.size() == Config.SOLO_UNIT_CAP)
	assert(massive.units[0].weight == 2.0)
	assert(massive.units[0].hp == float(catalog.get_troop("e1").hp) * 2.0)
	assert(massive.units[0].damage == float(catalog.get_troop("e1").dmg) * 2.0)
	_check_archer_melee(catalog)
	var setup := Setup.new()
	setup.hero_troop = "n1"
	setup.enemy_faction = "undead"
	setup.enemy_army = [{"type": "s1", "n": 600}]
	var session := Factory.create(setup, catalog)
	assert(session.snapshot().counts == [1, 600])
	assert(session._state.units[0].xp_multiplier == 0.6)
	setup.enemy_unit_cap = 20
	assert(Factory.create(setup, catalog).snapshot().counts == [1, 20])
	setup.enemy_unit_cap = -1
	assert(Factory.create(setup, catalog) == null)
	var custom := catalog.get_troop("n1")
	custom.id = "test_troop"
	custom.fac = "test_faction"
	custom.battle_traits = {"morale_immune": true, "leader_bond": "test_bond", "leader_loss_chance": 0.35}
	assert(catalog.replace_data({custom.id: custom}))
	var custom_battle := BattleState.new()
	custom_battle.setup_groups()
	assert(ArmyBuilder.spawn(custom_battle, 0, [{"type": custom.id, "n": 1}], "nord", catalog, rng))
	assert(custom_battle.units[0].morale_immune and custom_battle.units[0].leader_bond == "test_bond")
	print("Catalog and spawn tests passed")
	quit(0)

func _check_archer_melee(catalog: Catalog) -> void:
	var battle := BattleState.new()
	battle.setup_groups()
	var rng := RandomNumberGenerator.new()
	assert(ArmyBuilder.spawn(battle, 0, [{"type": "n2a", "n": 2}], "nord", catalog, rng, 1))
	var archer: Unit = battle.units[0]
	var definition := catalog.get_troop("n2a")
	assert(archer.weight == 2.0 and archer.damage == definition.dmg * 2.0)
	archer.position = Vector2.ZERO
	var defender := Unit.new(1, 1, Vector2(20, 0), 100, 0, 1)
	defender.facing = PI
	battle.add_unit(defender)
	var reference := RandomNumberGenerator.new()
	rng.seed = 12
	reference.seed = 12
	var factor := reference.randf_range(Config.MELEE_DAMAGE_MIN, Config.MELEE_DAMAGE_MAX)
	assert(archer.ranged_melee_damage == definition.mdmg)
	assert(Combat.strike(battle, archer, defender, rng) == roundi(float(definition.mdmg) * factor))
	assert(rng.state == reference.state)
	archer.ranged_melee_damage = 0.0
	factor = reference.randf_range(Config.MELEE_DAMAGE_MIN, Config.MELEE_DAMAGE_MAX)
	assert(Combat.strike(battle, archer, defender, rng) == roundi(archer.damage * 0.6 * factor))
