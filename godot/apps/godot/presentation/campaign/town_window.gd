extends "res://apps/godot/presentation/campaign/modal_window.gd"
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## A settlement: recruits, market (food, hero gear) and waiting (renderTown in src/06_ui.js).
const Economy = preload("res://core/campaign/economy/party_economy.gd")
const Market = preload("res://core/campaign/economy/market.gd")
const GearCatalog = preload("res://core/equipment/data/gear_catalog.gd")
const HeroGear = preload("res://core/equipment/rules/hero_gear.gd")
const HeroEquip = preload("res://core/equipment/rules/hero_equip.gd")
const ItemCard = preload("res://apps/godot/presentation/campaign/item_card.gd")
const SettlementLayer = preload("res://apps/godot/presentation/campaign/settlement_layer.gd")
const FactionCatalog = preload("res://core/campaign/data/faction_catalog.gd")
const PartyWindowText = preload("res://apps/godot/presentation/campaign/companion_text.gd")

signal wait_requested(settlement: Dictionary)
var state: RefCounted
var settlement: Dictionary = {}
var _gear := GearCatalog.new()
var _factions := FactionCatalog.new()
var _legacy := {}
## Item whose card is open on the market (tradeDock).
var _trade_pick := ""

func _ready() -> void:
	super()
	if not (ContentLoader.populate(_gear) and ContentLoader.populate(_factions)):
		push_error("Required content failed to load: apps/godot/presentation/campaign/town_window.gd")
		return
	_legacy = {"weapon": HeroGear.LEGACY_WEAPONS, "armor": HeroGear.LEGACY_ARMOR, "shield": HeroGear.LEGACY_SHIELDS, "horse": HeroGear.LEGACY_HORSES}

func open_for(world_state: RefCounted, s: Dictionary) -> void:
	_siege_confirm = false
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
	close_button.text = "Покинуть " + {"town": "город", "castle": "замок", "village": "деревню", "camp": "лагерь"}.get(settlement.kind, "поселение")
	set_crest(settlement.fac)
	sub_label.text = "%s · %s   ·   золото %d" % [SettlementLayer.KIND_NAMES.get(settlement.kind, ""), _factions.get_faction(settlement.fac).get("name", ""), p.gold]
	var tabs: Array = [["recruit", "Рекруты"], ["goods", "Товары"], ["market", "Снабжение"]]
	if settlement.kind == "town":
		tabs.append(["tavern", "Таверна"])
	if settlement.kind == "town" and settlement.fac in ["nord", "emp", "khan", "kin", "emi", "dom", "pact"]:
		tabs.append(["oath", "Служба"])
	if mine:
		tabs.append(["hold", "Владение"])
	elif settlement.kind == "town":
		tabs.append(["quests", "Задания"])
	set_tabs(tabs, current_tab if current_tab != "" else "recruit")
	clear_body()
	if current_tab == "hold" and mine:
		_hold(p, fx)
	elif current_tab == "oath":
		_oath(p)
	elif current_tab == "tavern":
		_tavern(p)
	elif current_tab == "quests":
		_quests(p)
	elif current_tab == "market":
		_market(p, fx)
	elif current_tab == "goods":
		_goods(p, fx)
	else:
		_recruits(p, fx)
		_siege_offer(p)

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
		], r.type)
	heading("Ожидание")
	note("Время идёт как обычно, а отряд стоит у стен. Любой клик по карте — в путь.")
	row("Подождать здесь", "", [{"text": "Ждать", "call": func(): wait_requested.emit(settlement); close_window()}])

func _tavern(p) -> void:
	var comps = state.companions
	var here: Array = comps.at(p, settlement)
	var n: int = p.comps.size()
	note("Наёмники-одиночки сидят по тавернам и переходят из города в город. Спутник сражается рядом с тобой, растёт в уровнях и даёт отряду своё умение. Спутников в отряде: %d из %d." % [n, comps.COMP_MAX])
	if here.is_empty():
		note("Сегодня здесь только местные пьяницы и игроки в кости.")
	for c in here:
		var d: Dictionary = state.companion_catalog.get_companion(c.id)
		var price := int(d.price)
		var can: bool = p.gold >= price and n < comps.COMP_MAX
		var cost := ("%d зол., жалованье %d/день" % [price, d.wage]) if price > 0 else "бесплатно, служит за честь"
		row("%s · %s%s" % [c.name, d.role, (" · ур. %d" % c.lvl) if int(c.lvl) > 1 else ""], "«%s»\n%s: %s\n%s" % [d.story, d.skn, PartyWindowText.skill_text(d, c), cost],
			[{"text": "Нанять", "disabled": not can, "call": func(): _say(comps.hire(p, settlement, c.id))}])
	var rm: Dictionary = comps.rumor(p, settlement)
	if not rm.is_empty():
		note("Трактирщик шепчет: «%s (%s) сейчас в %s. Ищет, к кому бы пристать»." % [rm.c.name, String(rm.c.role).to_lower(), rm.t.name])

