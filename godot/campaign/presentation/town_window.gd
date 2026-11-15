extends "res://campaign/presentation/modal_window.gd"
## A settlement: recruits, market (food, hero gear) and waiting (renderTown in src/06_ui.js).
const Economy = preload("res://campaign/economy/party_economy.gd")
const Market = preload("res://campaign/economy/market.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const HeroGear = preload("res://equipment/rules/hero_gear.gd")
const SettlementLayer = preload("res://campaign/presentation/settlement_layer.gd")
const FactionCatalog = preload("res://campaign/data/faction_catalog.gd")

signal wait_requested(settlement: Dictionary)
var state: RefCounted
var settlement: Dictionary = {}
var _gear := GearCatalog.new()
var _factions := FactionCatalog.new()
var _legacy := {}

func _ready() -> void:
	super()
	assert(_gear.load_data() and _factions.load_data())
	_legacy = {"weapon": HeroGear.LEGACY_WEAPONS, "armor": HeroGear.LEGACY_ARMOR, "shield": HeroGear.LEGACY_SHIELDS, "horse": HeroGear.LEGACY_HORSES}

func open_for(world_state: RefCounted, s: Dictionary) -> void:
	state = world_state
	settlement = s
	set_tabs([["recruit", "Рекруты"]], "recruit")
	open_window()

func render() -> void:
	if state == null:
		return
	var p = state.player
	var fx: Dictionary = state.player_effects()
	var mine: bool = settlement.fac == "player"
	title_label.text = settlement.name
	sub_label.text = "%s · %s   ·   золото %d" % [SettlementLayer.KIND_NAMES.get(settlement.kind, ""), _factions.get_faction(settlement.fac).get("name", ""), p.gold]
	set_tabs([["recruit", "Рекруты"], ["goods", "Товары"], ["market", "Снабжение"]], current_tab if current_tab != "" else "recruit")
	clear_body()
	if current_tab == "market":
		_market(p, fx)
	elif current_tab == "goods":
		_goods(p, fx)
	else:
		_recruits(p, fx)

func _recruits(p, fx: Dictionary) -> void:
	var cap := Economy.size_cap(p.hero, fx)
	var count: int = Economy.troop_count(p.troops)
	note("В отряде %d из %d бойцов. Свободных рекрутов: %d. Новые люди приходят каждые три дня." % [count, cap, Economy.troop_count(settlement.recruits)])
	if settlement.recruits.is_empty():
		note("Сегодня здесь никто не хочет воевать.")
	for r in settlement.recruits.duplicate():
		var troop: Dictionary = state.roster.catalog.get_troop(r.type)
		var cost := Economy.hire_cost(troop, fx)
		var can: bool = p.gold >= cost and count < cap
		row("%s ×%d" % [troop.name, r.n], "ур. %d · %d зол. за бойца" % [troop.tier, cost], [
			{"text": "Нанять", "disabled": not can, "call": func(): Economy.hire(p, settlement, troop, 1, fx)},
			{"text": "×5", "disabled": not can, "call": func(): Economy.hire(p, settlement, troop, 5, fx)},
		])
	heading("Ожидание")
	note("Время идёт как обычно, а отряд стоит у стен. Любой клик по карте — в путь.")
	row("Подождать здесь", "", [{"text": "Ждать", "call": func(): wait_requested.emit(settlement); close_window()}])

func _market(p, fx: Dictionary) -> void:
	heading("Провизия")
	note("В запасе %d порций. Отряду нужна порция на шестерых бойцов в день." % Economy.provisions(p))
	for offer in Economy.FOOD_OFFERS:
		row("%d порций" % offer[0], "%d зол." % offer[1], [{"text": "Купить", "disabled": p.gold < offer[1], "call": func(): Economy.buy_food(p, offer[0], offer[1])}])
	heading("Снаряжение героя")
	for key in Economy.GEAR_LABEL:
		var item := Economy.gear_next(p.hero, key, _legacy, _gear)
		if item.is_empty():
			row(Economy.GEAR_LABEL[key], "лучшее уже у тебя")
		else:
			row("%s: %s" % [Economy.GEAR_LABEL[key], item.name], "%d зол." % item.price, [{"text": "Купить", "disabled": p.gold < int(item.price), "call": func(): Economy.buy_gear(p, key, _legacy, _gear)}])

func _goods(p, fx: Dictionary) -> void:
	var market = state.market
	if not market.has_market(settlement):
		note("Здесь не торгуют.")
		return
	var m: Dictionary = market.market_of(settlement, state.clock.day)
	var men: int = Economy.troop_count(p.troops)
	note("Обоз: %s из %d. Деньги торговца: %d." % [str(market.cargo_weight(p.inv)), market.cargo_cap(p, fx, men), m.gold])
	for id in market.goods:
		var g: Dictionary = market.goods[id]
		var buy_p: int = market.buy_price(p.rel, fx, settlement, m, id)
		var sell_p: int = market.sell_price(p.rel, fx, settlement, m, id)
		var level: String = market.price_level(settlement, m, id)
		var tag := "  (дёшево)" if level == "low" else ("  (дорого)" if level == "high" else "")
		var have := int(p.inv.get(id, 0))
		row("%s%s" % [g.n, tag], "у торговца %d · купить %d · продать %d · у тебя %d" % [m.stock.get(id, 0), buy_p, sell_p, have], [
			{"text": "+1", "disabled": int(m.stock.get(id, 0)) < 1 or p.gold < buy_p, "call": func(): _trade(market.buy(p, fx, settlement, state.clock.day, id, 1, men))},
			{"text": "+10", "call": func(): _trade(market.buy(p, fx, settlement, state.clock.day, id, 10, men))},
			{"text": "−1", "disabled": have < 1, "call": func(): _trade(market.sell(p, fx, settlement, state.clock.day, id, 1))},
			{"text": "все", "disabled": have < 1, "call": func(): _trade(market.sell(p, fx, settlement, state.clock.day, id, have))},
		])

func _trade(result: Dictionary) -> void:
	if result.n == 0 and result.why != "":
		sub_label.text = Market.WHY[result.why]
