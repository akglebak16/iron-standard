extends RefCounted
## The hero's background and the free start points, picked on the start screen (#152).
## Every background gives +1 to one attribute and a start bundle of about the same worth (~250 coins):
## gold, a piece of kit or a few men. The bundle is given once, when the new campaign is made.
const Config = preload("res://core/characters/config.gd")
const GearCatalog = preload("res://core/equipment/data/gear_catalog.gd")
const HeroEquip = preload("res://core/equipment/rules/hero_equip.gd")
const TroopCatalog = preload("res://core/troops/data/catalog.gd")

## The free attribute points every new hero has (`pts` in WorldState.create).
const START_POINTS := 2
## About what each bundle of men is worth in hire costs.
const MEN_WORTH := {"retainer": 180.0, "hunter": 120.0}
const ORDER := ["smith", "retainer", "knight", "hunter", "merchant"]
const ORIGINS := {
	"smith": {"name": "Сын кузнеца", "attr": "str", "gear": {"body": "body_mail"},
		"text": "Вырос у отцовского горна. Сила +1, кольчуга вместо стёганки."},
	"retainer": {"name": "Бывший дружинник", "attr": "vit",
		"text": "Служил в дружине и увёл с собой товарищей. Стойкость +1."},
	"knight": {"name": "Обедневший рыцарь", "attr": "cha", "gear": {"head": "head_nasal", "shield": "shield_banded"},
		"text": "От рода остались имя, шлем и окованный щит. Харизма +1."},
	"hunter": {"name": "Охотник", "attr": "agi", "gear": {"ranged": "bow_hunt"},
		"text": "Ходил по лесам с луком. Ловкость +1, охотничий лук."},
	"merchant": {"name": "Купец", "attr": "int", "gold": 250,
		"text": "Знает счёт и цену вещам. Интеллект +1, 250 монет сверх обычного."},
}

## Points a valid `spent` puts on each attribute ({} spends none), or null when the split is not allowed.
static func spent_points(spent: Variant) -> Variant:
	if not spent is Dictionary:
		return null
	var out := {}
	var total := 0
	for key in spent:
		var value: Variant = spent[key]
		if not key in Config.ATTRIBUTES or not (value is int or value is float) or int(value) != value or int(value) < 0:
			return null
		if int(value) > 0:
			out[key] = int(value)
			total += int(value)
	return out if total <= START_POINTS else null

## Gives the new hero his background and the points spent on the start screen. `start_troops` is the
## culture's start list ([[type, n], ...]): the background's men are its second (archers) or third stack.
## Returns false and changes nothing when the choice is not valid.
static func apply(player: RefCounted, origin: String, spent: Variant, start_troops: Array, gear: GearCatalog, troops: TroopCatalog) -> bool:
	if not ORIGINS.has(origin) or player == null or gear == null or troops == null:
		return false
	var points: Variant = spent_points(spent)
	if points == null:
		return false
	var o: Dictionary = ORIGINS[origin]
	var hero: Dictionary = player.hero
	for item in o.get("gear", {}).values():
		if gear.get_item(String(item)).is_empty(): return false
	var men_type := ""
	if MEN_WORTH.has(origin):
		var stack: int = 1 if origin == "hunter" else 2
		if start_troops.size() <= stack: return false
		men_type = String(start_troops[stack][0])
		if troops.get_troop(men_type).is_empty(): return false
	hero.origin = origin
	hero[o.attr] = int(hero.get(o.attr, 1)) + 1
	for key in points:
		hero[key] = int(hero.get(key, 1)) + int(points[key])
		hero.pts = int(hero.get("pts", 0)) - int(points[key])
	if o.has("gear"):
		var eq := HeroEquip.ensure(hero)
		for slot in o.gear:
			eq[slot] = o.gear[slot]
		HeroEquip.sync_legacy(hero)
	player.gold += int(o.get("gold", 0))
	if men_type != "":
		var cost := maxf(1.0, float(troops.get_troop(men_type).get("cost", 60)))
		var n := maxi(1, roundi(float(MEN_WORTH[origin]) / cost))
		var added := false
		for s in player.troops:
			if s.type == men_type:
				s.n = int(s.n) + n
				added = true
				break
		if not added:
			player.troops.append({"type": men_type, "n": n})
	return true

## How many men a background brings for a culture's start list (shown on the start screen).
static func men_for(origin: String, start_troops: Array, troops: TroopCatalog) -> Array:
	if not MEN_WORTH.has(origin) or troops == null:
		return []
	var stack: int = 1 if origin == "hunter" else 2
	if start_troops.size() <= stack:
		return []
	var troop: Dictionary = troops.get_troop(String(start_troops[stack][0]))
	if troop.is_empty():
		return []
	return [troop.get("name", ""), maxi(1, roundi(float(MEN_WORTH[origin]) / maxf(1.0, float(troop.get("cost", 60)))))]
