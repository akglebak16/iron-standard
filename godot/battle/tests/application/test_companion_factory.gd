extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")
const CompanionCatalog = preload("res://characters/data/companion_catalog.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const Factory = preload("res://battle/application/factory.gd")
const Unit = preload("res://battle/model/unit.gd")
const Config = preload("res://battle/config.gd")
const TICK_SECONDS := 1.0 / 60.0

func _initialize() -> void:
	var troops := Catalog.new()
	var gear := GearCatalog.new()
	var perks := PerkCatalog.new()
	var companions := CompanionCatalog.new()
	assert(ContentLoader.populate(troops) and ContentLoader.populate(gear) and ContentLoader.populate(perks) and ContentLoader.populate(companions))
	var setup := Setup.new()
	setup.hero_troop = "n1"
	setup.hero_profile = {"cha": 2}
	setup.enemy_army = [{"type": "e1", "n": 1}]
	setup.companion_profiles = [{"id": "anselm", "hp": 0.25}, {"id": "ingrid"}, {"id": "tului"}, {"id": "vikenty", "hp": 0.24}]
	var session := Factory.create(setup, troops, gear, perks, companions)
	assert(session != null and session.snapshot().counts == [4, 1])
	assert(session.companion_dialogue().is_empty())
	var by_id := {}
	for unit: Unit in session._state.units:
		if unit.companion:
			by_id[unit.companion_id] = unit
	assert(by_id.size() == 3)
	var healer: Unit = by_id.anselm
	var archer: Unit = by_id.ingrid
	var rider: Unit = by_id.tului
	assert(not healer.hero and healer.group_kind == Config.GROUP_INFANTRY)
	assert(is_equal_approx(healer.hp, healer.max_hp * 0.3) and healer.shield_block == 0.12)
	assert(healer.morale == 168.0)
	assert(archer.group_kind == Config.GROUP_ARCHERS and archer.perk_effects.range > 0.0)
	assert(archer.attack_range > float(gear.get_item("bow_hunt").range))
	assert(rider.mounted and rider.group_kind == Config.GROUP_CAVALRY)
	assert(session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.GROUP_ARCHERS))
	session.advance(TICK_SECONDS)
	assert(archer.ai_mode != Config.AI_MODE_UNASSIGNED)
	assert(session._state.groups[0][Config.GROUP_ARCHERS].order == Config.ORDER_CHARGE)
	healer.kills = 1
	session._state.kill(healer)
	session._state.kill(session._state.units[0])
	session.advance(Config.MORALE_TICK_SECONDS)
	session.advance(Config.BATTLE_END_DELAY_SECONDS + TICK_SECONDS)
	var result := session.result()
	assert(result.win and result.comps.anselm == {"hp": 0.0, "down": true, "kills": 1})
	assert(result.comps.has("ingrid") and not result.comps.has("vikenty"))
	assert(result.dead.is_empty() and result.wounded.is_empty() and result.left.is_empty())
	setup.companion_profiles.append({"id": "anselm"})
	assert(Factory.create(setup, troops, gear, perks, companions) == null)
	_check_wounded_bonus(troops, gear, perks, companions)
	_check_dialogue(troops, gear, perks, companions)
	print("Companion battle integration tests passed")
	quit(0)

func _check_wounded_bonus(troops: Catalog, gear: GearCatalog, perks: PerkCatalog, companions: CompanionCatalog) -> void:
	var setup := Setup.new()
	setup.hero_troop = "n1"
	setup.hero_profile = {"perks": ["surgery"]}
	setup.player_army = [{"type": "n1", "n": 1}]
	# Both healers miss the encounter. Their respective rank III and II skills still add up.
	var roster: Array[Dictionary] = [{"id": "anselm", "lvl": 7, "hp": 0.2}, {"id": "vikenty", "lvl": 4, "hp": 0.2}]
	var plain := Factory.create(setup, troops, gear, perks, companions)
	setup.companion_profiles = roster
	var treated := Factory.create(setup, troops, gear, perks, companions)
	assert(plain != null and treated != null)
	assert(treated.snapshot().counts == [2, 0])
	var chance := Config.BASE_WOUNDED_CHANCE + float(treated._hero.perk_effects.surv)
	var rng := RandomNumberGenerator.new()
	var sample_state: int
	for seed_value in 1000:
		rng.seed = seed_value
		var before := rng.state
		var roll := rng.randf()
		# This roll needs both companion bonuses as well as the hero's surgery perk.
		if roll >= chance + 0.22 and roll < chance + 0.22 + 0.1 and roll >= Config.BASE_WOUNDED_CHANCE + 0.32:
			sample_state = before
			break
	assert(sample_state != 0)
	for session in [plain, treated]:
		session._state.kill(session._state.units[0])
		session._rng.state = sample_state
		session.advance(TICK_SECONDS)
		session.advance(Config.BATTLE_END_DELAY_SECONDS + TICK_SECONDS)
	assert(plain.result().dead.n1 == 1)
	assert(treated.result().wounded.n1 == 1 and treated.result().comps.is_empty())
	assert(plain._rng.state == treated._rng.state)

func _check_dialogue(troops: Catalog, gear: GearCatalog, perks: PerkCatalog, companions: CompanionCatalog) -> void:
	var setup := Setup.new()
	setup.hero_troop = "n1"
	setup.companion_profiles = [{"id": "vikenty", "name": "Викентий в бою", "voice": {"start": ["Из сохранения"]}}]
	var session := Factory.create(setup, troops, gear, perks, companions)
	assert(session != null)
	var id: int = session._state.units.front().id
	var roster := session.companion_dialogue()
	var original := companions.get_companion("vikenty")
	assert(roster[id].name == "Викентий в бою" and roster[id].lines == original.voice)
	roster[id].lines.clear()
	assert(session.companion_dialogue()[id].lines == original.voice)
	original.voice = {"start": [false]}
	assert(not companions.replace_data([original]))
	assert(not companions.get_companion("vikenty").voice.is_empty())
