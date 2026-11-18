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
const TroopList = preload("res://apps/godot/presentation/campaign/troop_list.gd")
const SettlementRecruits = preload("res://core/campaign/rules/settlement_recruits.gd")
const QuestCard = preload("res://apps/godot/presentation/campaign/quest_card.gd")

signal wait_requested(settlement: Dictionary)
## A place to mark on the world map (the town of a wanderer, a quest target) — the window closes after it.
signal map_target(x: float, y: float)
var state: RefCounted
var settlement: Dictionary = {}
var _gear := GearCatalog.new()
var _factions := FactionCatalog.new()
var _legacy := {}
## Item whose card is open on the market (tradeDock).
var _trade_pick := ""
## Market sub-tab: "goods" (trade goods and food) or "gear" (weapons, armour, horses).
var _market_view := "goods"
## The result of the last deal, shown under the title once after the redraw.
var _flash := ""

func _ready() -> void:
	fit_height = true
	super()
	var wait := Button.new()
	wait.name = "Wait"
	wait.text = "Подождать здесь"
	wait.tooltip_text = "Время идёт, отряд стоит у стен. Любой клик по карте или Z — в путь."
	wait.icon = GameSkin.icon("hourglass")
	wait.expand_icon = true
	wait.add_theme_constant_override("icon_max_width", 20)
	wait.focus_mode = Control.FOCUS_NONE
	wait.pressed.connect(func():
		UiSounds.play(self, "click")
		wait_requested.emit(settlement)
		close_window())
	footer_left.add_child(wait)
	if not (ContentLoader.populate(_gear) and ContentLoader.populate(_factions)):
		push_error("Required content failed to load: apps/godot/presentation/campaign/town_window.gd")
		return
	_legacy = {"weapon": HeroGear.LEGACY_WEAPONS, "armor": HeroGear.LEGACY_ARMOR, "shield": HeroGear.LEGACY_SHIELDS, "horse": HeroGear.LEGACY_HORSES}

func open_for(world_state: RefCounted, s: Dictionary) -> void:
	_siege_confirm = false
	_leave_confirm = false
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
	if _flash != "":
		sub_label.text += "   ·   " + _flash
		_flash = ""
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

## «Рекруты»: a summary of purse, room, wages and the next recruits, then one compact table (as on the market).
func _recruits(p, fx: Dictionary) -> void:
	var catalog = state.roster.catalog
	var cap := Economy.size_cap(p.hero, fx)
	var count: int = Economy.troop_count(p.troops)
	var room := maxi(0, cap - count)
	var line := TroopList.summary(body, "RecruitSummary")
	TroopList.chip(line, "coin", "Золото %d" % p.gold)
	TroopList.chip(line, "men", "Отряд %d / %d · свободно %d" % [count, cap, room], TroopList.WARN if room == 0 else GameSkin.PARCH,
		"Мест нет: лимит растёт с уровнем и харизмой героя." if room == 0 else "Лимит зависит от уровня, харизмы и перков героя.")
	TroopList.chip(line, "coin", "Жалованье сейчас %d в день" % Economy.wage_day(p.troops, func(t): return float(catalog.get_troop(t).wage), fx))
	TroopList.chip(line, "hourglass", "Новые люди %s" % _next_recruits())
	var stacks: Array = settlement.recruits.duplicate()
	stacks.sort_custom(func(a, b):
		var ta: Dictionary = catalog.get_troop(a.type)
		var tb: Dictionary = catalog.get_troop(b.type)
		return int(ta.tier) > int(tb.tier) if int(ta.tier) != int(tb.tier) else String(ta.name) < String(tb.name))
	if stacks.is_empty():
		_empty_state("men", "Сегодня никто не хочет воевать", "Новые люди придут %s." % _next_recruits())
	else:
		var men := Economy.troop_count(stacks)
		var grid := TroopList.table(body, "RecruitTable", "Желают вступить", TroopList.men(men), GameSkin.BRASS)
		for r in stacks:
			_recruit_line(grid, p, fx, catalog.get_troop(r.type), int(r.n), room)

## «через 5 ч» / «через 2 дн. 3 ч» until the settlement refreshes its recruits.
func _next_recruits() -> String:
	var hours := maxi(1, SettlementRecruits.RECRUIT_HOURS - int(settlement.get("rt", 0)))
	return "через %d ч" % hours if hours < 24 else "через %d дн. %d ч" % [hours / 24, hours % 24]

func _recruit_line(grid: GridContainer, p, fx: Dictionary, troop: Dictionary, n: int, room: int) -> void:
	var cost := Economy.hire_cost(troop, fx)
	var affordable: int = p.gold / cost
	var why := ""
	if room == 0:
		why = "Отряд полон: %d из %d" % [Economy.troop_count(p.troops), Economy.size_cap(p.hero, fx)]
	elif affordable < 1:
		why = "Не хватает золота: нужно %d, у тебя %d" % [cost, p.gold]
	var all := mini(n, mini(affordable, room))
	var actions: Array = []
	var price := TroopList.cell("%d за бойца" % cost, GameSkin.BRASS if affordable > 0 else TroopList.WARN, 14)
	price.name = "Price_" + troop.id
	price.custom_minimum_size.x = 92
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions.append(price)
	for def in [["Hire", "Нанять", 1], ["Hire5", "×5", 5], ["HireAll", "Всех ×%d" % all if all > 1 else "Всех", all]]:
		var k: int = mini(int(def[2]), all)
		var b := TroopList.small(make_button({"sound": "coin", "text": def[1], "disabled": k < 1 or why != "",
			"hint": why if why != "" else "Нанять %d за %d золота" % [k, k * cost],
			"call": func(): _hire(p, fx, troop, k)}))
		b.name = "%s_%s" % [def[0], troop.id]
		actions.append(b)
	var lines := ["ступень %s · %s · жалованье %d в день" % [TroopList.tier_pips(int(troop.tier)), TroopList.group_name(troop), int(troop.wage)]]
	var figures := "здоровье %d · броня %d · урон %d" % [int(troop.hp), int(troop.arm), int(troop.dmg)]
	var ups: Array = troop.get("up", []).map(func(id): return String(state.roster.catalog.get_troop(id).name))
	if not ups.is_empty():
		figures += "   ·   дальше: " + ", ".join(PackedStringArray(ups))
	lines.append(figures)
	TroopList.row(grid, troop.id, troop.id, "%s ×%d" % [troop.name, n], lines, actions)

