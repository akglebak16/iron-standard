extends RefCounted
## Trade goods of a settlement's market: stock, regional prices, buying and selling (src/05d_trade.js).
## Hero gear sold from the cargo hold arrives with the inventory slice.
const GoodsCatalog = preload("res://campaign/data/goods_catalog.gd")

const MK_GOLD := {"town": 2600, "castle": 1400, "village": 800}
const MK_GOODS := {"town": 16, "castle": 5, "village": 9}
const GOLD_FACTOR := 2.5
const WHY := {"stock": "У торговца больше нет этого товара.", "gold": "Не хватает золота.", "weight": "В обозе не хватает места.",
	"merchant": "У торговца кончились деньги.", "none": "Здесь не торгуют."}

var goods: Dictionary
var rng: RandomNumberGenerator

func _init(catalog: GoodsCatalog, random: RandomNumberGenerator) -> void:
	goods = catalog.definitions()
	rng = random

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
	return m

func market_day(s: Dictionary, m: Dictionary) -> void:
	m.gold += roundi((MK_GOLD.get(s.kind, 800) * GOLD_FACTOR - m.gold) * 0.12) + roundi(20.0 * GOLD_FACTOR)
	for id in goods:
		var t := good_target(s, id)
		var v: int = m.stock.get(id, 0)
		m.stock[id] = maxi(0, v + roundi((t - v) * 0.22 + rng.randf_range(-1.4, 1.4)))

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
	var g: Dictionary = goods[id]
	var m := 0.78 if culture(s) in g.make else (1.22 if culture(s) in g.need else 1.0)
	if s.kind == "village" and g.get("raw", false):
		m *= 0.9
	if s.kind == "town" and g.get("lux", false):
		m *= 1.08
	return m

func stock_mod(s: Dictionary, m: Dictionary, id: String) -> float:
	return clampf(1.5 - 0.5 * float(m.stock.get(id, 0)) / maxf(12.0, float(good_target(s, id))), 0.6, 1.6)

func rel_mod(rel: Dictionary, s: Dictionary) -> float:
	return clampf(float(rel.get(s.fac, 0)), -100.0, 100.0) * 0.0006

func buy_price(rel: Dictionary, fx: Dictionary, s: Dictionary, m: Dictionary, id: String) -> int:
	return maxi(1, roundi(goods[id].p * region_mod(s, id) * stock_mod(s, m, id) * 1.08 * (1.0 - rel_mod(rel, s)) * (1.0 - float(fx.get("buy", 0.0)))))

## Selling is never better than buying in the same town, so friendship and perks cannot make a money loop.
func sell_price(rel: Dictionary, fx: Dictionary, s: Dictionary, m: Dictionary, id: String) -> int:
	var raw := roundi(goods[id].p * region_mod(s, id) * stock_mod(s, m, id) * 0.92 * (1.0 + rel_mod(rel, s)) * (1.0 + float(fx.get("sell", 0.0))))
	return maxi(1, mini(raw, floori(buy_price(rel, fx, s, m, id) * 0.93)))

## "low" / "high" when the local price is well under / over the usual one.
func price_level(s: Dictionary, m: Dictionary, id: String) -> String:
	var r := region_mod(s, id) * stock_mod(s, m, id)
	return "low" if r < 0.88 else ("high" if r > 1.12 else "")

func cargo_weight(inv: Dictionary) -> float:
	var w := 0.0
	for id in inv:
		if goods.has(id):
			w += float(goods[id].w) * int(inv[id])
	return snappedf(w, 0.1)

func cargo_cap(player: RefCounted, fx: Dictionary, troop_count: int) -> int:
	return roundi((60.0 + troop_count * 3.0 + int(player.hero.str) * 6.0 + (30.0 if int(player.hero.horse) > 0 else 0.0)) * (1.0 + float(fx.get("cargo", 0.0))))

func buy(player: RefCounted, fx: Dictionary, s: Dictionary, day: int, id: String, n: int, troop_count: int) -> Dictionary:
	if not goods.has(id) or not has_market(s):
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
		if w + float(goods[id].w) > cap + 1e-6:
			why = "weight"
			break
		player.gold -= price
		total += price
		m.stock[id] -= 1
		m.gold += price
		w += float(goods[id].w)
		player.inv[id] = int(player.inv.get(id, 0)) + 1
		k += 1
	return {"n": k, "sum": total, "why": why}

func sell(player: RefCounted, fx: Dictionary, s: Dictionary, day: int, id: String, n: int) -> Dictionary:
	if not goods.has(id) or not has_market(s):
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
