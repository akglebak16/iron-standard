extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const GearCatalog = preload("res://core/equipment/data/gear_catalog.gd")

func _initialize() -> void:
	var catalog := GearCatalog.new()
	assert(ContentLoader.populate(catalog))
	assert(catalog.size() == 55)
	assert(catalog.get_item("sword_old").dmg == 20)
	assert(catalog.get_item("xbow_heavy").pb == 0.22)
	assert(catalog.get_item("jav_heavy").wt == "throw")
	assert(catalog.get_item("horse_war").v == 172)
	assert(catalog.get_item("shield_heraldic").projectile_block_bonus == 0.18)
	assert(catalog.get_item("missing").is_empty())
	var copy := catalog.get_item("sword_old")
	copy.dmg = 999
	assert(catalog.get_item("sword_old").dmg == 20)
	var valid := {"test_sword": {"id": "test_sword", "name": "Test sword", "slot": "melee", "tier": 0, "price": 1, "w": 1, "dmg": 10, "dt": "cut", "wt": "sword", "spd": 1, "hands": 1, "f": ["emp"]}}
	assert(catalog.replace_data(valid))
	valid.test_sword.f.append("nord")
	assert(catalog.get_item("test_sword").f == ["emp"])
	var invalid := catalog.get_item("test_sword")
	invalid.dt = "laser"
	assert(not catalog.replace_data({"test_sword": invalid}))
	assert(catalog.get_item("test_sword").dt == "cut")
	invalid.dt = "cut"
	invalid.hands = 3
	assert(not catalog.replace_data({"test_sword": invalid}))
	invalid.hands = 1
	invalid.f = [3]
	assert(not catalog.replace_data({"test_sword": invalid}))
	invalid.f = ["emp"]
	invalid.erase("spd")
	assert(not catalog.replace_data({"test_sword": invalid}))
	assert(catalog.get_item("test_sword").spd == 1)
	var shield := {"id": "test_shield", "name": "Test shield", "slot": "shield", "tier": 0, "price": 1, "w": 1, "v": 0.5, "projectile_block_bonus": 0.3}
	assert(catalog.replace_data({"test_shield": shield}))
	shield.projectile_block_bonus = 1.1
	assert(not catalog.replace_data({"test_shield": shield}))
	assert(catalog.get_item("test_shield").projectile_block_bonus == 0.3)
	assert(ContentLoader.populate(catalog))
	assert(catalog.size() == 55)
	print("Gear catalog tests passed")
	quit(0)