func _hire(p, fx: Dictionary, troop: Dictionary, n: int) -> void:
	var gold: int = p.gold
	var hired := Economy.hire(p, settlement, troop, n, fx)
	if hired > 0:
		_flash = "нанято: %s ×%d (−%d золота)" % [troop.name, hired, gold - int(p.gold)]

## The party window's empty card: a large icon, a title and a muted line.
func _empty_state(icon_name: String, title: String, detail: String, node_name := "RecruitEmpty") -> void:
	var card := card_panel()
	card.name = node_name
	body.add_child(card)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	card.add_child(line)
	line.add_child(TroopList.icon(GameSkin.icon(icon_name), 44))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(col)
	var t := Label.new()
	t.text = title
	GameSkin.title(t, 22)
	col.add_child(t)
	var d := TroopList.cell(detail, GameSkin.MUTED, 16)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(d)

## «Таверна»: wandering companions for hire as cards (portrait, story, skill, attributes, perks, price) and the
## innkeeper's rumour with the town on the map.
func _tavern(p) -> void:
	var comps = state.companions
	var here: Array = comps.at(p, settlement)
	var n: int = p.comps.size()
	var line := TroopList.summary(body, "TavernSummary")
	TroopList.chip(line, "heart", "Спутники %d / %d" % [n, comps.COMP_MAX], TroopList.WARN if n >= comps.COMP_MAX else GameSkin.PARCH,
		"Спутник бьётся рядом с тобой, растёт в уровнях и даёт отряду своё умение.")
	TroopList.chip(line, "coin", "Жалованье спутников %d в день" % comps.wage(p))
	TroopList.chip(line, "coin", "Золото %d" % p.gold)
	if here.is_empty():
		_empty_state("ale", "За столами одни местные", "Наёмники-одиночки переходят из города в город раз в несколько дней. Загляни позже или спроси трактирщика, где их видели.", "TavernEmpty")
	for c in here:
		_companion_card(p, c, n)
	var rm: Dictionary = comps.rumor(p, settlement)
	if not rm.is_empty():
		_rumor_card(rm)

func _companion_card(p, c: Dictionary, party_comps: int) -> void:
	var comps = state.companions
	var d: Dictionary = state.companion_catalog.get_companion(c.id)
	var price := int(d.price)
	var why := ""
	if party_comps >= comps.COMP_MAX:
		why = "Отряд спутников полон: %d из %d" % [party_comps, comps.COMP_MAX]
	elif p.gold < price:
		why = "Не хватает %d золота" % (price - p.gold)
	var card := card_panel()
	card.name = "Companion_" + c.id
	body.add_child(card)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	card.add_child(line)
	var portrait := TroopList.icon(OriginalArt.compose(HeroGear.resolve(c, state.gear).look).portrait, 96)
	portrait.name = "Portrait"
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(portrait)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 3)
	line.add_child(main)
	var title := Label.new()
	title.text = c.name
	GameSkin.title(title, 21)
	main.add_child(title)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 6)
	main.add_child(who)
	who.add_child(TroopList.icon(OriginalArt.crest(d.fac), 18))
	who.add_child(TroopList.cell("%s · %s%s" % [d.role, _factions.get_faction(d.fac).get("name", ""), (" · ур. %d" % c.lvl) if int(c.lvl) > 1 else ""], GameSkin.MUTED, 14))
	var story := TroopList.cell("«%s»" % d.story, Color("#d8c8a0"), 14)
	story.name = "Story"
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var slant := FontVariation.new()
	slant.base_font = GameSkin.BODY
	slant.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.18, 1), Vector2.ZERO)
	story.add_theme_font_override("font", slant)
	main.add_child(story)
	var skill := HBoxContainer.new()
	skill.name = "Skill"
	skill.add_theme_constant_override("separation", 6)
	main.add_child(skill)
	skill.add_child(TroopList.icon(GameSkin.icon("flag"), 18))
	var skill_name := TroopList.cell(String(d.skn) + ":", GameSkin.BRASS, 14)
	skill_name.add_theme_font_override("font", GameSkin.BODY_BOLD)
	skill.add_child(skill_name)
	var skill_text := TroopList.cell(PartyWindowText.skill_text(d, c), GameSkin.PARCH, 14)
	skill_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill.add_child(skill_text)
	var stats := HFlowContainer.new()
	stats.name = "Attributes"
	stats.add_theme_constant_override("h_separation", 6)
	stats.add_theme_constant_override("v_separation", 4)
	main.add_child(stats)
	for key in ["str", "vit", "agi", "int", "cha"]:
		stats.add_child(_pill("%s %d" % [Economy.ATTRS[key][0], int(c.get(key, 0))], GameSkin.PARCH, Economy.ATTRS[key][1]))
	var ranks := {}
	for id in c.get("perks", []):
		ranks[id] = int(ranks.get(id, 0)) + 1
	for id in ranks:
		var perk: Dictionary = state.perks.get_perk(id)
		if not perk.is_empty():
			stats.add_child(_pill("%s %s" % [perk.n, "◆".repeat(mini(3, ranks[id]))], GameSkin.BRASS, OriginalArt.MANIFEST.perks.get(id, perk.n)))
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 168
	side.add_theme_constant_override("separation", 4)
	line.add_child(side)
	var prize := HBoxContainer.new()
	prize.alignment = BoxContainer.ALIGNMENT_END
	side.add_child(prize)
	prize.add_child(TroopList.icon(GameSkin.icon("coin"), 24))
	var price_label := Label.new()
	price_label.name = "Price"
	price_label.text = str(price) if price > 0 else "даром"
	GameSkin.title(price_label, 24)
	price_label.add_theme_color_override("font_color", TroopList.WARN if p.gold < price else GameSkin.BRASS)
	prize.add_child(price_label)
	var wage := TroopList.cell("жалованье %d в день" % int(d.wage) if price > 0 else "служит за честь", GameSkin.MUTED, 13)
	wage.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(wage)
	var hire := make_button({"sound": "coin", "text": "Нанять", "disabled": why != "", "hint": why if why != "" else "Нанять за %d золота" % price,
		"call": func():
			var gold: int = p.gold
			var fail: String = comps.hire(p, settlement, c.id)
			if fail != "":
				_say(fail)
			else:
				_flash = "нанят спутник: %s (−%d золота)" % [c.name, gold - int(p.gold)]})
	hire.name = "Hire_" + c.id
	GameSkin.primary(hire)
	hire.size_flags_horizontal = Control.SIZE_SHRINK_END
	side.add_child(hire)
	if why != "":
		var reason := TroopList.cell(why, TroopList.WARN, 13)
		reason.name = "Why"
		reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side.add_child(reason)

