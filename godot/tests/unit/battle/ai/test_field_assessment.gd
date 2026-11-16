extends SceneTree
## Field assessment (DESIGN.md 4.1) on synthetic groups: counts, strength with types, center, front, engagement,
## morale and threat sectors. Classes come from properties, so the troop IDs here are deliberately unusual.
const FieldAssessment = preload("res://core/battle/simulation/ai/field_assessment.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Config = preload("res://core/battle/config.gd")

func _initialize() -> void:
	_test_counts_and_classes()
	_test_strength_and_matchup()
	_test_engaged_and_morale()
	_test_threat_sectors()
	_test_read_only()
	print("Field assessment tests passed")
	quit(0)

func _battle() -> State:
	var battle := State.new()
	battle.setup_groups()
	return battle

func _add(battle: State, side: int, kind: int, at: Vector2, troop: String = "zz_test", tier: int = 1) -> Unit:
	var unit := Unit.new(battle.units.size(), side, at, 100, 0, tier)
	unit.troop_id = troop
	battle.add_grouped_unit(unit, kind)
	return unit

func _group(report: Dictionary, side: int, kind: int) -> Dictionary:
	return report.sides[side].groups[kind]

func _test_counts_and_classes() -> void:
	var battle := _battle()
	for i in 4: _add(battle, 0, Config.GROUP_INFANTRY, Vector2(500, 800 + i * 20))
	var spear := _add(battle, 0, Config.GROUP_INFANTRY, Vector2(500, 880), "qq_pike")
	spear.anti_cavalry = true
	for i in 3:
		var archer := _add(battle, 0, Config.GROUP_ARCHERS, Vector2(400, 800 + i * 20))
		archer.attack_range = 300.0
	var rider := _add(battle, 1, Config.GROUP_CAVALRY, Vector2(1500, 800), "qq_horse")
	rider.mounted = true
	var horse_archer := _add(battle, 1, Config.GROUP_CAVALRY, Vector2(1500, 840), "qq_horse_bow")
	horse_archer.mounted = true
	horse_archer.attack_range = 250.0
	var hero := Unit.new(battle.units.size(), 0, Vector2(100, 100), 100, 0, 1)
	hero.hero = true
	battle.add_grouped_unit(hero, Config.GROUP_INFANTRY)
	var dead := _add(battle, 0, Config.GROUP_INFANTRY, Vector2(100, 100))
	dead.dead = true
	var runner := _add(battle, 0, Config.GROUP_INFANTRY, Vector2(100, 100))
	runner.fleeing = true
	var report := FieldAssessment.assess(battle)
	var infantry := _group(report, 0, Config.GROUP_INFANTRY)
	assert(infantry.count == 5, "The hero, the dead and the fleeing are not ready fighters")
	assert(infantry.fleeing == 1)
	assert(infantry.classes[Config.AI_CLASS_FOOT] == 4 and infantry.classes[Config.AI_CLASS_SPEAR] == 1)
	assert(infantry.center.is_equal_approx(Vector2(500, 840)))
	assert(is_equal_approx(infantry.front_width, 80.0), "Facing +x, the front runs along y")
	assert(_group(report, 0, Config.GROUP_ARCHERS).classes[Config.AI_CLASS_ARCHER] == 3)
	var cavalry := _group(report, 1, Config.GROUP_CAVALRY)
	assert(cavalry.classes[Config.AI_CLASS_CAVALRY] == 1 and cavalry.classes[Config.AI_CLASS_HORSE_ARCHER] == 1)
	assert(report.sides[0].count == 8 and report.sides[0].fleeing == 1 and report.sides[1].count == 2)
	assert(_group(report, 1, Config.GROUP_INFANTRY).count == 0 and _group(report, 1, Config.GROUP_INFANTRY).center == Vector2.INF)

func _test_strength_and_matchup() -> void:
	var battle := _battle()
	var wounded := _add(battle, 0, Config.GROUP_INFANTRY, Vector2(500, 800), "zz_a", 2)
	wounded.hp = 50.0
	var spear := _add(battle, 0, Config.GROUP_ARCHERS, Vector2(500, 900), "zz_b", 0)
	spear.anti_cavalry = true
	var rider := _add(battle, 1, Config.GROUP_CAVALRY, Vector2(900, 900), "zz_c", 0)
	rider.mounted = true
	var report := FieldAssessment.assess(battle)
	var infantry := _group(report, 0, Config.GROUP_INFANTRY)
	assert(is_equal_approx(infantry.strength, 0.5 * (1.0 + Config.AI_FIELD_TIER_POWER * 2)), "Weight x health x tier factor")
	var spears := _group(report, 0, Config.GROUP_ARCHERS)
	var against_riders: float = spears.matchup[Config.GROUP_CAVALRY]
	assert(is_equal_approx(against_riders, Config.AI_MATCHUP[Config.AI_CLASS_SPEAR][Config.AI_CLASS_CAVALRY]))
	assert(spears.matchup[Config.GROUP_INFANTRY] == 0.0, "No enemy group, no matchup")
	var riders := _group(report, 1, Config.GROUP_CAVALRY)
	assert(is_equal_approx(riders.matchup[Config.GROUP_ARCHERS], Config.AI_MATCHUP[Config.AI_CLASS_CAVALRY][Config.AI_CLASS_SPEAR]))
	assert(against_riders > riders.matchup[Config.GROUP_ARCHERS], "Spears beat horsemen, whatever their troop IDs")

func _test_engaged_and_morale() -> void:
	var battle := _battle()
	var fighters: Array[Unit] = []
	for i in 4: fighters.append(_add(battle, 0, Config.GROUP_INFANTRY, Vector2(500, 800 + i * 20)))
	fighters[0].ai_mode = Config.AI_MODE_MELEE
	fighters[0].plan_distance = 20.0
	fighters[1].ai_mode = Config.AI_MODE_MELEE
	fighters[1].plan_distance = Config.AI_FIELD_CONTACT_DISTANCE * 3.0 # Running to the enemy, not yet fighting.
	fighters[2].morale = 0.0
	fighters[3].wavering = true
	var report := FieldAssessment.assess(battle)
	var infantry := _group(report, 0, Config.GROUP_INFANTRY)
	assert(is_equal_approx(infantry.engaged_share, 0.25) and infantry.engaged)
	assert(infantry.wavering == 1)
	var base := fighters[0].base_morale
	assert(is_equal_approx(infantry.morale, base * 0.75))
	assert(is_equal_approx(infantry.morale_share, 0.75))
	fighters[0].plan_distance = Config.AI_FIELD_CONTACT_DISTANCE * 2.0
	assert(not _group(FieldAssessment.assess(battle), 0, Config.GROUP_INFANTRY).engaged)

func _test_threat_sectors() -> void:
	var battle := _battle()
	for i in 3: _add(battle, 0, Config.GROUP_INFANTRY, Vector2(1000, 800 + i * 10))
	battle.groups[0][Config.GROUP_INFANTRY].direction = 0.0
	var behind: Array[Unit] = []
	for i in 3: behind.append(_add(battle, 1, Config.GROUP_INFANTRY, Vector2(700, 800 + i * 10)))
	var report := FieldAssessment.assess(battle)
	var infantry := _group(report, 0, Config.GROUP_INFANTRY)
	assert(infantry.threat_rear > 0.0 and infantry.threat_front == 0.0 and infantry.threat_flank == 0.0)
	for unit in behind: unit.position = Vector2(1000, unit.position.y + 300)
	infantry = _group(FieldAssessment.assess(battle), 0, Config.GROUP_INFANTRY)
	assert(infantry.threat_flank > 0.0 and infantry.threat_rear == 0.0)
	for unit in behind: unit.position = Vector2(1200, unit.position.y - 300)
	infantry = _group(FieldAssessment.assess(battle), 0, Config.GROUP_INFANTRY)
	var near: float = infantry.threat_front
	assert(near > 0.0 and infantry.threat_flank == 0.0)
	for unit in behind: unit.position.x = 1000 + Config.AI_FIELD_THREAT_RADIUS * 0.8
	assert(_group(FieldAssessment.assess(battle), 0, Config.GROUP_INFANTRY).threat_front < near, "Threat fades with distance")
	for unit in behind: unit.position.x = 1000 + Config.AI_FIELD_THREAT_RADIUS + 10
	assert(_group(FieldAssessment.assess(battle), 0, Config.GROUP_INFANTRY).threat_front == 0.0)

func _test_read_only() -> void:
	var battle := _battle()
	for i in 6: _add(battle, i % 2, Config.GROUP_INFANTRY, Vector2(500 + i * 100, 800))
	var before := [battle.motion.positions.duplicate(), battle.motion.real_fields.duplicate(), battle.motion.integer_fields.duplicate(), battle.groups[0][0].center]
	var first := FieldAssessment.assess(battle)
	first.sides[0].groups[0].count = 999
	var after := [battle.motion.positions, battle.motion.real_fields, battle.motion.integer_fields, battle.groups[0][0].center]
	assert(var_to_str(before) == var_to_str(after), "Assessment never writes the state")
	assert(FieldAssessment.assess(battle).sides[0].groups[0].count == 3, "Each report is detached")