func _quests(p) -> void:
	var q = state.quests
	var board: Array = settlement.get("board", [])
	note("Заказы города. Награду выплачивают сразу, как дело сделано.")
	if board.is_empty():
		note("Доска пуста.")
	for item in board.duplicate():
		row(q.text(item), "Срок: до дня %d · %s · награда %d" % [item.dl, q.detail(item, settlement), item.reward],
			[{"text": "Взять", "disabled": p.quests.size() >= q.MAX_QUESTS, "call": func(): _say(q.accept(p, settlement, int(item.id)))}])
	if not p.quests.is_empty():
		heading("Твои задания")
		for item in p.quests:
			row(q.text(item), "До дня %d · награда %d" % [item.dl, item.reward])

func _oath(p) -> void:
	var clans = state.clans
	var f: String = settlement.fac
	note("Фракция: %s. Отношения: %d. %s" % [_factions.get_faction(f).name, roundi(float(p.rel.get(f, 0))), ("Ты служишь: %s." % _factions.get_faction(p.liege).name) if p.liege != "" else "Ты вольный наёмник."])
	if p.liege == f:
		var rl: Dictionary = clans.ruler_of(f)
		heading("Ты вассал %s" % _factions.get_faction(f).gen)
		if not rl.is_empty():
			note("Сюзерен: %s." % rl.name)
		note("Жалованье: %d золота в день. Враги сюзерена — твои враги. Когда он созывает войска, будь рядом с осаждаемым городом: это награда и шанс получить лен. Неявок: %d из 3." % [clans.pay(), p.strikes])
		if p.summons is Dictionary:
			note("Зов: %s%s." % [state.map.settlement_by_id(p.summons.tid).get("name", "?"), " (ты участвовал)" if p.summons.joined else ", срок до дня %d" % ceili(p.summons.until / 24.0)])
		row("Оставить службу", "Отношения с фракцией ухудшатся.", [{"text": "Уйти", "call": func(): clans.leave()}])
	elif p.liege == "":
		var why: String = clans.oath_why(f)
		heading("Принести присягу")
		note("Нужен %d уровень героя и отношения от %d. Сюзерен платит жалованье и награждает за походы, но враги фракции станут твоими." % [clans.OATH_LVL, clans.OATH_REL])
		row("Присягнуть", why, [{"text": "Присягнуть", "disabled": why != "", "call": func(): _say(clans.swear(f))}])
	else:
		note("Сначала оставь службу у %s." % _factions.get_faction(p.liege).gen)
	heading("Мир")
	for x in state.wars.factions_alive():
		var foes: Array = []
		for k in state.wars.wars:
			var parts: PackedStringArray = k.split("|")
			if x in parts:
				foes.append(_factions.get_faction(parts[1] if parts[0] == x else parts[0]).name)
		var rl: Dictionary = clans.ruler_of(x)
		var head: String = rl.name if not rl.is_empty() else ("междуцарствие" if clans.kingless(x) else "")
		row("%s · владений %d" % [_factions.get_faction(x).name, state.wars.hold_of(x).all], "%s%sвоюет с: %s · родов %d" % [head, " · " if head != "" else "", ", ".join(foes) if not foes.is_empty() else "мир", clans.of_faction(x).size()])

var _siege_confirm := false

## "Besiege" for a town or castle of a state at peace with the player: one more click declares war.
func _siege_offer(p) -> void:
	var real: bool = settlement.fac in ["nord", "emp", "khan", "kin", "emi", "dom", "pact"]
	if not real or settlement.kind == "village" or settlement.kind == "camp":
		return
	heading("Осада")
	if not _siege_confirm:
		row("Осадить %s" % settlement.name, "Это объявление войны.", [{"text": "Осадить", "call": func(): _siege_confirm = true}])
	else:
		note("Отношения с %s станут враждебными: их лорды начнут охотиться за тобой, ворота их городов закроются." % _factions.get_faction(settlement.fac).gen)
		row("Объявить войну и осадить?", "", [
			{"text": "Отмена", "call": func(): _siege_confirm = false},
			{"text": "Объявить войну", "call": func():
				_siege_confirm = false
				var s := settlement
				state.declare_war(s.fac)
				close_window()
				state.siege_requested.emit(s)}])

func _say(why: String) -> void:
	if why != "":
		sub_label.text = why