## The innkeeper's whisper: who is the nearest wanderer and where; the town can be shown on the map.
func _rumor_card(rm: Dictionary) -> void:
	var card := card_panel()
	card.name = "Rumor"
	body.add_child(card)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)
	line.add_child(TroopList.icon(GameSkin.icon("ale"), 34))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	line.add_child(col)
	var head := TroopList.cell("Трактирщик шепчет", GameSkin.BRASS, 15)
	head.add_theme_font_override("font", GameSkin.BODY_BOLD)
	col.add_child(head)
	var text := TroopList.cell("«%s, %s, сейчас в %s. Ищет, к кому бы пристать»." % [rm.c.name, String(rm.c.role).to_lower(), rm.t.name], GameSkin.PARCH, 14)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	var t: Dictionary = rm.t
	var go := TroopList.small(make_button({"sound": "click", "text": "Показать на карте", "hint": "Отметить %s на карте" % t.name,
		"call": func(): map_target.emit(float(t.x), float(t.y)); close_window()}))
	go.name = "RumorMap"
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(go)

## A small rounded label with a tooltip: an attribute or a perk on a companion card.
func _pill(text: String, color: Color, hint: String) -> PanelContainer:
	var pill := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#2a2016")
	box.border_color = Color(color, 0.45)
	box.set_border_width_all(1)
	box.set_corner_radius_all(9)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	pill.add_theme_stylebox_override("panel", box)
	pill.tooltip_text = hint
	pill.mouse_filter = Control.MOUSE_FILTER_STOP
	var l := TroopList.cell(text, color, 12)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(l)
	return pill

## «Задания»: the town's board as cards (kind, task, distance, deadline, reward, «Взять», «Показать на карте») and the
## player's own errands in short lines with progress and what is handed in here.
func _quests(p) -> void:
	var q = state.quests
	var bonus := float(state.player_effects().get("quest", 0.0))
	var board: Array = settlement.get("board", [])
	var mine: Array = p.quests.filter(func(x): return not state.map.settlement_by_id(x.sid).is_empty() and not state.map.settlement_by_id(x.from).is_empty())
	mine.sort_custom(func(a, b): return int(a.dl) < int(b.dl))
	var total := 0
	for x in mine:
		total += roundi(float(x.reward) * (1.0 + bonus))
	var full: bool = p.quests.size() >= q.MAX_QUESTS
	var line := TroopList.summary(body, "QuestSummary")
	TroopList.chip(line, "book", "Твои задания %d / %d" % [p.quests.size(), q.MAX_QUESTS], TroopList.WARN if full else GameSkin.PARCH,
		"Журнал полон: сначала сдай или заверши задание." if full else "Одновременно можно вести до %d заданий." % q.MAX_QUESTS)
	TroopList.chip(line, "coin", "Награды в журнале %d" % total)
	TroopList.chip(line, "flag", "Доска пополняется каждый день", GameSkin.PARCH, "Заказ висит на доске %d дней, на его место встаёт новый." % q.BOARD_DAYS)
	_section_title("Доска заказов", "награду платят сразу, как дело сделано")
	if board.is_empty():
		_empty_state("flag", "Заказов пока нет", "Новые заказы появятся завтра: город вывешивает их каждый день.", "BoardEmpty")
	for item in board.duplicate():
		_board_card(p, item, bonus, full)
	if mine.is_empty():
		_section_title("Твои задания", "пока нет")
		note("Возьми заказ с доски: доставка, поставка, разведка или охота на разбойников.")
	else:
		var grid := TroopList.table(body, "MyQuests", "Твои задания", "%d из %d · по ближайшему сроку" % [mine.size(), q.MAX_QUESTS], GameSkin.BRASS)
		grid.columns = 4
		for x in mine:
			_my_quest_line(grid, QuestCard.describe(x, state, _factions, bonus), x)

func _section_title(title: String, detail: String) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	body.add_child(line)
	var t := Label.new()
	t.text = title
	GameSkin.title(t, 19)
	line.add_child(t)
	line.add_child(TroopList.cell(detail, GameSkin.MUTED, 14))

