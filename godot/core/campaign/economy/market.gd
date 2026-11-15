extends RefCounted
## Trade goods of a settlement's market: stock, regional prices, buying and selling (src/05d_trade.js).
## Gear is traded too: tier-limited stock by settlement kind, flat prices, never more than one or two pieces.
const GoodsCatalog = preload("res://core/campaign/data/goods_catalog.gd")

const MK_GOLD := {"town": 2600, "castle": 1400, "village": 800}
const MK_GOODS := {"town": 16, "castle": 5, "village": 9}
const GOLD_FACTOR := 2.5
const WHY := {"stock": "У торговца больше нет этого товара.", "gold": "Не хватает золота.", "weight": "В обозе не хватает места.",
	"merchant": "У торговца кончились деньги.", "none": "Здесь не торгуют."}

const GEAR_APPEAR := [0.6, 0.42, 0.28, 0.16]
const GEAR_DAILY := [0.13, 0.09, 0.06, 0.035]

var goods: Dictionary
var gear: Dictionary = {}  # gear definitions (content/gameplay/equipment/items.json), optional
var rng: RandomNumberGenerator

func _init(catalog: GoodsCatalog, random: RandomNumberGenerator) -> void:
	goods = catalog.definitions()
	rng = random

func is_item(id: String) -> bool:
	return goods.has(id) or gear.has(id)

func is_gear(id: String) -> bool:
	return gear.has(id) and not goods.has(id)

func base_price(id: String) -> float:
	return float(goods[id].p) if goods.has(id) else float(gear[id].price)

func weight(id: String) -> float:
	return float(goods[id].w) if goods.has(id) else float(gear.get(id, {}).get("w", 0.0))

func gear_pool(s: Dictionary) -> Array:
	var top := 1 if s.kind == "village" else (2 if s.kind == "town" else 3)
	var out: Array = []
	for id in gear:
		var it: Dictionary = gear[id]
		if not it.get("unique", 0) and int(it.tier) <= top:
			out.append(id)
	return out

func gear_odds(s: Dictionary, id: String, table: Array) -> float:
	var it: Dictionary = gear[id]
	var k := 1.0
	if it.has("f"):
		k = 1.5 if culture(s) in it.f else 0.45
	return float(table[mini(3, int(it.tier))]) * k

static func has_market(s: Dictionary) -> bool:
	return s.kind != "camp" and s.fac != "bandit" and s.fac != "undead"

static func culture(s: Dictionary) -> String:
	return String(s.get("cult", s.fac))

func good_target(s: Dictionary, id: String) -> int:
	var g: Dictionary = goods[id]
	var t := float(MK_GOODS.get(s.kind, 8))
	if culture(s) in g.make:
		t *= 1.7
	elif culture(s) in g.need:
		t *= 0.45
	if s.kind == "village" and not g.get("raw", false):
		t *= 0.5
	if s.kind == "castle" and not id in ["grain", "ale", "salt", "iron"]:
		t *= 0.4
	return maxi(1, roundi(t))

func make_market(s: Dictionary, day: int) -> Dictionary:
	var m := {"day": day, "gold": roundi(MK_GOLD.get(s.kind, 800) * GOLD_FACTOR * rng.randf_range(0.7, 1.1)), "stock": {}}
	for id in goods:
		m.stock[id] = roundi(good_target(s, id) * rng.randf_range(0.6, 1.4))
	for id in gear_pool(s):
		if rng.randf() < gear_odds(s, id, GEAR_APPEAR):
			m.stock[id] = rng.randi_range(1, 2)
	return m

func market_day(s: Dictionary, m: Dictionary) -> void:
	m.gold += roundi((MK_GOLD.get(s.kind, 800) * GOLD_FACTOR - m.gold) * 0.12) + roundi(20.0 * GOLD_FACTOR)
	for id in goods:
		var t := good_target(s, id)
		var v: int = m.stock.get(id, 0)
		m.stock[id] = maxi(0, v + roundi((t - v) * 0.22 + rng.randf_range(-1.4, 1.4)))
	for id in gear_pool(s):
		var v: int = int(m.stock.get(id, 0))
		if v > 3:
			m.stock[id] = v - 1
		elif v == 0 and rng.randf() < gear_odds(s, id, GEAR_DAILY):
			m.stock[id] = 1

## Lazily created and caught up by day (at most 20 days at once).
func market_of(s: Dictionary, day: int) -> Dictionary:
	if not s.has("market") or s.market == null:
		s["market"] = make_market(s, day)
	var m: Dictionary = s.market
	for k in mini(20, maxi(0, day - int(m.day))):
		market_day(s, m)
	m.day = day
	return m

