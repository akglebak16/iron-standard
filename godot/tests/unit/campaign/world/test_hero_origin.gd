extends SceneTree
## The hero's background and start points (#152): every background gives +1 to its attribute and its bundle,
## points never go over the free ones, and a wrong choice changes nothing.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const HeroOrigin = preload("res://core/campaign/world/hero_origin.gd")
const HeroGear = preload("res://core/equipment/rules/hero_gear.gd")
const PlayerParty = preload("res://core/campaign/world/player_party.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const Config = preload("res://core/characters/config.gd")

func _initialize() -> void:
	var registry := ContentLoader.registry()
	assert(not registry.is_empty())
	assert(HeroOrigin.ORDER.size() == HeroOrigin.ORIGINS.size())
	var attrs := {}
	for id in HeroOrigin.ORDER:
		var o: Dictionary = HeroOrigin.ORIGINS[id]
		assert(o.attr in Config.ATTRIBUTES and not attrs.has(o.attr), "one background per attribute")
		attrs[o.attr] = true
		for culture in WorldState.START_TROOPS:
			var p := _party(culture)
			var before: Dictionary = p.hero.duplicate(true)
			var men := _men(p)
			var gold: int = p.gold
			assert(HeroOrigin.apply(p, id, {}, WorldState.START_TROOPS[culture], registry.gear, registry.troops), "%s/%s" % [id, culture])
			assert(p.hero.origin == id)
			for key in Config.ATTRIBUTES:
				assert(p.hero[key] == before[key] + (1 if key == o.attr else 0))
			assert(p.hero.pts == HeroOrigin.START_POINTS)
			var gear: Dictionary = HeroGear.resolve(p.hero, registry.gear)
			for slot in o.get("gear", {}):
				assert(gear.slots[slot] == o.gear[slot], "%s gets %s" % [id, o.gear[slot]])
			# what the background does not give stays as before: a mounted culture keeps its horse
			assert(gear.mounted == (before.horse > 0) and p.hero.horse == before.horse)
			assert(p.gold == gold + int(o.get("gold", 0)))
			var listed := HeroOrigin.men_for(id, WorldState.START_TROOPS[culture], registry.troops)
			assert(_men(p) == men + (int(listed[1]) if not listed.is_empty() else 0))
			assert(listed.is_empty() != HeroOrigin.MEN_WORTH.has(id))
			# the bundle is worth about the same for every background and culture
			var worth := float(o.get("gold", 0))
			for slot in o.get("gear", {}):
				var old_item: Dictionary = registry.gear.get_item(str(HeroGear.resolve(before, registry.gear).slots.get(slot, "")))
				worth += float(registry.gear.get_item(o.gear[slot]).price) - float(old_item.get("price", 0))
			if not listed.is_empty():
				var stack: int = 1 if id == "hunter" else 2
				worth += float(registry.troops.get_troop(WorldState.START_TROOPS[culture][stack][0]).cost) * int(listed[1])
			assert(worth >= 110 and worth <= 330, "%s/%s is worth %d" % [id, culture, worth])
	# start points: spent once, never more than the free ones
	var p := _party("nord")
	assert(HeroOrigin.apply(p, "merchant", {"str": 1, "cha": 1}, WorldState.START_TROOPS.nord, registry.gear, registry.troops))
	assert(p.hero.str == 2 and p.hero.cha == 2 and p.hero.int == 2 and p.hero.pts == 0)
	p = _party("nord")
	assert(HeroOrigin.apply(p, "smith", {"vit": 1.0}, WorldState.START_TROOPS.nord, registry.gear, registry.troops))
	assert(p.hero.vit == 2 and p.hero.str == 2 and p.hero.pts == 1)
	for bad in [{"str": 3}, {"str": 2, "agi": 1}, {"str": -1}, {"luck": 1}, {"str": 0.5}, null, "str"]:
		p = _party("nord")
		var untouched: Dictionary = p.hero.duplicate(true)
		assert(not HeroOrigin.apply(p, "smith", bad, WorldState.START_TROOPS.nord, registry.gear, registry.troops))
		assert(p.hero == untouched)
	p = _party("nord")
	assert(not HeroOrigin.apply(p, "king", {}, WorldState.START_TROOPS.nord, registry.gear, registry.troops) and not p.hero.has("origin"))
	print("Hero origin tests passed")
	quit(0)

## A fresh party as WorldState.create makes it, without the world.
func _party(culture: String) -> RefCounted:
	var p := PlayerParty.new()
	p.culture = culture
	p.hero = {"name": "Тест", "lvl": 1, "xp": 0, "pts": 2, "pp": 1, "perks": [], "str": 1, "vit": 1, "agi": 1, "int": 1, "cha": 1,
		"armor": 0, "weapon": 0, "shield": 0, "horse": 1 if culture in ["khan", "emi"] else 0, "hp": 1.0, "seed": 5}
	for t in WorldState.START_TROOPS[culture]:
		p.troops.append({"type": t[0], "n": t[1]})
	return p

func _men(p: RefCounted) -> int:
	var n := 0
	for s in p.troops: n += int(s.n)
	return n