func _board_card(p, item: Dictionary, bonus: float, full: bool) -> void:
	var card_info: Dictionary = QuestCard.describe(item, state, _factions, bonus)
	var days := int(item.dl) - int(state.clock.day)
	var card := card_panel()
	card.name = "Board_%d" % int(item.id)
	body.add_child(card)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)
	var symbol := TroopList.icon(GameSkin.icon(card_info.icon), 36)
	symbol.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(symbol)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 2)
	line.add_child(main)
	var kind := TroopList.cell(String(card_info.type).to_upper(), GameSkin.BRASS, 12)
	kind.name = "Kind"
	main.add_child(kind)
	var title := TroopList.cell(card_info.title, GameSkin.PARCH, 17)
	title.name = "Task"
	title.add_theme_font_override("font", GameSkin.BODY_BOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.add_child(title)
	main.add_child(TroopList.cell(String(state.quests.detail(item, settlement)), GameSkin.MUTED, 14))
	if not card_info.progress.is_empty() and item.type in ["supply", "muster"]:
		main.add_child(TroopList.cell("%s: %d из %d" % [card_info.progress[2], card_info.progress[0], card_info.progress[1]], GameSkin.MUTED, 14))
	if card_info.warning != "" and days >= 0:
		var warn := TroopList.cell("!  " + String(card_info.warning), Color("#f09b7d"), 14)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		main.add_child(warn)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 176
	side.add_theme_constant_override("separation", 3)
	line.add_child(side)
	var prize := HBoxContainer.new()
	prize.alignment = BoxContainer.ALIGNMENT_END
	side.add_child(prize)
	prize.add_child(TroopList.icon(GameSkin.icon("coin"), 22))
	var reward := Label.new()
	reward.name = "Reward"
	reward.text = str(card_info.reward)
	GameSkin.title(reward, 23)
	prize.add_child(reward)
	var deadline := TroopList.cell("срок %s · до дня %d" % [QuestCard.days(days), int(item.dl)], TroopList.WARN if days <= 3 else GameSkin.MUTED, 13)
	deadline.name = "Deadline"
	deadline.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(deadline)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 6)
	side.add_child(buttons)
	var target: Dictionary = QuestCard.target(item, state.map)
	if not target.is_empty():
		var go := TroopList.small(make_button({"sound": "click", "text": "На карте", "hint": "Показать цель на карте: %s" % target.get("name", ""),
			"call": func(): map_target.emit(float(target.x), float(target.y)); close_window()}))
		go.name = "Map_%d" % int(item.id)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		buttons.add_child(go)
	var take := make_button({"sound": "order", "text": "Взять", "disabled": full, "hint": "Журнал полон: не больше %d заданий" % state.quests.MAX_QUESTS if full else "Взять задание",
		"call": func():
			var fail: String = state.quests.accept(p, settlement, int(item.id))
			if fail != "":
				_say(fail)
			else:
				_flash = "взято задание: " + String(card_info.title)})
	take.name = "Take_%d" % int(item.id)
	GameSkin.primary(take)
	buttons.add_child(take)
	if full:
		var why := TroopList.cell("журнал полон", TroopList.WARN, 12)
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		side.add_child(why)

## One of the player's errands: kind icon, task with progress, days left and «сдаётся здесь» / «готово к сдаче», map.
func _my_quest_line(grid: GridContainer, info: Dictionary, q: Dictionary) -> void:
	grid.add_child(TroopList.icon(GameSkin.icon(info.icon), 26))
	var block := VBoxContainer.new()
	block.name = "Mine_%d" % int(q.id)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 0)
	var title := TroopList.cell(info.title, GameSkin.PARCH, 15)
	title.add_theme_font_override("font", GameSkin.BODY_BOLD)
	title.clip_text = true
	title.tooltip_text = info.title
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	block.add_child(title)
	var tags: Array = []
	for tag in info.tags:
		tags.append(tag[0])
	var target: Dictionary = QuestCard.target(q, state.map)
	if not target.is_empty() and int(target.get("id", -1)) == int(settlement.id) and q.type != "camp":
		tags.append("сдаётся здесь")
	var under := "%s · %s" % [info.type, info.deadline]
	if not info.progress.is_empty():
		under += " · %s %d / %d" % [String(info.progress[2]).to_lower(), info.progress[0], info.progress[1]]
	if not tags.is_empty():
		under += " · " + " · ".join(PackedStringArray(tags))
	var sub := TroopList.cell(under, Color("#a5c77b") if tags.has("готово к сдаче") or tags.has("сдаётся здесь") else (TroopList.WARN if info.blocked or tags.has("срочно") else GameSkin.MUTED), 12)
	sub.clip_text = true
	block.add_child(sub)
	grid.add_child(block)
	var reward := TroopList.cell("%d зол." % int(info.reward), GameSkin.BRASS, 14)
	grid.add_child(reward)
	if not info.target.is_empty():
		var t: Dictionary = info.target
		var go := TroopList.small(make_button({"sound": "click", "text": "На карте", "hint": "Показать цель на карте: %s" % t.get("name", ""),
			"call": func(): map_target.emit(float(t.x), float(t.y)); close_window()}))
		grid.add_child(go)
	else:
		grid.add_child(Control.new())

