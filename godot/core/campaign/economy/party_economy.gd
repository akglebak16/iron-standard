extends RefCounted
## The player's purse, men and food: hiring, upgrades, wages, provisions, hero gear and attributes
## (doHire/doFood/doGear/doUpgrade/doAttr in src/05c_logic.js, sizeCap/wageDay/eatProv in src/05_world.js and src/05d_trade.js).
const Config = preload("res://core/campaign/config.gd")

const MK := 2.0
## Portions one unit of a food good gives, eaten cheapest first.
const FOOD_VALUE := {"potato": 6, "grain": 6, "zurek": 12, "ale": 4}
const FOOD_OFFERS := [[10, 22], [30, 60], [80, 150]]
const GEAR_SLOTS := {"weapon": "melee", "armor": "body", "shield": "shield", "horse": "horse"}
const GEAR_LABEL := {"weapon": "Оружие", "armor": "Доспех", "shield": "Щит", "horse": "Конь"}
const ATTRS := {
	"str": ["Сила", "+2,5 к урону за очко"], "vit": ["Стойкость", "+14 к здоровью за очко"], "agi": ["Ловкость", "Быстрее удар и шаг"],
	"int": ["Интеллект", "+3% к опыту, быстрее лечение"], "cha": ["Харизма", "+5 к размеру отряда и +4 к морали за очко"],
}

static func troop_count(list: Array) -> int:
	var n := 0
	for s in list:
		n += int(s.n)
	return n

static func hire_cost(troop: Dictionary, fx: Dictionary) -> int:
	return maxi(1, roundi(float(troop.cost) * (1.0 - float(fx.get("hire", 0.0)))))

static func upgrade_cost(troop: Dictionary, fx: Dictionary) -> int:
	return maxi(1, roundi(float(troop.upCost) * (1.0 - float(fx.get("hire", 0.0)))))

static func size_cap(hero: Dictionary, fx: Dictionary) -> int:
	return roundi((20.0 + int(hero.cha) * 5 + (int(hero.lvl) - 1) * 3 + float(fx.get("size", 0.0))) * MK)

static func wage_day(troops: Array, catalog_wage: Callable, fx: Dictionary) -> int:
	var w := 0.0
	for s in troops:
		w += float(catalog_wage.call(s.type)) * int(s.n)
	return roundi(w / 3.0 * (1.0 - float(fx.get("wage", 0.0))))

static func add_troops(list: Array, type: String, n: int) -> void:
	for s in list:
		if s.type == type:
			s.n += n
			return
	list.append({"type": type, "n": n})

static func remove_troops(list: Array, type: String, n: int) -> void:
	for i in list.size():
		if list[i].type == type:
			list[i].n -= n
			if list[i].n <= 0:
				list.remove_at(i)
			return

## Hires up to n men of `type` from the settlement; returns how many joined.
static func hire(player: RefCounted, settlement: Dictionary, troop: Dictionary, n: int, fx: Dictionary) -> int:
	var recruit := {}
	for r in settlement.recruits:
		if r.type == troop.id:
			recruit = r
	if recruit.is_empty():
		return 0
	var cost := hire_cost(troop, fx)
	var room := size_cap(player.hero, fx) - troop_count(player.troops)
	var count := mini(mini(n, int(recruit.n)), mini(player.gold / cost, room))
	if count < 1:
		return 0
	player.gold -= count * cost
	add_troops(player.troops, troop.id, count)
	recruit.n -= count
	if recruit.n <= 0:
		settlement.recruits.erase(recruit)
	return count

## Promotes as many men as the purse allows; returns the number promoted.
static func upgrade(player: RefCounted, troop: Dictionary, up_id: String, fx: Dictionary) -> int:
	if not up_id in troop.up:
		return 0
	var stack := {}
	for s in player.troops:
		if s.type == troop.id:
			stack = s
	if stack.is_empty():
		return 0
	var cost := upgrade_cost(troop, fx)
	var count := mini(int(stack.n), player.gold / cost)
	if count < 1:
		return 0
	player.gold -= count * cost
	remove_troops(player.troops, troop.id, count)
	add_troops(player.troops, up_id, count)
	return count

