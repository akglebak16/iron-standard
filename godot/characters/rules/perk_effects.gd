extends RefCounted
## Pure projection of the hero's own perk ranks; companion bonuses arrive separately later.
const Config = preload("res://characters/config.gd")
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")

static func own(profile: Dictionary, catalog: PerkCatalog) -> Dictionary:
	if catalog == null:
		return {}
	var effects := catalog.zero_effects()
	var selected: Variant = profile.get("perks", [])
	if not selected is Array:
		return {}
	var ranks := {}
	for id in selected:
		if id is String:
			ranks[id] = mini(Config.PERK_MAX_RANK, int(ranks.get(id, 0)) + 1)
	for id in ranks:
		var perk: Dictionary = catalog.get_perk(id)
		if perk.is_empty():
			continue # Browser ignores unknown IDs in old saves.
		for effect in perk.fx:
			effects[effect] += perk.fx[effect][ranks[id] - 1]
	return effects