## «Служба»: the faction card (crest, ruler, relations bar, your status), then the oath with its requirements, benefits
## and costs, or your service (pay, no-shows, the current summons, leaving with a second click), and the balance of
## power as a table with the enemies' crests.
func _oath(p) -> void:
	var clans = state.clans
	var f: String = settlement.fac
	var faction: Dictionary = _factions.get_faction(f)
	var rel := roundi(float(p.rel.get(f, 0)))
	var card := card_panel()
	card.name = "FactionCard"
	body.add_child(card)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	card.add_child(line)
	line.add_child(TroopList.icon(OriginalArt.crest(f), 56))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	line.add_child(col)
	var title := Label.new()
	title.text = faction.get("name", f)
	GameSkin.title(title, 21)
	col.add_child(title)
	var rl: Dictionary = clans.ruler_of(f)
	col.add_child(TroopList.cell("Правитель: %s" % (rl.name if not rl.is_empty() else ("междуцарствие" if clans.kingless(f) else "—")), GameSkin.MUTED, 14))
	var status := "Ты вассал %s" % faction.get("gen", f) if p.liege == f else ("Ты служишь: %s" % _factions.get_faction(p.liege).get("name", p.liege) if p.liege != "" else "Ты вольный наёмник")
	col.add_child(TroopList.cell(status, GameSkin.PARCH, 15))
	var rel_box := VBoxContainer.new()
	rel_box.custom_minimum_size.x = 220
	rel_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(rel_box)
	var rel_label := TroopList.cell("Отношения: %d · %s" % [rel, _relation_word(rel)], _relation_color(rel), 15)
	rel_label.name = "Relation"
	rel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rel_box.add_child(rel_label)
	rel_box.add_child(_bar("RelationBar", (rel + 100) / 200.0, _relation_color(rel), "От −100 до 100. Растут от заданий и побед над врагами фракции."))
	if p.liege == f:
		_service_card(p, f)
	elif p.liege == "":
		_oath_card(p, f)
	else:
		var other := card_panel()
		other.name = "ServeElsewhere"
		body.add_child(other)
		var t := TroopList.cell("Ты уже служишь %s. Чтобы присягнуть здесь, сначала оставь ту службу в любом городе %s." % [_factions.get_faction(p.liege).get("gen", p.liege), _factions.get_faction(p.liege).get("gen", p.liege)], GameSkin.PARCH, 15)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		other.add_child(t)
	_powers(p, f)

static func _relation_word(rel: int) -> String:
	if rel < -20: return "враждебны"
	if rel < 0: return "холодно"
	if rel < 20: return "ровно"
	if rel < 50: return "дружны"
	return "близки"

static func _relation_color(rel: int) -> Color:
	if rel < -20: return Color("#e0705a")
	if rel < 0: return Color("#d9a35a")
	if rel < 20: return GameSkin.PARCH
	return Color("#a5c77b")

## A thin bar 0..1 in the game's colours.
func _bar(node_name: String, value: float, color: Color, hint: String) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(value, 0.0, 1.0)
	bar.custom_minimum_size = Vector2(0, 8)
	bar.tooltip_text = hint
	var back := StyleBoxFlat.new()
	back.bg_color = Color("#140f0a")
	back.border_color = Color("#ffffff22")
	back.set_border_width_all(1)
	back.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

## Not serving anyone: what the oath needs (✓/✗), what it gives, what it costs, and the button.
func _oath_card(p, f: String) -> void:
	var clans = state.clans
	var gen: String = _factions.get_faction(f).get("gen", f)
	var grid := TroopList.table(body, "OathCard", "Присяга", "служба %s" % gen, GameSkin.BRASS)
	grid.columns = 1
	var lvl := int(p.hero.get("lvl", 1))
	var rel := roundi(float(p.rel.get(f, 0)))
	var needs := [
		["Уровень героя %d, нужен %d" % [lvl, clans.OATH_LVL], lvl >= clans.OATH_LVL, "Опыт дают бои и задания."],
		["Отношения %d, нужно от %d" % [rel, clans.OATH_REL], rel >= clans.OATH_REL, "Выполняй задания этой фракции и бей её врагов."],
		["Идёт война: сюзерену нужны воины", not state.wars.wars.is_empty(), "В мирное время присягу не принимают."],
	]
	for i in needs.size():
		var need: Array = needs[i]
		var mark := TroopList.cell(("✓  " if need[1] else "✗  ") + String(need[0]), Color("#a5c77b") if need[1] else TroopList.WARN, 15)
		mark.name = "Need%d" % i
		mark.tooltip_text = need[2]
		mark.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(mark)
	var gives := TroopList.cell("Даёт: жалованье %d золота в день, награды за походы сюзерена, шанс получить лен." % clans.pay(), GameSkin.PARCH, 14)
	gives.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid.add_child(gives)
	var costs := TroopList.cell("Требует: враги %s станут твоими; на зов сюзерена надо являться, после трёх неявок — изгнание." % gen, GameSkin.MUTED, 14)
	costs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid.add_child(costs)
	var why: String = clans.oath_why(f)
	var swear := make_button({"sound": "order", "text": "Присягнуть", "disabled": why != "", "hint": why if why != "" else "Принести присягу %s" % gen,
		"call": func(): _say(clans.swear(f))})
	swear.name = "Swear"
	GameSkin.primary(swear)
	swear.size_flags_horizontal = Control.SIZE_SHRINK_END
	grid.add_child(swear)
	_stretch(grid)

## A one-column table: let its lines take the card's width (buttons keep to the right edge).
static func _stretch(grid: GridContainer) -> void:
	for c in grid.get_children():
		if c is Control:
			(c as Control).size_flags_horizontal = (Control.SIZE_EXPAND | Control.SIZE_SHRINK_END) if c is Button else Control.SIZE_EXPAND_FILL

var _leave_confirm := false