func _hold(p, fx: Dictionary) -> void:
	var siege = state.siege
	var income: int = siege.income(settlement)
	var upkeep: int = roundi(siege.upkeep(settlement) * (1.0 - float(fx.get("wage", 0.0))))
	var garrison: Array = state.wars.garrison_of(settlement)
	heading("Доход")
	note("Подати +%d в день, гарнизон стоит %d. Оставь здесь людей: пустой город захватят." % [income, upkeep])
	if float(settlement.get("ruin", 0)) > 0:
		note("Руины ещё восстанавливаются: доход сильно меньше.")
	var cap := Economy.size_cap(p.hero, fx)
	heading("Гарнизон (%d)" % Economy.troop_count(garrison))
	for t in garrison.duplicate():
		var troop: Dictionary = state.roster.catalog.get_troop(t.type)
		row("%s ×%d" % [troop.name, t.n], "ур. %d" % troop.tier, [
			{"text": "Забрать", "call": func(): siege.gar_move(p, settlement, t.type, 1, false, cap)},
			{"text": "×5", "call": func(): siege.gar_move(p, settlement, t.type, 5, false, cap)}])
	heading("Твой отряд")
	for t in p.troops.duplicate():
		var troop: Dictionary = state.roster.catalog.get_troop(t.type)
		row("%s ×%d" % [troop.name, t.n], "ур. %d" % troop.tier, [
			{"text": "Оставить", "call": func(): siege.gar_move(p, settlement, t.type, 1, true, cap)},
			{"text": "×5", "call": func(): siege.gar_move(p, settlement, t.type, 5, true, cap)}])

func _market(p, fx: Dictionary) -> void:
	heading("Провизия")
	note("В запасе %d порций. Отряду нужна порция на шестерых бойцов в день." % Economy.provisions(p))
	for offer in Economy.FOOD_OFFERS:
		row("%d порций" % offer[0], "%d зол." % offer[1], [{"text": "Купить", "disabled": p.gold < offer[1], "call": func(): Economy.buy_food(p, offer[0], offer[1])}])
	note("Оружие, доспехи и коней продают на вкладке «Товары», надевают в окне отряда (вкладка «Снаряжение»).")

func _goods(p, fx: Dictionary) -> void:
	var market = state.market
	if not market.has_market(settlement):
		note("Здесь не торгуют.")
		return
	var m: Dictionary = market.market_of(settlement, state.clock.day)
	var men: int = Economy.troop_count(p.troops)
	note("Обоз: %s из %d. Деньги торговца: %d." % [str(market.cargo_weight(p.inv)), market.cargo_cap(p, fx, men), m.gold])
	_gear_trade(p, fx, m, men)
	heading("Товары")
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

func _gear_trade(p, fx: Dictionary, m: Dictionary, men: int) -> void:
	var market = state.market
	if _trade_pick != "" and market.is_gear(_trade_pick):
		var picked: Dictionary = market.gear[_trade_pick]
		var eq: Dictionary = HeroEquip.ensure(p.hero)
		var worn: Dictionary = market.gear.get(String(eq.get(picked.slot)), {}) if eq.get(picked.slot) != null else {}
		item_card(ItemCard.describe(picked, worn, true), [{"text": "Закрыть", "call": func(): _trade_pick = ""}])
	heading("Снаряжение у торговца")
	var any := false
	for id in m.stock:
		if not market.is_gear(id) or int(m.stock[id]) < 1:
			continue
		any = true
		var it: Dictionary = market.gear[id]
		var price: int = market.buy_price(p.rel, fx, settlement, m, id)
		row("%s · %s" % [it.name, _tier(it)], "%s · вес %s · купить %d" % [_slot(it), str(it.get("w", 0)), price],
			[{"text": "Подробнее", "call": func(): _trade_pick = id}, {"text": "Купить", "disabled": p.gold < price, "call": func(): _trade(market.buy(p, fx, settlement, state.clock.day, id, 1, men))}])
	if not any:
		note("Сегодня оружейник пуст.")
	heading("Снаряжение в обозе")
	var mine := false
	for id in p.inv.keys():
		if not market.is_gear(id):
			continue
		mine = true
		var it: Dictionary = market.gear[id]
		var price: int = market.sell_price(p.rel, fx, settlement, m, id)
		row("%s ×%d · %s" % [it.name, p.inv[id], _tier(it)], "%s · продать %d" % [_slot(it), price],
			[{"text": "Подробнее", "call": func(): _trade_pick = id}, {"text": "Продать", "disabled": m.gold < price, "call": func(): _trade(market.sell(p, fx, settlement, state.clock.day, id, 1))}])
	if not mine:
		note("Трофеев в обозе нет. Надетое не продаётся: сначала сними его.")

const TIERS := ["простое", "добротное", "редкое", "мастерское"]
const SLOT_NAMES := {"head": "шлем", "body": "доспех", "hands": "перчатки", "legs": "поножи", "melee": "оружие", "ranged": "стрелковое", "shield": "щит", "horse": "конь"}

static func _tier(it: Dictionary) -> String:
	return TIERS[mini(3, int(it.get("tier", 0)))]

static func _slot(it: Dictionary) -> String:
	return SLOT_NAMES.get(it.get("slot", ""), "")

func _trade(result: Dictionary) -> void:
	if result.n == 0 and result.why != "":
		sub_label.text = Market.WHY[result.why]
