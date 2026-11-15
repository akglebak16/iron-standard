extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Loot = preload("res://campaign/economy/battle_loot.gd")
const Troops = preload("res://troops/data/catalog.gd")
const Gear = preload("res://equipment/data/gear_catalog.gd")
const Goods = preload("res://campaign/data/goods_catalog.gd")

func _initialize() -> void:
	var troops := Troops.new()
	var gear := Gear.new()
	var goods := Goods.new()
	assert(ContentLoader.populate(troops) and ContentLoader.populate(gear) and ContentLoader.populate(goods))
	assert(goods.definitions().size() == 11)
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	var party := {"troops": [], "hero": {"str": 0}, "inv": {"grain": 59}}
	var caravan := {"troops": [{"type": "e1", "n": 50}], "trade_goods_only": true, "faction": "emp"}
	var drops := Loot.collect(party, caravan, {}, false, troops, gear, goods, rng)
	assert(drops.size() == 1 and drops[0].n == 1)
	assert("emp" in goods.definitions()[drops[0].id].make)
	assert(party.inv[drops[0].id] == (60 if drops[0].id == "grain" else 1))
	assert(Loot.collect(party, caravan, {}, false, troops, gear, goods, rng).is_empty())
	var infantry := {"troops": [{"type": "e1", "n": 50}], "faction": "emp"}
	var items := gear.definitions()
	var gear_count := 0
	for seed_value in 20:
		rng.seed = seed_value
		party.inv = {}
		for drop in Loot.collect(party, infantry, {}, false, troops, gear, goods, rng):
			if not items.has(drop.id):
				continue
			gear_count += 1
			var item: Dictionary = items[drop.id]
			assert(item.tier <= 1 and item.slot != "horse" and not item.get("unique", 0))
	assert(gear_count > 0)
	print("Battle loot tests passed")
	quit(0)