## Serving this faction: liege, pay, no-shows bar, the current summons with the map, and leaving with confirmation.
func _service_card(p, f: String) -> void:
	var clans = state.clans
	var grid := TroopList.table(body, "ServiceCard", "Служба", "ты вассал %s" % _factions.get_faction(f).get("gen", f), Color("#a5c77b"))
	grid.columns = 1
	grid.add_child(TroopList.cell("Жалованье: %d золота в день" % clans.pay(), GameSkin.PARCH, 15))
	var strikes := int(p.strikes)
	var miss := TroopList.cell("Неявки на зов: %d из 3%s" % [strikes, " — ещё одна, и сюзерен изгонит" if strikes == 2 else ""], TroopList.WARN if strikes >= 2 else GameSkin.PARCH, 15)
	miss.name = "Strikes"
	grid.add_child(miss)
	grid.add_child(_bar("StrikesBar", strikes / 3.0, TroopList.WARN if strikes >= 2 else Color("#d9a35a"), "После трёх неявок сюзерен изгоняет со службы."))
	if p.summons is Dictionary:
		var t: Dictionary = state.map.settlement_by_id(p.summons.tid)
		var call := HBoxContainer.new()
		call.name = "Summons"
		call.add_theme_constant_override("separation", 8)
		grid.add_child(call)
		var text := TroopList.cell("Зов: %s%s" % [t.get("name", "?"), " — ты участвовал" if p.summons.joined else ", явиться до дня %d" % ceili(p.summons.until / 24.0)], Color("#a5c77b") if p.summons.joined else GameSkin.BRASS, 15)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		call.add_child(text)
		if not t.is_empty():
			var go := TroopList.small(make_button({"sound": "click", "text": "На карте", "hint": "Показать %s на карте" % t.get("name", ""),
				"call": func(): map_target.emit(float(t.x), float(t.y)); close_window()}))
			go.name = "SummonsMap"
			call.add_child(go)
	else:
		grid.add_child(TroopList.cell("Зова нет. Когда сюзерен соберёт войско, приходи к осаждаемому городу: это награда и шанс на лен.", GameSkin.MUTED, 14))
	var leave := make_button({"sound": "click", "text": "Точно уйти? Отношения −20" if _leave_confirm else "Оставить службу",
		"hint": "Отношения с фракцией ухудшатся на 20",
		"call": func():
			if _leave_confirm:
				_leave_confirm = false
				clans.leave()
			else:
				_leave_confirm = true})
	leave.name = "Leave"
	leave.size_flags_horizontal = Control.SIZE_SHRINK_END
	grid.add_child(leave)
	_stretch(grid)

## «Расклад сил»: a row per living faction — crest, name and ruler, holdings, clans and the crests of its enemies.
func _powers(p, here: String) -> void:
	var clans = state.clans
	var grid := TroopList.table(body, "Powers", "Расклад сил", "кто с кем воюет", GameSkin.MUTED)
	grid.columns = 5
	for head in ["", "Фракция", "Владений", "Родов", "Воюет с"]:
		grid.add_child(TroopList.cell(head, GameSkin.MUTED, 12))
	for x in state.wars.factions_alive():
		var faction: Dictionary = _factions.get_faction(x)
		grid.add_child(TroopList.icon(OriginalArt.crest(x), 26))
		var block := VBoxContainer.new()
		block.name = "Power_" + x
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.add_theme_constant_override("separation", -2)
		var name_text := String(faction.get("name", x)) + ("  · твой сюзерен" if x == p.liege else ("  · этот город" if x == here else ""))
		var n := TroopList.cell(name_text, Color("#a5c77b") if x == p.liege else (GameSkin.BRASS if x == here else GameSkin.PARCH), 15)
		n.add_theme_font_override("font", GameSkin.BODY_BOLD)
		block.add_child(n)
		var rl: Dictionary = clans.ruler_of(x)
		block.add_child(TroopList.cell(rl.name if not rl.is_empty() else ("междуцарствие" if clans.kingless(x) else "—"), GameSkin.MUTED, 12))
		grid.add_child(block)
		var holds := TroopList.cell(str(state.wars.hold_of(x).all), GameSkin.PARCH, 15)
		holds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(holds)
		var houses := TroopList.cell(str(clans.of_faction(x).size()), GameSkin.PARCH, 15)
		houses.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(houses)
		var foes := HBoxContainer.new()
		foes.name = "Foes_" + x
		foes.add_theme_constant_override("separation", 4)
		foes.custom_minimum_size.x = 150
		for k in state.wars.wars:
			var parts: PackedStringArray = k.split("|")
			if x in parts:
				var foe: String = parts[1] if parts[0] == x else parts[0]
				var crest := TroopList.icon(OriginalArt.crest(foe), 24)
				crest.name = "Foe_" + foe
				crest.tooltip_text = _factions.get_faction(foe).get("name", foe)
				crest.mouse_filter = Control.MOUSE_FILTER_STOP
				foes.add_child(crest)
		if foes.get_child_count() == 0:
			foes.add_child(TroopList.cell("мир", Color("#a5c77b"), 14))
		grid.add_child(foes)

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
	note("Проценты — разница с обычной ценой: зелёное выгодно, красное нет. Покупай там, где товар делают, продавай, где его не хватает.")
	var mine: Array = []
	var theirs: Array = []
	var worth := 0
	for id in market.goods:
		var have := int(p.inv.get(id, 0))
		if have > 0:
			mine.append(id)
			worth += have * int(market.sell_price(p.rel, fx, settlement, m, id))
		if int(m.stock.get(id, 0)) > 0:
			theirs.append(id)
	var sides := _trade_sides("GoodsTable")
	var cargo := _trade_side(sides, "CargoGoods", "Твой обоз", "всё уйдёт за ≈%d" % worth if worth > 0 else "", "В обозе нет товаров.", mine.size())
	for id in mine:
		_goods_sell_line(cargo, p, fx, m, id)
	var shop := _trade_side(sides, "MerchantGoods", "Торговец", "денег %d" % int(m.gold), "Сегодня товаров нет.", theirs.size())
	for id in theirs:
		_goods_buy_line(shop, p, fx, m, men, id)

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

## Two cards side by side: what the player can sell on the left, what the merchant sells on the right.
func _trade_sides(sides_name: String) -> HBoxContainer:
	var sides := HBoxContainer.new()
	sides.name = sides_name
	sides.add_theme_constant_override("separation", 8)
	body.add_child(sides)
	return sides

