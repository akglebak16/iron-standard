extends SceneTree
## The hero's background (#152) only places the two free start points: the same total for every background, nothing else.
const HeroOrigin = preload("res://core/campaign/world/hero_origin.gd")
const Config = preload("res://core/characters/config.gd")

func _initialize() -> void:
	assert(HeroOrigin.ORDER.size() == HeroOrigin.ORIGINS.size())
	for id in HeroOrigin.ORDER:
		var total := 0
		for key in HeroOrigin.ORIGINS[id].attrs:
			assert(key in Config.ATTRIBUTES)
			total += int(HeroOrigin.ORIGINS[id].attrs[key])
		assert(total == HeroOrigin.START_POINTS, "%s spends exactly the free points" % id)
		var hero := _hero()
		var before := hero.duplicate(true)
		assert(HeroOrigin.apply(hero, id))
		var sum_before := 0
		var sum_after := 0
		for key in Config.ATTRIBUTES:
			sum_before += int(before[key])
			sum_after += int(hero[key])
		assert(sum_after == sum_before + HeroOrigin.START_POINTS and hero.pts == 0 and hero.origin == id)
		for key in before:
			if not key in Config.ATTRIBUTES and key != "pts":
				assert(hero[key] == before[key], "%s changes only the attributes" % id)
	assert(HeroOrigin.bonus_text("retainer", {"str": "Сила", "vit": "Стойкость"}) == "Сила +1, Стойкость +1")
	var hero := _hero()
	var untouched := hero.duplicate(true)
	assert(not HeroOrigin.apply(hero, "king") and hero == untouched)
	hero.pts = 1
	untouched = hero.duplicate(true)
	assert(not HeroOrigin.apply(hero, "smith") and hero == untouched, "points already spent")
	print("Hero origin tests passed")
	quit(0)

func _hero() -> Dictionary:
	return {"name": "Тест", "lvl": 1, "xp": 0, "pts": 2, "pp": 1, "perks": [], "str": 1, "vit": 1, "agi": 1, "int": 1, "cha": 1,
		"armor": 0, "weapon": 0, "shield": 0, "horse": 0, "hp": 1.0, "seed": 5}
