extends RefCounted
## The hero's background, picked on the start screen (#152). It only decides where the two free start points go:
## no gold, kit or men on top, so every hero starts exactly as strong as before.
const Config = preload("res://core/characters/config.gd")

## The free attribute points every new hero has (`pts` in WorldState.create); each background spends all of them.
const START_POINTS := 2
const ORDER := ["smith", "retainer", "knight", "hunter", "merchant"]
const ORIGINS := {
	"smith": {"name": "Сын кузнеца", "attrs": {"str": 2}, "text": "Вырос у отцовского горна."},
	"retainer": {"name": "Бывший дружинник", "attrs": {"str": 1, "vit": 1}, "text": "Служил в дружине, пока её не распустили."},
	"knight": {"name": "Обедневший рыцарь", "attrs": {"vit": 1, "cha": 1}, "text": "От рода остались имя и честь."},
	"hunter": {"name": "Охотник", "attrs": {"agi": 2}, "text": "Ходил по лесам с луком и ножом."},
	"merchant": {"name": "Купец", "attrs": {"int": 1, "cha": 1}, "text": "Знает счёт, дороги и цену вещам."},
}

## «Сила +2» or «Сила +1, Стойкость +1», in the order of the attributes.
static func bonus_text(origin: String, names: Dictionary) -> String:
	var parts: Array[String] = []
	for key in Config.ATTRIBUTES:
		var n := int(ORIGINS.get(origin, {}).get("attrs", {}).get(key, 0))
		if n > 0:
			parts.append("%s +%d" % [names.get(key, key), n])
	return ", ".join(parts)

## Spends the hero's start points as his background says. Returns false and changes nothing when the background
## is unknown or the points are already spent.
static func apply(hero: Dictionary, origin: String) -> bool:
	if not ORIGINS.has(origin) or int(hero.get("pts", 0)) < START_POINTS:
		return false
	for key in ORIGINS[origin].attrs:
		hero[key] = int(hero.get(key, 1)) + int(ORIGINS[origin].attrs[key])
	hero.pts = int(hero.pts) - START_POINTS
	hero.origin = origin
	return true
