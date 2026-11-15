extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(ContentLoader.populate(catalog))
	var original := catalog.get_troop("n1")
	var changed := catalog.get_troop("n1")
	changed.hp = 0
	changed.look.weapon = "changed"
	assert(catalog.get_troop("n1") == original)
	for field in ["hp", "spd", "cd", "block"]:
		var invalid := original.duplicate(true)
		invalid.erase(field)
		assert(not catalog.replace_data({"n1": invalid}))
	for bad_value in [NAN, INF, -1, "60"]:
		var invalid := original.duplicate(true)
		invalid.hp = bad_value
		assert(not catalog.replace_data({"n1": invalid}))
	var invalid_shield := original.duplicate(true)
	invalid_shield.shb = 1.1
	assert(not catalog.replace_data({"n1": invalid_shield}))
	for traits in [[], {"morale_immune": 1}, {"morale_base": INF}, {"projectile_damage_multiplier": -1}, {"leader_loss_chance": 0.4}, {"leader_bond": " ", "leader_loss_chance": 0.4}, {"leader_bond": "test", "leader_loss_chance": 1.1}, {"unknown": true}]:
		var invalid := original.duplicate(true)
		invalid.battle_traits = traits
		assert(not catalog.replace_data({"n1": invalid}))
	assert(not catalog.replace_data([]))
	assert(catalog.size() == 67 and catalog.get_troop("n1") == original)
	var definitions := {"n1": original.duplicate(true)}
	assert(catalog.replace_data(definitions))
	definitions.n1.hp = 0
	assert(catalog.get_troop("n1").hp == original.hp)
	print("Catalog validation tests passed")
	quit(0)