static func provisions(player: RefCounted) -> int:
	var n := maxi(0, int(player.food))
	for id in FOOD_VALUE:
		n += int(player.inv.get(id, 0)) * int(FOOD_VALUE[id])
	return n

## Eats `need` portions (cheapest goods first); returns what is still missing.
static func eat(player: RefCounted, need: int) -> int:
	var from_leftover := mini(maxi(0, int(player.food)), need)
	player.food -= from_leftover
	need -= from_leftover
	for id in FOOD_VALUE:
		while need > 0 and int(player.inv.get(id, 0)) > 0:
			player.inv[id] -= 1
			need -= int(FOOD_VALUE[id])
	if need < 0:
		player.food -= need
		need = 0
	return need

static func buy_food(player: RefCounted, n: int, price: int) -> bool:
	if not [n, price] in FOOD_OFFERS or player.gold < price:
		return false
	player.gold -= price
	player.food += n
	return true

static func gear_next(hero: Dictionary, key: String, legacy: Dictionary, gear_catalog) -> Dictionary:
	var ids: Array = legacy[key]
	var next := int(hero.get(key, 0)) + 1
	if next >= ids.size() or String(ids[next]).is_empty():
		return {}
	return gear_catalog.get_item(ids[next])

static func buy_gear(player: RefCounted, key: String, legacy: Dictionary, gear_catalog) -> bool:
	var item := gear_next(player.hero, key, legacy, gear_catalog)
	if item.is_empty() or player.gold < int(item.price):
		return false
	player.gold -= int(item.price)
	player.hero[key] = int(player.hero.get(key, 0)) + 1
	return true

static func spend_attribute(hero: Dictionary, key: String) -> bool:
	if not ATTRS.has(key) or int(hero.get("pts", 0)) < 1:
		return false
	hero.pts -= 1
	hero[key] = int(hero.get(key, 1)) + 1
	return true

## One day passes: provisions are eaten, wages paid; returns log lines. Deserters leave when the purse or the larder is empty.
static func day_tick(player: RefCounted, catalog_wage: Callable, fx: Dictionary, rng: RandomNumberGenerator, troop_name: Callable) -> Array:
	var log: Array = []
	var count := troop_count(player.troops)
	eat(player, maxi(0, ceili(count / 6.0)))
	var wage := wage_day(player.troops, catalog_wage, fx)
	if player.gold >= wage:
		player.gold -= wage
	else:
		player.gold = 0
		if count > 3 and rng.randf() < 0.6:
			var s: Dictionary = player.troops[rng.randi_range(0, player.troops.size() - 1)]
			remove_troops(player.troops, s.type, 1)
			log.append("Не хватило денег на жалованье: %s дезертировал." % String(troop_name.call(s.type)).to_lower())
	if provisions(player) <= 0:
		player.food = 0
		if count > 2 and rng.randf() < 0.5:
			var s: Dictionary = player.troops[rng.randi_range(0, player.troops.size() - 1)]
			remove_troops(player.troops, s.type, 1)
			log.append("Отряд голодает: боец ушёл.")
		else:
			log.append("Закончилась провизия!")
	for f in player.rel:
		var v: float = player.rel[f]
		if f != "bandit":
			player.rel[f] = v - 0.1 if v > 0.0 else (minf(0.0, v + 0.25) if v < 0.0 else 0.0)
	return log

static func perk_rank(hero: Dictionary, id: String) -> int:
	return mini(3, hero.get("perks", []).count(id))

## "" when the next rank can be bought, otherwise the reason (perkWhy).
static func perk_why(hero: Dictionary, perk: Dictionary) -> String:
	var rank := perk_rank(hero, perk.id)
	if rank >= 3:
		return "Максимальный уровень."
	if int(hero.get(perk.a, 1)) < int(perk.req[rank]):
		return "Нужно: %s %d." % [ATTRS[perk.a][0], perk.req[rank]]
	if int(hero.get("pp", 0)) < 1:
		return "Нет очков перков."
	return ""

static func buy_perk(hero: Dictionary, perk: Dictionary) -> bool:
	if not perk_why(hero, perk).is_empty():
		return false
	hero.pp -= 1
	hero.perks.append(perk.id)
	return true
