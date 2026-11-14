extends RefCounted
const Config = preload("res://characters/config.gd")
const Catalog = preload("res://characters/data/companion_catalog.gd")
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")
const PerkEffects = preload("res://characters/rules/perk_effects.gd")

static func party_effects(hero: Dictionary, roster: Array, catalog: Catalog, perks: PerkCatalog) -> Dictionary:
	var effects := PerkEffects.own(hero, perks)
	for saved in roster:
		var resolved := resolve(saved, catalog)
		if resolved.is_empty():
			continue
		for effect in resolved.party_effects:
			effects[effect] = float(effects.get(effect, 0)) + resolved.party_effects[effect]
	return effects

## Saved profile fields override the starting definition, including empty equipment slots.
static func resolve(saved: Dictionary, catalog: Catalog) -> Dictionary:
	var id: Variant = saved.get("id")
	if not id is String or catalog == null:
		return {}
	var definition := catalog.get_companion(id)
	if definition.is_empty():
		return {}
	var profile := {"id": id, "name": definition.name, "lvl": 1, "hp": 1.0, "eq": definition.eq, "perks": definition.perks, "sel": definition.sel}
	for i in Config.ATTRIBUTES.size():
		profile[Config.ATTRIBUTES[i]] = definition.a[i]
	profile.merge(saved.duplicate(true), true)
	var level: Variant = profile.lvl
	var health: Variant = profile.hp
	if not (level is int or level is float) or not is_finite(float(level)) or level < 1 or level != floorf(float(level)):
		return {}
	if not (health is int or health is float) or not is_finite(float(health)) or health < 0.0 or health > 1.0:
		return {}
	if not profile.name is String or profile.name.is_empty() or not profile.eq is Dictionary or not profile.perks is Array or profile.sel not in ["melee", "ranged"]:
		return {}
	for stat in Config.ATTRIBUTES:
		var value: Variant = profile[stat]
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0.0:
			return {}
	var rank_index := floori(minf(Config.PERK_MAX_RANK - 1, (float(level) - 1.0) / Config.COMPANION_LEVELS_PER_SKILL_RANK))
	var effects := {}
	for effect in definition.sk:
		effects[effect] = definition.sk[effect][rank_index]
	return {"profile": profile, "fit": health >= Config.COMPANION_FIT_HEALTH, "party_effects": effects, "voice": definition.get("voice", {})}