func region_mod(s: Dictionary, id: String) -> float:
	if not goods.has(id):
		return 1.0
	var g: Dictionary = goods[id]
	var m := 0.78 if culture(s) in g.make else (1.22 if culture(s) in g.need else 1.0)
	if s.kind == "village" and g.get("raw", false):
		m *= 0.9
	if s.kind == "town" and g.get("lux", false):
		m *= 1.08
	return m

func stock_mod(s: Dictionary, m: Dictionary, id: String) -> float:
	if not goods.has(id):
		return 1.0
	return clampf(1.5 - 0.5 * float(m.stock.get(id, 0)) / maxf(12.0, float(good_target(s, id))), 0.6, 1.6)

func rel_mod(rel: Dictionary, s: Dictionary) -> float:
	return clampf(float(rel.get(s.fac, 0)), -100.0, 100.0) * 0.0006

func buy_price(rel: Dictionary, fx: Dictionary, s: Dictionary, m: Dictionary, id: String) -> int:
	return maxi(1, roundi(base_price(id) * region_mod(s, id) * stock_mod(s, m, id) * (1.25 if is_gear(id) else 1.08) * (1.0 - rel_mod(rel, s)) * (1.0 - float(fx.get("buy", 0.0)))))

## Selling is never better than buying in the same town, so friendship and perks cannot make a money loop.
func sell_price(rel: Dictionary, fx: Dictionary, s: Dictionary, m: Dictionary, id: String) -> int:
	var raw := roundi(base_price(id) * region_mod(s, id) * stock_mod(s, m, id) * (0.5 if is_gear(id) else 0.92) * (1.0 + rel_mod(rel, s)) * (1.0 + float(fx.get("sell", 0.0))))
	return maxi(1, mini(raw, floori(buy_price(rel, fx, s, m, id) * 0.93)))

## "low" / "high" when the local price is well under / over the usual one.
func price_level(s: Dictionary, m: Dictionary, id: String) -> String:
	if not goods.has(id):
		return ""
	var r := region_mod(s, id) * stock_mod(s, m, id)
	return "low" if r < 0.88 else ("high" if r > 1.12 else "")

func cargo_weight(inv: Dictionary) -> float:
	var w := 0.0
	for id in inv:
		if is_item(id):
			w += weight(id) * int(inv[id])
	return snappedf(w, 0.1)

func cargo_cap(player: RefCounted, fx: Dictionary, troop_count: int) -> int:
	return roundi((60.0 + troop_count * 3.0 + int(player.hero.str) * 6.0 + (30.0 if int(player.hero.get("horse", 0)) > 0 else 0.0)) * (1.0 + float(fx.get("cargo", 0.0))))

func buy(player: RefCounted, fx: Dictionary, s: Dictionary, day: int, id: String, n: int, troop_count: int) -> Dictionary:
	if not is_item(id) or not has_market(s):
		return {"n": 0, "sum": 0, "why": "none"}
	var m := market_of(s, day)
	var cap := cargo_cap(player, fx, troop_count)
	var w := cargo_weight(player.inv)
	var k := 0
	var total := 0
	var why := ""
	while k < n:
		if int(m.stock.get(id, 0)) < 1:
			why = "stock"
			break
		var price := buy_price(player.rel, fx, s, m, id)
		if player.gold < price:
			why = "gold"
			break
		if w + weight(id) > cap + 1e-6:
			why = "weight"
			break
		player.gold -= price
		total += price
		m.stock[id] -= 1
		m.gold += price
		w += weight(id)
		player.inv[id] = int(player.inv.get(id, 0)) + 1
		k += 1
	return {"n": k, "sum": total, "why": why}

func sell(player: RefCounted, fx: Dictionary, s: Dictionary, day: int, id: String, n: int) -> Dictionary:
	if not is_item(id) or not has_market(s):
		return {"n": 0, "sum": 0, "why": "none"}
	var m := market_of(s, day)
	var k := 0
	var total := 0
	var why := ""
	while k < n:
		if int(player.inv.get(id, 0)) < 1:
			break
		var price := sell_price(player.rel, fx, s, m, id)
		if m.gold < price:
			why = "merchant"
			break
		player.gold += price
		total += price
		m.gold -= price
		m.stock[id] = int(m.stock.get(id, 0)) + 1
		player.inv[id] -= 1
		if player.inv[id] <= 0:
			player.inv.erase(id)
		k += 1
	return {"n": k, "sum": total, "why": why}
