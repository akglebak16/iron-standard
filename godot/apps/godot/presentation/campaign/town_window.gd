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
## Market sub-tab: "goods" (trade goods and food) or "gear" (weapons, armour, horses).
var _market_view := "goods"

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
	var tabs: Array = [["recruit", "Рекруты"], ["goods", "Рынок"]]
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
			{"sound": "coin", "text": "Нанять", "disabled": not can, "call": func(): Economy.hire(p, settlement, troop, 1, fx)},
			{"sound": "coin", "text": "×5", "disabled": not can, "call": func(): Economy.hire(p, settlement, troop, 5, fx)},
		], r.type)
	heading("Ожидание")
	note("Время идёт, а отряд стоит у стен. Любой клик по карте или Z — в путь.")
	row("Подождать здесь", "", [{"sound": "click", "text": "Ждать", "call": func(): wait_requested.emit(settlement); close_window()}])

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
			[{"sound": "coin", "text": "Нанять", "disabled": not can, "call": func(): _say(comps.hire(p, settlement, c.id))}])
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
			[{"sound": "order", "text": "Взять", "disabled": p.quests.size() >= q.MAX_QUESTS, "call": func(): _say(q.accept(p, settlement, int(item.id)))}])
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
		row("Оставить службу", "Отношения с фракцией ухудшатся.", [{"sound": "click", "text": "Уйти", "call": func(): clans.leave()}])
	elif p.liege == "":
		var why: String = clans.oath_why(f)
		heading("Принести присягу")
		note("Нужен %d уровень героя и отношения от %d. Сюзерен платит жалованье и награждает за походы, но враги фракции станут твоими." % [clans.OATH_LVL, clans.OATH_REL])
		row("Присягнуть", why, [{"sound": "order", "text": "Присягнуть", "disabled": why != "", "call": func(): _say(clans.swear(f))}])
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
			{"sound": "click", "text": "Забрать", "call": func(): siege.gar_move(p, settlement, t.type, 1, false, cap)},
			{"text": "×5", "call": func(): siege.gar_move(p, settlement, t.type, 5, false, cap)}])
	heading("Твой отряд")
	for t in p.troops.duplicate():
		var troop: Dictionary = state.roster.catalog.get_troop(t.type)
		row("%s ×%d" % [troop.name, t.n], "ур. %d" % troop.tier, [
			{"sound": "click", "text": "Оставить", "call": func(): siege.gar_move(p, settlement, t.type, 1, true, cap)},
			{"text": "×5", "call": func(): siege.gar_move(p, settlement, t.type, 5, true, cap)}])

func _goods(p, fx: Dictionary) -> void:
	var market = state.market
	if not market.has_market(settlement):
		note("Здесь не торгуют.")
		return
	var m: Dictionary = market.market_of(settlement, state.clock.day)
	var men: int = Economy.troop_count(p.troops)
	if _trade_pick != "" and market.is_gear(_trade_pick):
		_market_view = "gear"
	_trade_summary(p, fx, m, men)
	_market_switch()
	if _market_view == "gear":
		_gear_trade(p, fx, m, men)
		return
	note("Проценты — разница с обычной ценой. Зелёное выгодно, красное нет: покупай там, где товар делают, продавай, где его не хватает.")
	var grid := _trade_table("GoodsTable")
	for id in market.goods:
		_goods_line(grid, p, fx, m, men, id)

## Two sub-tabs of the market: trade goods and gear.
func _market_switch() -> void:
	var line := HBoxContainer.new()
	line.name = "MarketSwitch"
	line.add_theme_constant_override("separation", 6)
	body.add_child(line)
	for v in [["goods", "Товары", "sack"], ["gear", "Снаряжение", "sword"]]:
		var b := Button.new()
		b.name = "Market_" + v[0]
		b.text = v[1]
		b.icon = GameSkin.icon(v[2])
		b.add_theme_constant_override("icon_max_width", 17)
		b.add_theme_font_size_override("font_size", 15)
		b.toggle_mode = true
		b.button_pressed = _market_view == v[0]
		b.focus_mode = Control.FOCUS_NONE
		var view: String = v[0]
		b.pressed.connect(func():
			_market_view = view
			_trade_pick = ""
			render())
		line.add_child(b)

## A card with a compact table: icon, name, merchant's stock, buy, sell, in the cargo, buttons.
func _trade_table(table_name: String) -> GridContainer:
	var card := card_panel()
	card.name = table_name
	body.add_child(card)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	card.add_child(grid)
	for title in ["", "Название", "У торговца", "Купить", "Продать", "В обозе", ""]:
		grid.add_child(_cell(title, GameSkin.MUTED, 14))
	return grid

