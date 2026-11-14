extends SceneTree
const Catalog = preload("res://characters/data/companion_catalog.gd")
const Profile = preload("res://characters/rules/companion_profile.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(catalog.load_data() and catalog.size() == 13)
	for pair in [[1, 0.08], [3, 0.08], [4, 0.15], [6, 0.15], [7, 0.22], [99, 0.22]]:
		var resolved := Profile.resolve({"id": "anselm", "lvl": pair[0], "hp": 0.24}, catalog)
		assert(not resolved.fit and resolved.party_effects.surv == pair[1])
	var saved := {"id": "anselm", "hp": 0.25, "vit": 9, "eq": {"melee": "club"}}
	var resolved := Profile.resolve(saved, catalog)
	assert(resolved.fit and resolved.profile.vit == 9)
	assert(resolved.profile.eq == {"melee": "club"})
	resolved.profile.eq.clear()
	assert(saved.eq.melee == "club" and catalog.get_companion("anselm").eq.melee == "mace")
	for invalid in [{"id": "missing"}, {"id": "anselm", "lvl": 1.5}, {"id": "anselm", "hp": NAN}]:
		assert(Profile.resolve(invalid, catalog).is_empty())
	var invalid_data := catalog.get_companion("anselm")
	invalid_data.sk.surv = [0.08]
	assert(not catalog.replace_data([invalid_data]) and catalog.size() == 13)
	print("Companion profile tests passed")
	quit(0)
