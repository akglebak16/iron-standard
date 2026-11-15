extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://characters/data/perk_catalog.gd")
const PerkEffects = preload("res://characters/rules/perk_effects.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	assert(ContentLoader.populate(catalog))
	var none := PerkEffects.own({}, catalog)
	assert(none.ally == 0 and none.morale == 0 and none.hp == 0)
	var profile := {"perks": ["tactician", "tactician", "inspire", "quick", "unknown"]}
	var effects := PerkEffects.own(profile, catalog)
	assert(is_equal_approx(effects.ally, 0.06))
	assert(effects.morale == 12) # Tactician II (6) + Inspire I (6).
	assert(is_equal_approx(effects.cd, 0.03))
	assert(profile.perks.size() == 5)
	assert(PerkEffects.own({"perks": ["butcher", "butcher", "butcher", "butcher"]}, catalog).killHeal == 0.03)
	assert(PerkEffects.own({"perks": "bad"}, catalog).is_empty())
	print("Perk effects tests passed")
	quit(0)