## Purse, the merchant's money, cargo and provisions above the goods table.
func _trade_summary(p, fx: Dictionary, m: Dictionary, men: int) -> void:
	var market = state.market
	var card := card_panel()
	card.name = "TradeSummary"
	body.add_child(card)
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 26)
	line.add_theme_constant_override("v_separation", 6)
	card.add_child(line)
	var portions := Economy.provisions(p)
	var daily := maxi(1, ceili(men / 6.0))
	_chip(line, "coin", "Твоё золото: %d" % p.gold)
	_chip(line, "coin", "Деньги торговца: %d" % int(m.gold))
	_chip(line, "bag", "Обоз: %s / %d" % [str(snappedf(market.cargo_weight(p.inv), 0.1)), market.cargo_cap(p, fx, men)])
	_chip(line, "food", "Провизия: %d порц., на %d дн." % [portions, portions / daily], Color("#e0705a") if portions < daily * 3 else GameSkin.PARCH)

func _chip(parent: Control, icon_name: String, text: String, color := GameSkin.PARCH) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(_icon(GameSkin.icon(icon_name), 22))
	h.add_child(_cell(text, color, 16))
	parent.add_child(h)

func _goods_line(grid: GridContainer, p, fx: Dictionary, m: Dictionary, men: int, id: String) -> void:
	var market = state.market
	var g: Dictionary = market.goods[id]
	var buy_p: int = market.buy_price(p.rel, fx, settlement, m, id)
	var sell_p: int = market.sell_price(p.rel, fx, settlement, m, id)
	var stock := int(m.stock.get(id, 0))
	var have := int(p.inv.get(id, 0))
	var base: float = market.base_price(id)
	grid.add_child(_icon(GameSkin.icon(GOOD_ICONS.get(id, "sack")), 22))
	var name_line := HBoxContainer.new()
	name_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_line.add_theme_constant_override("separation", 8)
	var title := _cell(String(g.n), GameSkin.PARCH, 16)
	title.add_theme_font_override("font", GameSkin.BODY_BOLD)
	name_line.add_child(title)
	var food := int(Economy.FOOD_VALUE.get(id, 0))
	var info := "вес %s" % str(g.w)
	if food > 0:
		info = "еда %d порц. · %s" % [food, info]
	name_line.add_child(_cell(info, GameSkin.MUTED, 13))
	grid.add_child(name_line)
	grid.add_child(_cell(str(stock) if stock > 0 else "нет", GameSkin.PARCH if stock > 0 else GameSkin.MUTED, 15))
	grid.add_child(_price(buy_p, base * 1.08, false))
	grid.add_child(_price(sell_p, base * 0.92, true))
	var have_text := "—"
	if have > 0:
		have_text = "%d  (≈%d)" % [have, have * sell_p]
	grid.add_child(_cell(have_text, GameSkin.PARCH if have > 0 else GameSkin.MUTED, 15))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	var can_buy: bool = stock > 0 and p.gold >= buy_p
	var can_sell: bool = have > 0 and int(m.gold) >= sell_p
	actions.add_child(make_button({"text": "+1", "hint": "Купить 1 за %d зол." % buy_p, "disabled": not can_buy, "call": func(): _trade(market.buy(p, fx, settlement, state.clock.day, id, 1, men))}))
	actions.add_child(make_button({"text": "+10", "hint": "Купить до 10, сколько хватит денег и места", "disabled": not can_buy, "call": func(): _trade(market.buy(p, fx, settlement, state.clock.day, id, 10, men))}))
	actions.add_child(make_button({"text": "−1", "hint": "Продать 1 за %d зол." % sell_p, "disabled": not can_sell, "call": func(): _trade(market.sell(p, fx, settlement, state.clock.day, id, 1))}))
	actions.add_child(make_button({"text": "Все", "hint": "Продать всё, на что хватит денег торговца", "disabled": not can_sell, "call": func(): _trade(market.sell(p, fx, settlement, state.clock.day, id, have))}))
	for button in actions.get_children():
		_small(button)
	grid.add_child(actions)

## The price and how far it is from the usual one in one line; green when it is a good deal for the player.
func _price(price: int, usual: float, selling: bool) -> Control:
	var diff := roundi((float(price) / maxf(1.0, usual) - 1.0) * 100.0)
	var good := diff >= 5 if selling else diff <= -5
	var bad := diff <= -5 if selling else diff >= 5
	var color := GOOD_PRICE if good else (BAD_PRICE if bad else GameSkin.PARCH)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	var label := _cell(str(price), color, 15)
	label.add_theme_font_override("font", GameSkin.BODY_BOLD)
	line.add_child(label)
	line.add_child(_icon(GameSkin.icon("coin"), 13))
	var mark := _cell("−%d%%" % -diff if diff <= -5 else ("+%d%%" % diff if diff >= 5 else ""), color, 13)
	mark.tooltip_text = "Обычная цена около %d" % roundi(usual)
	mark.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(mark)
	line.tooltip_text = mark.tooltip_text
	return line

