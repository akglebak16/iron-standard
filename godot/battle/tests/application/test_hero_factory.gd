extends SceneTree
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const Factory = preload("res://battle/application/factory.gd")
const Setup = preload("res://battle/data/battle_setup.gd")

func _initialize() -> void:
	var catalog := GearCatalog.new()
	assert(catalog.load_data())
	_test_factory(catalog)
	print("Hero factory tests passed")
	quit(0)

func _test_factory(gear_catalog: GearCatalog) -> void:
	var troops := Catalog.new()
	assert(troops.load_data())
	var setup: Setup = load("res://battle/data/demo_battle.tres").duplicate(true)
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
	assert(hero.pierce == 0.1)
	assert(is_equal_approx(hero.accuracy, 0.081))
	setup.hero_profile.eq.ranged = "missing"
	assert(hero.weapon_kind == "throw")
	assert(Factory.create(setup, troops) == null)