## One side: a card with a header (title and a short sum) and a table icon, name, price, buttons. Returns the table;
## with nothing to list the card says `empty` instead.
func _trade_side(sides: HBoxContainer, side_name: String, title: String, detail: String, empty: String, rows: int, extra: Control = null) -> GridContainer:
	var card := card_panel()
	card.name = side_name
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var t := Label.new()
	t.text = title
	GameSkin.title(t, 19)
	head.add_child(t)
	var d := _cell(detail, GameSkin.MUTED, 14)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(d)
	if extra != null:
		head.add_child(extra)
	var grid := GridContainer.new()
	grid.name = "Table"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	if rows == 0:
		var e := _cell(empty, GameSkin.MUTED, 15)
		e.name = "Empty"
		col.add_child(e)
	return grid

## Icon, name with a small line under it, price; the caller adds the buttons.
func _trade_line(grid: GridContainer, icon: Texture2D, name_text: String, name_color: Color, info: String, price: Control, mark := {}) -> void:
	grid.add_child(_icon(icon, 26))
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", -2)
	var n := _cell(name_text, name_color, 15)
	n.add_theme_font_override("font", GameSkin.BODY_BOLD)
	n.clip_text = true
	n.tooltip_text = name_text
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	block.add_child(n)
	var under := HBoxContainer.new()
	under.add_theme_constant_override("separation", 6)
	if not mark.is_empty():
		var m := _cell(String(mark.text), mark.color, 12)
		m.name = "Compare"
		m.tooltip_text = String(mark.get("hint", ""))
		m.mouse_filter = Control.MOUSE_FILTER_PASS
		under.add_child(m)
	var i := _cell(info, GameSkin.MUTED, 12)
	i.clip_text = true
	i.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	under.add_child(i)
	block.add_child(under)
	grid.add_child(block)
	grid.add_child(price)

func _actions(grid: GridContainer, defs: Array) -> void:
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	actions.alignment = BoxContainer.ALIGNMENT_END
	for def in defs:
		var b := make_button(def)
		_small(b)
		actions.add_child(b)
	grid.add_child(actions)

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

func _goods_info(id: String) -> String:
	var g: Dictionary = state.market.goods[id]
	var food := int(Economy.FOOD_VALUE.get(id, 0))
	return ("еда %d порц. · вес %s" % [food, str(g.w)]) if food > 0 else "вес %s" % str(g.w)

## A good in the cargo: how many, what it fetches here, sell one or all.
func _goods_sell_line(grid: GridContainer, p, fx: Dictionary, m: Dictionary, id: String) -> void:
	var market = state.market
	var sell_p: int = market.sell_price(p.rel, fx, settlement, m, id)
	var have := int(p.inv.get(id, 0))
	_trade_line(grid, GameSkin.icon(GOOD_ICONS.get(id, "sack")), String(market.goods[id].n), GameSkin.PARCH,
		"×%d · %s" % [have, _goods_info(id)], _price(sell_p, market.base_price(id) * 0.92, true))
	var can: bool = int(m.gold) >= sell_p
	var why := "" if can else " — " + Market.WHY.merchant.to_lower()
	_actions(grid, [
		{"text": "−1", "hint": "Продать 1 за %d зол.%s" % [sell_p, why], "disabled": not can, "call": func(): _trade(market.sell(p, fx, settlement, state.clock.day, id, 1), "продано")},
		{"text": "Все", "hint": "Продать все %d за ≈%d зол.%s" % [have, have * sell_p, why], "disabled": not can, "call": func(): _trade(market.sell(p, fx, settlement, state.clock.day, id, have), "продано")}])

## A good the merchant has: stock, price, buy one or ten.
func _goods_buy_line(grid: GridContainer, p, fx: Dictionary, m: Dictionary, men: int, id: String) -> void:
	var market = state.market
	var buy_p: int = market.buy_price(p.rel, fx, settlement, m, id)
	var have := int(p.inv.get(id, 0))
	var info := "есть %d · %s" % [int(m.stock.get(id, 0)), _goods_info(id)]
	if have > 0:
		info += " · у тебя %d" % have
	_trade_line(grid, GameSkin.icon(GOOD_ICONS.get(id, "sack")), String(market.goods[id].n), GameSkin.PARCH, info,
		_price(buy_p, market.base_price(id) * 1.08, false))
	var why := _buy_block(p, fx, men, id, buy_p)
	_actions(grid, [
		{"text": "+1", "hint": why if why != "" else "Купить 1 за %d зол." % buy_p, "disabled": why != "", "call": func(): _trade(market.buy(p, fx, settlement, state.clock.day, id, 1, men), "куплено")},
		{"text": "+10", "hint": why if why != "" else "Купить до 10, сколько хватит денег и места", "disabled": why != "", "call": func(): _trade(market.buy(p, fx, settlement, state.clock.day, id, 10, men), "куплено")}])