## Compact trade buttons so the whole goods list fits on one screen.
static func _small(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size = Vector2(34, 24)
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var box: StyleBox = button.get_theme_stylebox(state_name)
		if box == null:
			continue
		box = box.duplicate()
		box.content_margin_top = 1
		box.content_margin_bottom = 1
		box.content_margin_left = 6
		box.content_margin_right = 6
		button.add_theme_stylebox_override(state_name, box)

static func _cell(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

static func _icon(texture: Texture2D, extent: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(extent, extent)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _gear_trade(p, fx: Dictionary, m: Dictionary, men: int) -> void:
	var market = state.market
	if _trade_pick != "" and market.is_gear(_trade_pick):
		var picked: Dictionary = market.gear[_trade_pick]
		var eq: Dictionary = HeroEquip.ensure(p.hero)
		var worn: Dictionary = market.gear.get(String(eq.get(picked.slot)), {}) if eq.get(picked.slot) != null else {}
		item_card(ItemCard.describe(picked, worn, true), [{"text": "Закрыть", "call": func(): _trade_pick = ""}])
	var ids: Array = []
	for id in m.stock:
		if market.is_gear(id) and int(m.stock[id]) > 0:
			ids.append(id)
	for id in p.inv:
		if market.is_gear(id) and int(p.inv[id]) > 0 and not id in ids:
			ids.append(id)
	if ids.is_empty():
		note("Сегодня оружейник пуст, а трофеев в обозе нет.")
		return
	ids.sort_custom(func(x, y):
		var a: Dictionary = market.gear[x]
		var b: Dictionary = market.gear[y]
		var sa: int = SLOT_ORDER.find(String(a.get("slot", "")))
		var sb: int = SLOT_ORDER.find(String(b.get("slot", "")))
		return sa < sb if sa != sb else int(a.get("tier", 0)) < int(b.get("tier", 0)))
	note("Надетое не продаётся: сначала сними его в окне отряда. «Обзор» показывает вещь рядом с надетой.")
	var grid := _trade_table("GearTable")
	for id in ids:
		_gear_line(grid, p, fx, m, men, id)

func _gear_line(grid: GridContainer, p, fx: Dictionary, m: Dictionary, men: int, id: String) -> void:
	var market = state.market
	var it: Dictionary = market.gear[id]
	var buy_p: int = market.buy_price(p.rel, fx, settlement, m, id)
	var sell_p: int = market.sell_price(p.rel, fx, settlement, m, id)
	var stock := int(m.stock.get(id, 0))
	var have := int(p.inv.get(id, 0))
	var base: float = market.base_price(id)
	var tier: Array = ItemCard.TIERS[clampi(int(it.get("tier", 0)), 0, 3)]
	grid.add_child(_icon(OriginalArt.item_icon(id), 22))
	var name_line := HBoxContainer.new()
	name_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_line.add_theme_constant_override("separation", 8)
	var title := _cell(String(it.name), Color(tier[1]), 16)
	title.add_theme_font_override("font", GameSkin.BODY_BOLD)
	name_line.add_child(title)
	name_line.add_child(_cell("%s · %s · вес %s" % [_slot(it), _tier(it), str(it.get("w", 0))], GameSkin.MUTED, 13))
	grid.add_child(name_line)
	grid.add_child(_cell(str(stock) if stock > 0 else "нет", GameSkin.PARCH if stock > 0 else GameSkin.MUTED, 15))
	grid.add_child(_price(buy_p, base * 1.25, false))
	grid.add_child(_price(sell_p, base * 0.5, true))
	grid.add_child(_cell(str(have) if have > 0 else "—", GameSkin.PARCH if have > 0 else GameSkin.MUTED, 15))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	actions.add_child(make_button({"text": "Обзор", "hint": "Свойства вещи и сравнение с надетой", "call": func(): _trade_pick = id}))
	actions.add_child(make_button({"text": "+1", "hint": "Купить за %d зол." % buy_p, "disabled": stock < 1 or p.gold < buy_p, "call": func(): _trade(market.buy(p, fx, settlement, state.clock.day, id, 1, men))}))
	actions.add_child(make_button({"text": "−1", "hint": "Продать за %d зол." % sell_p, "disabled": have < 1 or int(m.gold) < sell_p, "call": func(): _trade(market.sell(p, fx, settlement, state.clock.day, id, 1))}))
	for button in actions.get_children():
		_small(button)
	grid.add_child(actions)

## Icons of trade goods; the colours match item_card's ▲/▼.
const GOOD_ICONS := {"grain": "grain", "salt": "sack", "ale": "ale", "iron": "ingot", "leather": "hide", "furs": "pelt", "cloth": "roll", "wine": "bottle", "spice": "jar", "potato": "food", "zurek": "food"}
const GOOD_PRICE := Color("#8fc24f")
const BAD_PRICE := Color("#e0705a")
const SLOT_ORDER := ["melee", "ranged", "shield", "head", "body", "hands", "legs", "horse"]
const TIERS := ["простое", "добротное", "редкое", "мастерское"]
const SLOT_NAMES := {"head": "шлем", "body": "доспех", "hands": "перчатки", "legs": "поножи", "melee": "оружие", "ranged": "стрелковое", "shield": "щит", "horse": "конь"}

static func _tier(it: Dictionary) -> String:
	return TIERS[mini(3, int(it.get("tier", 0)))]

static func _slot(it: Dictionary) -> String:
	return SLOT_NAMES.get(it.get("slot", ""), "")

func _trade(result: Dictionary) -> void:
	if int(result.get("n", 0)) > 0:
		UiSounds.play(self, "coin")
	if result.n == 0 and result.why != "":
		sub_label.text = Market.WHY[result.why]
