extends SceneTree
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Market = preload("res://core/campaign/economy/market.gd")
const GoodsCatalog = preload("res://core/campaign/data/goods_catalog.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var state := WorldState.create(2, data, "emp", ContentLoader.registry())
	var catalog := GoodsCatalog.new()
	assert(ContentLoader.populate(catalog))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var market := Market.new(catalog, rng)
	var p = state.player
	var fx: Dictionary = state.player_effects()
	var towns: Array = state.map.settles.filter(func(s): return s.kind == "town")
	var a: Dictionary = towns[0]
	var m: Dictionary = market.market_of(a, 1)
	assert(m.gold > 1000 and m.stock.size() == 11)
	var cheap := ""
	for id in market.goods:
		if market.region_mod(a, id) < 1.0:
			cheap = id
	assert(cheap != "", "every culture makes something")
	for id in market.goods:
		assert(market.sell_price(p.rel, fx, a, m, id) <= market.buy_price(p.rel, fx, a, m, id), "no money loop for " + id)
	p.gold = 5000
	p.inv = {}
	var first: int = market.buy_price(p.rel, fx, a, m, cheap)
	var got: Dictionary = market.buy(p, fx, a, 1, cheap, 10, 10)
	assert(got.n > 0 and p.inv[cheap] == got.n and p.gold == 5000 - got.sum)
	assert(market.buy_price(p.rel, fx, a, m, cheap) >= first)
	var sold: Dictionary = market.sell(p, fx, a, 1, cheap, 100)
	assert(sold.n == got.n and not p.inv.has(cheap) and sold.sum < got.sum)
	p.inv = {}
	var heavy: Dictionary = market.buy(p, fx, a, 1, "iron", 500, 10)
	assert(heavy.why in ["weight", "stock", "gold"])
	assert(market.cargo_weight(p.inv) <= market.cargo_cap(p, fx, 10) + 0.001)
	market.market_of(a, 6)
	assert(m.day == 6)
	print("Market tests passed")
	quit(0)
