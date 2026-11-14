extends SceneTree
const ArmyBuilder = preload("res://battle/data/army_builder.gd")

const Config = preload("res://battle/config.gd")
const Catalog = preload("res://battle/data/catalog.gd")
const BattleState = preload("res://battle/model/state.gd")

func _initialize() -> void:
	var catalog = Catalog.new()
	assert(catalog.load_data())
	assert(catalog.size() == 67)
	assert(catalog.get_troop("n1").name == "Бонд")
	assert(catalog.get_troop("n1").hp == 60) # faction health multiplier already applied in source catalog
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
	assert(battle.units[0].hp == 60.0 and battle.units[0].weight == 1.0)
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
	var undead = BattleState.new()
	undead.setup_groups()
	assert(ArmyBuilder.spawn(undead, 1, [{"type": "s1", "n": 600}], "undead", catalog, rng))
	assert(undead.units.size() == Config.UNDEAD_UNIT_CAP)
	print("Catalog and spawn tests passed")
	quit(0)