## Why one more `id` cannot be bought now, or "".
func _buy_block(p, fx: Dictionary, men: int, id: String, price: int) -> String:
	var market = state.market
	if p.gold < price:
		return Market.WHY.gold
	if market.cargo_weight(p.inv) + market.weight(id) > market.cargo_cap(p, fx, men) + 1e-6:
		return Market.WHY.weight
	return ""

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
		item_card(ItemCard.describe(picked, _worn(p, picked), true), [{"text": "Закрыть", "call": func(): _trade_pick = ""}])
	var mine: Array = []
	var theirs: Array = []
	var worth := 0
	for id in p.inv:
		if market.is_gear(id) and int(p.inv[id]) > 0:
			mine.append(id)
			worth += int(p.inv[id]) * int(market.sell_price(p.rel, fx, settlement, m, id))
	for id in m.stock:
		if market.is_gear(id) and int(m.stock[id]) > 0:
			theirs.append(id)
	mine.sort_custom(_gear_order)
	theirs.sort_custom(_gear_order)
	note("Надетое не продаётся: сначала сними его в окне отряда. ▲/▼ — разница с надетым в том же слоте, «Обзор» — вещь целиком.")
	var sides := _trade_sides("GearTable")
	var all_button: Button = null
	if not mine.is_empty():
		all_button = make_button({"text": "Продать все", "hint": "Продать все трофеи из обоза за ≈%d зол." % worth, "sound": "", "call": func(): _sell_all(p, fx, mine)})
		all_button.name = "SellAllGear"
		_small(all_button)
	var cargo := _trade_side(sides, "CargoGear", "Твой обоз", "всё уйдёт за ≈%d" % worth if worth > 0 else "", "Трофеев в обозе нет.", mine.size(), all_button)
	for id in mine:
		_gear_line(cargo, p, fx, m, men, id, true)
	var shop := _trade_side(sides, "MerchantGear", "Оружейник", "денег %d" % int(m.gold), "Сегодня оружейник пуст.", theirs.size())
	for id in theirs:
		_gear_line(shop, p, fx, m, men, id, false)

func _gear_order(x: String, y: String) -> bool:
	var a: Dictionary = state.market.gear[x]
	var b: Dictionary = state.market.gear[y]
	var sa: int = SLOT_ORDER.find(String(a.get("slot", "")))
	var sb: int = SLOT_ORDER.find(String(b.get("slot", "")))
	return sa < sb if sa != sb else int(a.get("tier", 0)) < int(b.get("tier", 0))

## The item worn in the slot of `item`, or {}.
func _worn(p, item: Dictionary) -> Dictionary:
	var eq: Dictionary = HeroEquip.ensure(p.hero)
	var worn_id = eq.get(item.get("slot"))
	return state.market.gear.get(String(worn_id), {}) if worn_id != null else {}

## ▲ / ▼ of the main figure (damage, block, speed or armour) against the worn item of that slot.
func _compare(p, item: Dictionary) -> Dictionary:
	var worn := _worn(p, item)
	if worn.is_empty():
		return {"text": "▲ слот пуст", "color": GOOD_PRICE, "hint": "В этом слоте ничего не надето"}
	if String(worn.get("id", "")) == String(item.get("id", "-")):
		return {"text": "надето", "color": GameSkin.MUTED, "hint": "Такая же вещь уже надета"}
	var d := ItemCard.delta(item, worn, "dmg" if item.has("dmg") else "v")
	if d.is_empty():
		return {"text": "=", "color": GameSkin.MUTED, "hint": "Как надетое: %s" % String(worn.get("name", ""))}
	return {"text": String(d.text), "color": GOOD_PRICE if int(d.trend) > 0 else BAD_PRICE, "hint": "Против надетого: %s" % String(worn.get("name", ""))}

func _gear_line(grid: GridContainer, p, fx: Dictionary, m: Dictionary, men: int, id: String, selling: bool) -> void:
	var market = state.market
	var it: Dictionary = market.gear[id]
	var tier: Array = ItemCard.TIERS[clampi(int(it.get("tier", 0)), 0, 3)]
	var count := int(p.inv.get(id, 0)) if selling else int(m.stock.get(id, 0))
	var info := "%s · %s · вес %s" % [_slot(it), _tier(it), str(it.get("w", 0))]
	if count > 1:
		info = ("×%d · " if selling else "есть %d · ") % count + info
	var base: float = market.base_price(id)
	var price: int = market.sell_price(p.rel, fx, settlement, m, id) if selling else market.buy_price(p.rel, fx, settlement, m, id)
	_trade_line(grid, OriginalArt.item_icon(id), String(it.name), Color(tier[1]), info,
		_price(price, base * (0.5 if selling else 1.25), selling), _compare(p, it))
	var look := {"text": "Обзор", "hint": "Свойства вещи и сравнение с надетой", "call": func(): _trade_pick = id}
	if selling:
		var can: bool = int(m.gold) >= price
		_actions(grid, [look, {"text": "Продать", "hint": ("Продать за %d зол." % price) if can else Market.WHY.merchant, "disabled": not can, "call": func(): _trade(market.sell(p, fx, settlement, state.clock.day, id, 1), "продано")}])
	else:
		var why := _buy_block(p, fx, men, id, price)
		_actions(grid, [look, {"text": "Купить", "hint": why if why != "" else "Купить за %d зол." % price, "disabled": why != "", "call": func(): _trade(market.buy(p, fx, settlement, state.clock.day, id, 1, men), "куплено")}])

## Sells every piece of gear in the cargo the merchant can pay for.
func _sell_all(p, fx: Dictionary, ids: Array) -> void:
	var market = state.market
	var n := 0
	var total := 0
	var why := ""
	for id in ids:
		var r: Dictionary = market.sell(p, fx, settlement, state.clock.day, id, int(p.inv.get(id, 0)))
		n += int(r.n)
		total += int(r.sum)
		if String(r.why) != "":
			why = String(r.why)
	if n > 0:
		UiSounds.play(self, "coin")
		_flash = "продано трофеев: %d за %d зол.%s" % [n, total, (". " + Market.WHY[why]) if why != "" else ""]
	elif why != "":
		_flash = Market.WHY[why]

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

func _trade(result: Dictionary, verb: String) -> void:
	if int(result.get("n", 0)) > 0:
		UiSounds.play(self, "coin")
	var why := String(result.get("why", ""))
	if int(result.get("n", 0)) > 0:
		_flash = "%s %d за %d зол.%s" % [verb, int(result.n), int(result.sum), (" " + Market.WHY[why]) if why != "" else ""]
	elif why != "":
		_flash = Market.WHY[why]
