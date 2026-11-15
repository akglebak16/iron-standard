extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const Factory = preload("res://battle/application/factory.gd")
const Setup = preload("res://battle/data/battle_setup.gd")
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")
const Config = preload("res://battle/config.gd")
const HeroInput = preload("res://battle/application/hero_input.gd")

func _initialize() -> void:
	var catalog := GearCatalog.new()
	assert(ContentLoader.populate(catalog))
	_test_factory(catalog)
	_test_battle_perks(catalog)
	_test_heavy_perk_swap(catalog)
	_test_named_undead_leader(catalog)
	_test_custom_shield(catalog)
	print("Hero factory tests passed")
	quit(0)

func _test_custom_shield(original_gear: GearCatalog) -> void:
	var troops := Catalog.new()
	assert(ContentLoader.populate(troops))
	var shield := original_gear.get_item("shield_plank")
	shield.id = "test_shield"
	shield.look = "custom_art"
	shield.projectile_block_bonus = 0.3
	var gear := GearCatalog.new()
	assert(gear.replace_data({shield.id: shield}))
	var setup := Setup.new()
	setup.hero_troop = "n1"
	setup.hero_profile = {"eq": {"shield": shield.id}}
	var session := Factory.create(setup, troops, gear)
	assert(session != null and session._hero.shield_block == 0.3)

func _test_factory(gear_catalog: GearCatalog) -> void:
	var troops := Catalog.new()
	assert(ContentLoader.populate(troops))
	var setup: Setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.companion_profiles.clear()
	setup.hero_profile = {"str": 3, "agi": 2, "vit": 4, "hp": 0.5, "eq": {"head": "head_cap", "body": "body_mail", "melee": "sword_knight", "ranged": "jav_heavy", "shield": "shield_plank", "horse": "horse_riding"}, "sel": "ranged"}
	var session = Factory.create(setup, troops, gear_catalog)
	assert(session != null)
	var hero = session._hero
	assert(hero.max_hp == 156.0)
	assert(hero.hp == 78.0)
	assert(hero.armor == 33.0)
	assert(hero.mounted and hero.speed == 150.0)
	assert(hero.damage == 56.0)
	assert(is_equal_approx(hero.attack_interval, 1.52))
	assert(hero.attack_range == 480.0)
	assert(hero.block_chance == 0.5)
	assert(hero.shield_block == 0.12)
	assert(hero.weapon_kind == "throw" and hero.damage_type == "pierce")
	assert(hero.hero_weapon.id == "jav_heavy")
	assert(hero.pierce == 0.1)
	assert(is_equal_approx(hero.accuracy, 0.081))
	setup.hero_profile.eq.ranged = "missing"
	assert(hero.weapon_kind == "throw")
	assert(Factory.create(setup, troops) == null)

func _test_battle_perks(gear_catalog: GearCatalog) -> void:
	var troops := Catalog.new()
	var perks := PerkCatalog.new()
	assert(ContentLoader.populate(troops) and ContentLoader.populate(perks))
	var setup: Setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.companion_profiles.clear()
	setup.hero_profile = {"str": 3, "agi": 2, "vit": 4, "cha": 2, "hp": 0.5, "perks": ["tough", "hide", "quick", "eagle", "tactician", "inspire"], "eq": {"head": "head_cap", "body": "body_mail", "melee": "sword_knight", "ranged": "jav_heavy", "shield": "shield_plank", "horse": "horse_riding"}, "sel": "ranged"}
	assert(Factory.create(setup, troops, gear_catalog) == null) # Perks require an injected catalog.
	var session = Factory.create(setup, troops, gear_catalog, perks)
	assert(session != null)
	var hero = session._hero
	assert(hero.max_hp == 164.0 and hero.hp == 82.0)
	assert(hero.armor == 36.0)
	assert(is_equal_approx(hero.attack_interval, 1.52 * 0.97))
	assert(hero.attack_range == 504.0)
	assert(is_equal_approx(hero.accuracy, 0.081 * 0.8))
	var ally = session._state.units[0]
	var base: Dictionary = troops.get_troop(ally.troop_id)
	assert(is_equal_approx(ally.damage, float(base.dmg) * ally.weight * 1.03))
	assert(is_equal_approx(ally.base_morale, Config.BASE_MORALE + ally.tier * Config.TIER_MORALE + 17.0))
	assert(ally.morale == ally.base_morale)
	assert(troops.get_troop(ally.troop_id).dmg == base.dmg) # Buff cannot mutate the catalog.
	setup.hero_profile.perks.append("tough")
	assert(hero.perk_effects.hp == 0.05) # Runtime projection is detached from the authoring Resource.

func _test_heavy_perk_swap(gear_catalog: GearCatalog) -> void:
	var troops := Catalog.new()
	var perks := PerkCatalog.new()
	assert(ContentLoader.populate(troops) and ContentLoader.populate(perks))
	var setup: Setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.companion_profiles.clear()
	setup.hero_profile = {"str": 3, "agi": 2, "vit": 4, "hp": 0.5, "perks": ["grip", "master", "quick", "tough"], "eq": {"melee": "tw_sword", "ranged": "jav_heavy"}, "sel": "melee"}
	var session = Factory.create(setup, troops, gear_catalog, perks)
	assert(session != null)
	var hero = session._hero
	var melee: Dictionary = gear_catalog.get_item("tw_sword")
	var ranged: Dictionary = gear_catalog.get_item("jav_heavy")
	assert(is_equal_approx(hero.damage, (float(melee.dmg) + 3.0 * Config.HERO_MELEE_DAMAGE_PER_STRENGTH) * 1.08))
	var health: float = hero.hp
	var maximum: float = hero.max_hp
	var input := HeroInput.new()
	input.swap = true
	assert(session.set_hero_input(input))
	session.advance(0.01)
	assert(hero.attack_range > 0.0)
	assert(is_equal_approx(hero.damage, (float(ranged.dmg) + 3.0 * float(ranged.bs)) * 1.04)) # Grip affects melee two-handed weapons only.
	assert(hero.hp == health and hero.max_hp == maximum)
	assert(hero.perk_effects.heavy == 0.04)

func _test_named_undead_leader(gear_catalog: GearCatalog) -> void:
	var troops := Catalog.new()
	assert(ContentLoader.populate(troops))
	var setup: Setup = load("res://battle/data/demo_battle.tres").duplicate(true)
	setup.companion_profiles.clear()
	setup.enemy_faction = "emp"
	setup.enemy_army = [{"type": "s1", "n": 2}, {"type": "s3", "n": 2}, {"type": "e1", "n": 1}]
	setup.enemy_leader_name = "Некромант"
	var session = Factory.create(setup, troops, gear_catalog)
	assert(session != null)
	var leaders: Array = session._state.units.filter(func(unit): return unit.leader)
	assert(leaders.size() == 1)
	var leader = leaders[0]
	assert(leader.side == 1 and leader.troop_id == "s3" and leader.name == setup.enemy_leader_name)
	assert(leader.hp == float(troops.get_troop("s3").hp) * Config.LEADER_HEALTH_MULTIPLIER)
	assert(leader.damage == float(troops.get_troop("s3").dmg) * Config.LEADER_DAMAGE_MULTIPLIER)
	for unit in session._state.units:
		if unit.side != 1:
			continue
		if unit.troop_id == "e1":
			assert(not unit.morale_immune and unit.leader_bond.is_empty())
		else:
			assert(unit.morale_immune and unit.morale == 999.0 and unit.base_morale == 999.0)
			assert(unit.projectile_damage_multiplier == 0.6 and unit.blunt_melee_damage_multiplier == 1.4)
