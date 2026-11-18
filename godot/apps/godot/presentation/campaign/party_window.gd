extends "res://apps/godot/presentation/campaign/modal_window.gd"
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## Party, hero and journal windows (openPanel in src/06_ui.js).
const Economy = preload("res://core/campaign/economy/party_economy.gd")
const CompanionText = preload("res://apps/godot/presentation/campaign/companion_text.gd")
const TABS := [["troops", "Отряд"], ["hero", "Герой"], ["gear", "Обоз"], ["quests", "Задания"], ["factions", "Фракции"], ["comps", "Спутники"], ["journal", "Журнал"]]
const HeroGear = preload("res://core/equipment/rules/hero_gear.gd")
const HeroEquip = preload("res://core/equipment/rules/hero_equip.gd")
const QuestCard = preload("res://apps/godot/presentation/campaign/quest_card.gd")
const ItemCard = preload("res://apps/godot/presentation/campaign/item_card.gd")
const GearComparison = preload("res://apps/godot/presentation/campaign/gear_comparison.gd")
const TroopList = preload("res://apps/godot/presentation/campaign/troop_list.gd")
const SLOT_NAMES := {"head": "Голова", "body": "Тело", "hands": "Руки", "legs": "Ноги", "melee": "Оружие", "ranged": "Стрелковое", "shield": "Щит", "horse": "Конь"}
var _who := ""
var _selected_gear := ""
var _selected_action := Callable()
var _last_tile := ""
var _last_tap := 0
var _bag_filter := "all"
var _slot_filter := ""
var _selected_owner := ""
var _faction := ""
signal quest_target(x: float, y: float)
const FactionCatalog = preload("res://core/campaign/data/faction_catalog.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
var _fcat := FactionCatalog.new()
var _fcat_loaded := false
var _confirm := ""
var _pick := ""
## «Отряд»: promote "one" man per click or "all" the purse allows.
var _promote_mode := "one"
## The last promotion, shown under the title once after the redraw.
var _flash := ""
var state: RefCounted
## HeroStats.preview(profile, gear, effects) -> Dictionary, set by composition.
var stat_preview := Callable()

func open_for(world_state: RefCounted, tab: String = "troops") -> void:
	state = world_state
	set_tabs(TABS, tab)
	open_window()

func render() -> void:
	if state == null:
		return
	set_width(1220)
	body.add_theme_constant_override("separation", 10)
	var p = state.player
	var fx: Dictionary = state.player_effects()
	title_label.text = p.hero.name
	sub_label.text = "Уровень %d · золото %d · порций %d" % [p.hero.lvl, p.gold, Economy.provisions(p)]
	if _flash != "":
		sub_label.text += "   ·   " + _flash
		_flash = ""
	set_tabs(TABS, current_tab if current_tab != "" else "troops")
	clear_body()
	match current_tab:
		"hero":
			_hero(p)
		"journal":
			_journal()
		"comps":
			_comps(p)
		"quests":
			_quests(p)
		"gear":
			_gear(p)
		"factions":
			_factions_tab(p)
		_:
			_troops(p, fx)

## «Отряд»: a one-line summary, then the troops in compact tables, those ready for promotion always first.
func _troops(p, fx: Dictionary) -> void:
	var catalog = state.roster.catalog
	var count := Economy.troop_count(p.troops)
	var cap := Economy.size_cap(p.hero, fx)
	var portions := Economy.provisions(p)
	var daily := maxi(1, ceili(count / 6.0))
	var line := TroopList.summary(body, "TroopSummary")
	TroopList.chip(line, "men", "Отряд %d / %d" % [count, cap], TroopList.WARN if count > cap else GameSkin.PARCH,
		"Отряд больше лимита: новых бойцов не нанять. Лимит растёт с уровнем и харизмой героя." if count > cap else "Лимит зависит от уровня, харизмы и перков героя.")
	TroopList.chip(line, "coin", "Жалованье %d в день" % Economy.wage_day(p.troops, func(t): return float(catalog.get_troop(t).wage), fx))
	TroopList.chip(line, "food", "Провизия %d порц., на %d дн." % [portions, portions / daily], TroopList.WARN if portions < daily * 3 else GameSkin.PARCH)
	TroopList.chip(line, "helm", TroopList.composition(p.troops, catalog), GameSkin.PARCH, "Группы для приказов в бою")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	body.add_child(head)
	_section(head, "helm", "Состав отряда")
	head.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	TroopList.switch(head, "PromoteMode", "Повышать:", [["one", "по одному", "Одна кнопка — один боец: так рекрутов можно развести по разным веткам"], ["all", "всех", "Одна кнопка — все бойцы этого типа, на кого хватит золота"]], _promote_mode,
		func(mode: String): _promote_mode = mode; render())
	if p.troops.is_empty():
		_empty_state(body, "men", "В отряде никого", "Нанимай людей в городах, замках и деревнях.")
		return
	var groups := {"ready": [], "poor": [], "top": []}
	for s in p.troops:
		var troop: Dictionary = catalog.get_troop(s.type)
		groups[_promotion_group(troop, p.gold, fx)].append(s)
	for key in groups:
		groups[key].sort_custom(func(a, b): return _troop_order(catalog.get_troop(a.type), int(a.n), catalog.get_troop(b.type), int(b.n)))
	var titles := {"ready": ["Готовы к повышению", TroopList.GOOD], "poor": ["Не хватает золота на повышение", Color("#d9a35a")], "top": ["Высшая ступень", GameSkin.MUTED]}
	for key in ["ready", "poor", "top"]:
		if groups[key].is_empty():
			continue
		var men := 0
		for s in groups[key]: men += int(s.n)
		var grid := TroopList.table(body, "TroopGroup_" + key, titles[key][0], TroopList.men(men), titles[key][1])
		for s in groups[key]:
			_troop_line(grid, p, fx, catalog.get_troop(s.type), int(s.n), count)

## "ready": can grow and the purse pays for one; "poor": can grow, no gold; "top": nowhere to grow.
static func _promotion_group(troop: Dictionary, gold: int, fx: Dictionary) -> String:
	if troop.get("up", []).is_empty():
		return "top"
	return "ready" if gold >= Economy.upgrade_cost(troop, fx) else "poor"

## Higher tier first, then the bigger stack, then the name.
static func _troop_order(a: Dictionary, an: int, b: Dictionary, bn: int) -> bool:
	if int(a.tier) != int(b.tier):
		return int(a.tier) > int(b.tier)
	if an != bn:
		return an > bn
	return String(a.name) < String(b.name)

func _troop_line(grid: GridContainer, p, fx: Dictionary, troop: Dictionary, n: int, party_count: int) -> void:
	var actions: Array = []
	var cost := Economy.upgrade_cost(troop, fx)
	for up_id in troop.get("up", []):
		var up: Dictionary = state.roster.catalog.get_troop(up_id)
		var k := mini(n, p.gold / cost) if _promote_mode == "all" else mini(1, p.gold / cost)
		var def := {"sound": "coin", "disabled": k < 1, "call": func(): _promote(p, fx, troop, up, k)}
		if _promote_mode == "all" and k > 0:
			def.text = "→ %s ×%d · %d" % [up.name, k, k * cost]
			def.hint = "Повысить %d из %d за %d золота" % [k, n, k * cost]
		else:
			def.text = "→ %s · %d" % [up.name, cost]
			def.hint = "Повысить одного бойца за %d золота" % cost
		if k < 1:
			def.hint = "Нужно %d золота, у тебя %d" % [cost, p.gold]
		var b := TroopList.small(make_button(def))
		b.name = "Promote_%s_%s" % [troop.id, up_id]
		actions.append(b)
	var dismiss := TroopList.small(make_button({"text": "Распустить", "disabled": party_count <= 1,
		"hint": "Отпустить одного бойца" if party_count > 1 else "Последнего бойца не распустить",
		"call": func(): Economy.remove_troops(p.troops, troop.id, 1)}))
	dismiss.name = "Dismiss_" + troop.id
	actions.append(dismiss)
	TroopList.row(grid, troop.id, troop.id, "%s ×%d" % [troop.name, n],
		["ступень %s · %s · жалованье %d" % [TroopList.tier_pips(int(troop.tier)), TroopList.group_name(troop), int(troop.wage)]], actions)

func _promote(p, fx: Dictionary, troop: Dictionary, up: Dictionary, k: int) -> void:
	var gold: int = p.gold
	var done := Economy.upgrade(p, troop, up.id, fx, k)
	if done > 0:
		_flash = "Повышен: %s → %s ×%d (−%d золота)" % [troop.name, up.name, done, gold - int(p.gold)]

func _hero(p) -> void:
	var h: Dictionary = p.hero
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	_journal_panel(body, GameSkin.BRASS).add_child(top)
	var resolved := HeroGear.resolve(h, state.gear)
	var picture := TextureRect.new()
	picture.texture = OriginalArt.compose(resolved.look).portrait
	picture.custom_minimum_size = Vector2(105, 125)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(picture)
	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(stats)
	var name_label := Label.new()
	name_label.text = "%s · Уровень %d" % [h.name, h.lvl]
	GameSkin.title(name_label, 28)
	stats.add_child(name_label)
	var xp := ProgressBar.new()
	xp.max_value = 100 + int(h.lvl) * 80
	xp.value = h.xp
	xp.custom_minimum_size.y = 12
	xp.show_percentage = false
	stats.add_child(xp)
	_icon_line(stats, "book", "Опыт %d / %d" % [h.xp, int(xp.max_value)])
	var hero_stats := HBoxContainer.new()
	hero_stats.add_theme_constant_override("separation", 14)
	stats.add_child(hero_stats)
	_icon_line(hero_stats, "shield", "Броня %d" % roundi(resolved.armor))
	_icon_line(hero_stats, "men", "Отряд %d / %d" % [Economy.troop_count(p.troops), Economy.size_cap(h, state.player_effects())])
	var points := VBoxContainer.new()
	top.add_child(points)
	for text in ["Очки атрибутов: %d" % h.pts, "Очки перков: %d" % h.pp]:
		var label := Label.new()
		label.text = text
		GameSkin.title(label, 18)
		points.add_child(label)
	var cargo := Button.new()
	cargo.text = "Открыть обоз"
	cargo.pressed.connect(func(): current_tab = "gear"; render())
	cargo.icon = GameSkin.icon("bag")
	cargo.add_theme_constant_override("icon_max_width", 20)
	points.add_child(cargo)
	note("Все перки доступны сразу. У каждого три уровня; следующий требует более высокого значения атрибута и стоит одно очко перков.")
	for key in Economy.ATTRS:
		var group := HBoxContainer.new()
		group.add_theme_constant_override("separation", 10)
		body.add_child(group)
		var attr := PanelContainer.new()
		attr.custom_minimum_size.x = 166
		attr.add_theme_stylebox_override("panel", GameSkin.box("plank", 10))
		group.add_child(attr)
		var attr_col := VBoxContainer.new()
		attr.add_child(attr_col)
		var title := Label.new()
		title.text = "%s   %d" % [Economy.ATTRS[key][0], h.get(key, 1)]
		GameSkin.title(title, 20)
		var attr_title := HBoxContainer.new()
		attr_col.add_child(attr_title)
		attr_title.add_child(_texture(GameSkin.icon({"str":"sword", "vit":"heart", "agi":"horse", "int":"book", "cha":"flag"}.get(key, "helm")), 20))
		attr_title.add_child(title)
		var detail := Label.new()
		detail.text = Economy.ATTRS[key][1]
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size.x = 140
		detail.add_theme_font_size_override("font_size", 13)
		attr_col.add_child(detail)
		var plus := Button.new()
		plus.text = "+"
		plus.disabled = int(h.pts) < 1
		plus.pressed.connect(func(): Economy.spend_attribute(h, key); UiSounds.play(self, "order"); render())
		attr_col.add_child(plus)
		var perks := GridContainer.new()
		perks.columns = 4 if get_viewport().get_visible_rect().size.x >= 1000 else 2
		perks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.add_child(perks)
		for perk in state.perks.list():
			if perk.a == key:
				perks.add_child(_perk_card(h, perk))

func _perk_card(h: Dictionary, perk: Dictionary) -> Button:
	var rank := Economy.perk_rank(h, perk.id)
	var why := Economy.perk_why(h, perk)
	var button := Button.new()
	button.custom_minimum_size = Vector2(160, 150)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = not why.is_empty()
	button.tooltip_text = "%s\nТребуется %s: %s" % [perk.n, Economy.ATTRS[perk.a][0], str(perk.req)]
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#403116") if rank == 3 else Color("#251c14")
	box.border_color = GameSkin.BRASS if rank > 0 else (Color("#9bd25b") if why.is_empty() else Color("#ffffff2e"))
	box.set_border_width_all(2)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(9)
	for state_name in ["normal", "disabled"]:
		button.add_theme_stylebox_override(state_name, box)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 9)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	for i in 4:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		match i:
			0: label.text = "◆".repeat(rank) + "◇".repeat(3 - rank) + "   " + " · ".join(perk.req.map(func(v): return str(int(v))))
			1: label.text = perk.n
			2:
				label.text = OriginalArt.MANIFEST.perks.get(perk.id, "")
				label.size_flags_vertical = Control.SIZE_EXPAND_FILL
			3: label.text = "Максимум" if rank >= 3 else ("Изучить · 1 очко" if why.is_empty() else why)
		label.add_theme_font_size_override("font_size", 12 if i != 1 else 17)
		label.add_theme_color_override("font_color", GameSkin.BRASS if i in [0, 1] and rank > 0 else GameSkin.PARCH)
		if i == 1: label.add_theme_font_override("font", GameSkin.DISPLAY)
		if i == 3:
			label.add_theme_color_override("font_color", Color("#a5c77b") if why.is_empty() else GameSkin.MUTED)
		col.add_child(label)
	button.pressed.connect(func(): Economy.buy_perk(h, perk); UiSounds.play(self, "order"); render())
	return button

const CHRONICLE_LIMIT := 30
const CHRONICLE_COLORS := [Color("#d8c9a5"), Color("#e0705a"), Color("#7fb2e0"), Color("#8fc24f")]

## Chronicle (jqChronicle in src/06f_jquests.js): last 30 entries, newest first, grouped by day.
func _journal() -> void:
	if state.journal.is_empty():
		_empty_state(body, "book", "История только начинается", "Здесь появятся события похода: войны, победы, задания и судьбы твоих соратников.")
		return
	var day := -1
	var box: VBoxContainer = null
	for e in state.journal.slice(0, CHRONICLE_LIMIT):
		if int(e.day) != day:
			day = int(e.day)
			var head := Label.new()
			head.text = "День %d%s" % [day, " · сегодня" if day == state.clock.day else ""]
			GameSkin.title(head, 18)
			body.add_child(head)
			box = VBoxContainer.new()
			box.name = "ChronicleDay_%d" % day
			_journal_panel(body).add_child(box)
		box.add_theme_constant_override("separation", 9)
		var line := Label.new()
		line.name = "ChronicleEvent"
		line.text = ["• ", "! ", "› ", "+ "][clampi(int(e.get("kind", 0)), 0, 3)] + String(e.text)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_color_override("font_color", CHRONICLE_COLORS[clampi(int(e.get("kind", 0)), 0, 3)])
		box.add_child(line)

func _comps(p) -> void:
	var comps = state.companions
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 10)
	body.add_child(metrics)
	_stat_tile(metrics, "heart", "Спутники", "%d / %d" % [p.comps.size(), comps.COMP_MAX], "верных соратников")
	_stat_tile(metrics, "coin", "Жалованье", str(comps.wage(p)), "золота в день")
	_stat_tile(metrics, "shield", "Готовы к бою", str(p.comps.filter(func(c): return comps.fit(c)).size()), "здоровье выше 25%")
	note("Спутники бьются сами в своей группе и слушаются приказов. В бою их не убивают, а ранят: раненый ниже 25%% здоровья пропускает бои, пока не подлечится. Жалованье спутников: %d в день." % comps.wage(p))
	if p.comps.is_empty():
		_empty_state(body, "heart", "Верные соратники ещё впереди", "Загляни в городскую таверну: там можно нанять спутников и узнать об их способностях.")
	for c in p.comps.duplicate():
		var d: Dictionary = state.companion_catalog.get_companion(c.id)
		var ok: bool = comps.fit(c)
		var btn: Dictionary
		if _confirm == c.id:
			btn = {"sound": "click", "text": "Точно отпустить?", "call": func(): comps.fire(p, c.id); _confirm = ""}
		else:
			btn = {"text": "Отпустить", "call": func(): _confirm = c.id}
		var grant := {"text": "Выбери надел ↓" if _pick == c.id else "Дать надел", "call": func(): _pick = "" if _pick == c.id else c.id}
		var saved_body := body
		var card := _journal_panel(body, Color("#91af6c") if ok else Color("#c97b5c"))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		card.add_child(line)
		line.add_child(_texture(OriginalArt.compose(HeroGear.resolve(c, state.gear).look).portrait, 86))
		var information := VBoxContainer.new()
		information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(information)
		body = information
		row("%s · %s · ур. %d" % [c.name, d.role, c.lvl], "%s · опыт %d\n%s: %s" % ["Готов к бою" if ok else "Ранен — восстанавливается", int(c.get("xp", 0)), d.skn, CompanionText.skill_text(d, c)], [grant, btn])
		_meter(body, "CompanionHealth", c.hp, 1, Color("#91af6c") if ok else Color("#c97b5c"), "Здоровье: %d%%. Ниже 25%% спутник пропускает бой." % roundi(c.hp * 100))
		body = saved_body
		if _pick == c.id:
			_fief_pick(c)
	_vassals(p)

func _fief_pick(c: Dictionary) -> void:
	var vs = state.vassals
	var free: Array = vs.fiefs().filter(func(s): return not s.has("vass"))
	if state.player.vass.size() >= vs.MAX:
		note("Вассалов уже %d: больше не прокормить." % vs.MAX)
	elif free.is_empty():
		note("Надел — твой город или замок без вассала. Сначала возьми его: захвати или получи от сюзерена.")
	else:
		note("Вассал отдаёт тебе 30% чистого дохода надела, остальное тратит на гарнизон и свою дружину. Выбери надел:")
		for s in free:
			row("%s (%s)" % [s.name, "город" if s.kind == "town" else "замок"], "доход %d в день, гарнизон %d" % [vs.net_income(s), Economy.troop_count(state.wars.garrison_of(s))],
				[{"sound": "coin", "text": "Отдать", "call": func(): sub_label.text = vs.grant(c.id, s.id); _pick = ""}])

func _vassals(p) -> void:
	var vs = state.vassals
	if p.vass.is_empty():
		return
	heading("Вассалы")
	note("Вассал живёт на наделе и содержит его гарнизон, платит тебе подать и сам нанимает дружину. Дружина бьёт врагов у надела и помогает отбить штурм.")
	for v in p.vass.duplicate():
		var s: Dictionary = state.map.settlement_by_id(v.sid)
		var party: Dictionary = vs.party_of(v)
		var detail := "Надел: %s · подать %d в день · казна %d\n" % [s.get("name", "—"), int(v.get("trib", 0)), roundi(float(v.gold))]
		detail += ("Дружина: %d из %d бойцов" % [Economy.troop_count(party.troops), vs.cap(v)]) if not party.is_empty() else ("Дружина разбита, соберёт новую через %d дн." % maxi(1, int(v.rest)))
		detail += "\nПриказ: %s — %s" % vs.MODES[v.get("mode", "guard")]
		var buttons: Array = []
		for m in vs.MODES:
			buttons.append({"sound": "click", "text": vs.MODES[m][0], "disabled": v.get("mode", "guard") == m, "call": func(): vs.set_mode(v.cid, m)})
		buttons.append({"sound": "coin", "text": "+200", "disabled": p.gold < 200, "call": func(): vs.give(v.cid, 200)})
		if _confirm == "v" + v.cid:
			buttons.append({"sound": "click", "text": "Точно забрать?", "call": func(): vs.revoke(v.cid); _confirm = ""})
		else:
			buttons.append({"text": "Забрать надел", "call": func(): _confirm = "v" + v.cid})
		row("%s · вассал · ур. %d" % [v.c.name, v.c.lvl], detail, buttons)

func _quests(p) -> void:
	if not _fcat_loaded:
		_fcat_loaded = ContentLoader.populate(_fcat)
	var bonus := float(state.player_effects().get("quest", 0.0))
	var ordered: Array = p.quests.filter(func(q): return not state.map.settlement_by_id(q.sid).is_empty() and not state.map.settlement_by_id(q.from).is_empty())
	ordered.sort_custom(func(a, b): return int(a.dl) < int(b.dl) or (int(a.dl) == int(b.dl) and int(a.reward) > int(b.reward)))
	_quest_summary(ordered, bonus)
	if ordered.is_empty():
		_empty_state(body, "flag", "Выбери следующий контракт", "В городах на доске заданий ждут поставки, разведка и охота на разбойников. Одновременно можно вести до %d заданий." % QUEST_LIMIT)
	var original := body
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	body.add_child(columns)
	var active := VBoxContainer.new()
	active.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active.size_flags_stretch_ratio = 1.8
	active.add_theme_constant_override("separation", 10)
	columns.add_child(active)
	body = active
	_section(body, "flag", "Активные задания", "По ближайшему сроку")
	for q in ordered:
		_quest_card(QuestCard.describe(q, state, _fcat, bonus))
	var chronicle := VBoxContainer.new()
	chronicle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chronicle.add_theme_constant_override("separation", 8)
	columns.add_child(chronicle)
	body = chronicle
	_section(body, "book", "Хроника", "Последние события")
	_journal()
	body = original

const QUEST_LIMIT := 4

## journalQuestsBody: active errands out of four, total reward, nearest deadline and errands done in the chronicle.
func _quest_summary(quests: Array, bonus: float) -> void:
	var total := 0
	for q in quests:
		total += roundi(float(q.reward) * (1.0 + bonus))
	var near: int = int(quests[0].dl) - int(state.clock.day) if not quests.is_empty() else 0
	var done: int = state.journal.filter(func(e): return String(e.text).begins_with("Задание выполнено")).size()
	var tiles := [
		["book", "%d/%d" % [quests.size(), QUEST_LIMIT], "Активных заданий", "журнал полон" if quests.size() >= QUEST_LIMIT else "можно взять ещё %d" % (QUEST_LIMIT - quests.size())],
		["coin", str(total), "Сумма наград", "золотом"],
		["hourglass", "—" if quests.is_empty() else ("просрочено" if near < 0 else ("сегодня" if near == 0 else QuestCard.days(near))), "Ближайший срок", "нет заданий" if quests.is_empty() else "до дня %d" % int(quests[0].dl)],
		["flag", str(done), "Выполнено", "по свежей хронике"],
	]
	var line := HBoxContainer.new()
	line.name = "QuestSummary"
	line.add_theme_constant_override("separation", 12)
	body.add_child(line)
	for tile in tiles:
		_stat_tile(line, tile[0], tile[2], tile[1], tile[3])

## jqCard: type and icon with «срочно»/«просрочено»/«готово к сдаче», the task, the client with his crest, distance,
## camp size, progress bar, what blocks it, reward, deadline with a time bar and «Показать на карте».
func _quest_card(card: Dictionary) -> void:
	var accent := Color("#d57860") if card.blocked else GameSkin.BRASS
	for tag in card.tags:
		if tag[1] > 0: accent = Color("#a5c77b")
		elif tag[1] < 0: accent = Color("#d57860")
	var panel := _journal_panel(body, accent)
	panel.name = "QuestCard"
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	panel.add_child(line)
	var symbol := _texture(GameSkin.icon(card.icon), 38)
	symbol.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(symbol)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 5)
	line.add_child(main)
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 6)
	main.add_child(tags)
	_badge(tags, card.type.to_upper(), GameSkin.BRASS)
	for tag in card.tags:
		var badge := Label.new()
		badge.name = "QuestTag"
		badge.text = tag[0].to_upper()
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", Color("#a5c77b") if tag[1] > 0 else Color("#f09b7d"))
		tags.add_child(badge)
	_journal_text(main, card.title, 19)
	var client := HBoxContainer.new()
	main.add_child(client)
	client.add_child(_texture(OriginalArt.crest(card.faction), 20))
	_journal_text(client, "%s · %s" % [card.from, card.faction_name], 14, true)
	_icon_line(main, "flag", card.detail)
	if card.camp_size >= 0: _icon_line(main, "men", "В лагере около %d бойцов" % card.camp_size)
	if not card.progress.is_empty():
		var progress_line := HBoxContainer.new()
		main.add_child(progress_line)
		_journal_text(progress_line, card.progress[2], 14, true)
		var count := Label.new()
		count.text = "%d / %d" % [card.progress[0], card.progress[1]]
		progress_line.add_child(count)
		_meter(main, "QuestProgress", card.progress[0], card.progress[1], accent)
	if card.warning != "":
		var warn := Label.new()
		warn.name = "QuestWarning"
		warn.text = "!  " + card.warning
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_theme_font_size_override("font_size", 14)
		warn.add_theme_color_override("font_color", Color("#f09b7d"))
		main.add_child(warn)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 182
	side.add_theme_constant_override("separation", 5)
	line.add_child(side)
	var prize := HBoxContainer.new()
	side.add_child(prize)
	prize.add_child(_texture(GameSkin.icon("coin"), 24))
	_journal_text(prize, _number(card.reward), 26)
	_journal_text(side, "золота за выполнение", 12, true)
	side.add_child(HSeparator.new())
	_icon_line(side, "hourglass", card.deadline, accent)
	_journal_text(side, card.until, 13, true)
	_meter(side, "QuestTime", card.time_left, 1, accent, "Доля оставшегося срока")
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	if not card.target.is_empty():
		var target: Dictionary = card.target
		var go := Button.new()
		go.text = "Показать на карте"
		go.icon = GameSkin.icon("flag")
		go.expand_icon = true
		go.add_theme_constant_override("icon_max_width", 18)
		go.tooltip_text = "Показать цель на карте: " + String(target.get("name", ""))
		GameSkin.primary(go)
		go.pressed.connect(func(): quest_target.emit(target.x, target.y); close_window())
		side.add_child(go)

func _gear(p) -> void:
	var gear = state.gear
	var h: Dictionary = p.hero
	for c in p.comps:
		if c.id == _who:
			h = c
	if h == p.hero:
		_who = ""
	if _selected_owner != _who:
		_selected_owner = _who
		_selected_gear = ""
		_selected_action = Callable()
		_slot_filter = ""
	var whos: Array = [{"text": "Герой", "disabled": _who == "", "call": func(): _who = ""}]
	for c in p.comps:
		whos.append({"text": c.name.split(" ")[0], "disabled": _who == c.id, "call": func(): _who = c.id})
	row("Кого одеваем", "", whos)
	var eq: Dictionary = HeroEquip.ensure(h)
	var inventory := HBoxContainer.new()
	inventory.add_theme_constant_override("separation", 18)
	body.add_child(inventory)
	var equipment := VBoxContainer.new()
	equipment.custom_minimum_size.x = 348
	_journal_panel(inventory).add_child(equipment)
	var backpack := VBoxContainer.new()
	backpack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_panel(inventory).add_child(backpack)
	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", 8)
	equipment.add_child(doll)
	var left := VBoxContainer.new()
	doll.add_child(left)
	var resolved := HeroGear.resolve(h, gear)
	var figure := OriginalArt.compose(resolved.look)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doll.add_child(center)
	var name_label := Label.new()
	name_label.text = h.name
	GameSkin.title(name_label, 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	var image := TextureRect.new()
	image.name = "EquipmentFigure"
	image.texture = figure.portrait
	image.custom_minimum_size = Vector2(150, 260)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	center.add_child(image)
	center.add_child(name_label)
	var right := VBoxContainer.new()
	doll.add_child(right)
	for i in SLOT_NAMES.size():
		var slot: String = SLOT_NAMES.keys()[i]
		var id: Variant = eq.get(slot)
		var parent: VBoxContainer = left if i < 4 else right
		var action := func(): HeroEquip.unequip(p.inv, h, slot)
		var tile := _gear_tile(String(id) if id != null else "", 1, action, slot, id == null)
		tile.name = "Equipped_" + slot
		tile.custom_minimum_size = Vector2(72, 72)
		parent.add_child(tile)
	if eq.get("ranged") != null:
		row("В руках в начале боя", "", [
			{"sound": "click", "text": "Ближнее", "disabled": h.get("sel") != "ranged", "call": func(): HeroEquip.wield(h, "melee")},
			{"sound": "click", "text": "Стрелковое", "disabled": h.get("sel") == "ranged", "call": func(): HeroEquip.wield(h, "ranged")}])
	var stats := GridContainer.new()
	stats.columns = 3
	stats.add_theme_constant_override("h_separation", 8)
	stats.add_theme_constant_override("v_separation", 10)
	equipment.add_child(stats)
	for stat in [["Броня", str(resolved.armor)], ["Урон оружия", str(resolved.weapon.get("dmg", 0))], ["Блок", "%d%%" % roundi(float(resolved.block) * 100)], ["Удар", str(resolved.weapon.get("spd", 1)) + " с"], ["Длина", str(30 + int(resolved.weapon.get("reach", 0)))], ["Урон по типу", {"cut": "Режущий", "pierce": "Колотый", "blunt": "Дробящий"}.get(resolved.weapon.get("dt", ""), "—")]]:
		var label := Label.new()
		label.text = "%s\n%s" % stat
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = 104
		stats.add_child(label)
	var bag_header := HBoxContainer.new()
	backpack.add_child(bag_header)
	var bag_title := Label.new()
	bag_title.text = "Рюкзак"
	GameSkin.title(bag_title, 21)
	bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_header.add_child(bag_title)
	for def in [["all", "Все"], ["weapons", "Оружие"], ["armor", "Броня"], ["goods", "Товары"]]:
		var button := Button.new()
		button.text = def[1]
		button.add_theme_font_size_override("font_size", 12)
		button.toggle_mode = true
		button.button_pressed = _bag_filter == def[0]
		button.pressed.connect(func(): _bag_filter = def[0]; _slot_filter = ""; render())
		bag_header.add_child(button)
	var cargo := Label.new()
	var weight: float = state.market.cargo_weight(p.inv)
	var capacity: int = state.market.cargo_cap(p, state.player_effects(), Economy.troop_count(p.troops))
	cargo.text = "Загрузка обоза: %s / %d · провизия: %d порций" % [str(weight), capacity, Economy.provisions(p)]
	backpack.add_child(cargo)
	var cargo_bar := ProgressBar.new()
	cargo_bar.max_value = capacity
	cargo_bar.value = weight
	cargo_bar.show_percentage = false
	cargo_bar.custom_minimum_size.y = 9
	backpack.add_child(cargo_bar)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	backpack.add_child(grid)
	var ids: Array = p.inv.keys().filter(func(k): return int(p.inv[k]) > 0)
	ids = ids.filter(func(id):
		var it: Dictionary = gear.get_item(id)
		if _slot_filter != "": return it.get("slot", "") == _slot_filter
		if _bag_filter == "weapons": return it.get("slot", "") in ["melee", "ranged", "shield"]
		if _bag_filter == "armor": return it.get("slot", "") in ["head", "body", "hands", "legs", "horse"]
		if _bag_filter == "goods": return it.is_empty()
		return true)
	if ids.is_empty(): _icon_line(backpack, "bag", "В этой категории пока нет предметов. Выбери другую категорию или пополни обоз в городе.")
	ids.sort()
	for id in ids:
		var item_id: String = id
		var action := func():
			if state.market.is_gear(item_id):
				var r: Dictionary = HeroEquip.equip(p.inv, h, item_id, gear)
				if r.note != "": sub_label.text = r.note
		var cargo_tile := _gear_tile(item_id, int(p.inv[item_id]), action, "cargo")
		cargo_tile.name = "Cargo_" + item_id
		grid.add_child(cargo_tile)
	for i in maxi(0, 24 - ids.size()):
		var empty := PanelContainer.new()
		empty.custom_minimum_size = Vector2(64, 64)
		var shade := StyleBoxFlat.new()
		shade.bg_color = Color("#0000002a")
		shade.border_color = Color("#ffffff0d")
		shade.set_border_width_all(2)
		empty.add_theme_stylebox_override("panel", shade)
		grid.add_child(empty)
	var hint := Label.new()
	hint.text = "Провизия: %d порций. Двойной щелчок по вещи — надеть, по слоту — снять. В бою X меняет оружие." % Economy.provisions(p)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", GameSkin.MUTED)
	backpack.add_child(hint)
	if _selected_gear != "":
		var it: Dictionary = gear.get_item(_selected_gear)
		if not it.is_empty():
			var worn := _selected_gear in eq.values()
			var current: Dictionary = gear.get_item(String(eq.get(it.slot))) if eq.get(it.slot) != null else {}
			item_card(ItemCard.describe(it, current, not worn), [{"sound": "click" if worn else "order", "text": "Снять" if worn else "Надеть", "call": _selected_action}])
			if not _selected_gear in eq.values():
				_comparison(GearComparison.compare(h, it, gear, state.perks, stat_preview))
		else:
			var good: Dictionary = state.market.goods.get(_selected_gear, {}).duplicate()
			good["id"] = _selected_gear
			item_card(ItemCard.describe(good), [])
			note("Торговый товар · продай на рынке города")
	else:
		note("Выбери предмет, чтобы узнать о нём больше. Двойной щелчок — надеть или снять.")

func _comparison(cmp: Dictionary) -> void:
	if cmp.is_empty():
		return
	var box := VBoxContainer.new()
	box.name = "GearComparison"
	body.add_child(box)
	var head := Label.new()
	head.text = cmp.title
	head.add_theme_color_override("font_color", GameSkin.MUTED)
	box.add_child(head)
	for r in cmp.rows:
		var line := HBoxContainer.new()
		box.add_child(line)
		var name_label := Label.new()
		name_label.text = r.name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var values := Label.new()
		values.text = "%s → %s" % [GearComparison.fmt(r.old), GearComparison.fmt(r.next)]
		values.custom_minimum_size.x = 110
		line.add_child(values)
		var delta := Label.new()
		delta.text = ("+" if float(r.delta) > 0.0 else "") + GearComparison.fmt(r.delta)
		delta.custom_minimum_size.x = 56
		delta.add_theme_color_override("font_color", [Color("#e0705a"), GameSkin.MUTED, Color("#8fc24f")][int(r.trend) + 1])
		line.add_child(delta)
	if cmp.note != "":
		note(cmp.note)

func _gear_tile(id: String, count: int, action: Callable, location: String, empty := false) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(64, 64)
	tile.expand_icon = true
	tile.add_theme_constant_override("icon_max_width", 42)
	tile.add_theme_font_size_override("font_size", 13)
	tile.clip_text = true
	if empty:
		tile.text = SLOT_NAMES.get(location, "—")
		tile.modulate.a = 0.5
		tile.icon = GameSkin.icon({"head": "helm", "body": "body", "hands": "hands", "legs": "legs", "melee": "sword", "ranged": "bow", "shield": "shield", "horse": "horse"}.get(location, "bag"))
		tile.pressed.connect(func(): _slot_filter = location; render())
		return tile
	tile.icon = OriginalArt.item_icon(id)
	tile.text = ""
	if location == "cargo":
		var amount := Label.new()
		amount.name = "Quantity"
		amount.text = str(count)
		amount.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		amount.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		amount.offset_left = -26
		amount.offset_right = -5
		amount.offset_top = 2
		amount.offset_bottom = 18
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.add_theme_font_size_override("font_size", 12)
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(amount)
	var it: Dictionary = state.gear.get_item(id)
	tile.tooltip_text = it.get("name", id) + ("\n" + _stats(it) if not it.is_empty() else "")
	if location == "cargo" and not it.is_empty():
		var who: Dictionary = state.player.hero
		for c in state.player.comps:
			if c.id == _who:
				who = c
		tile.tooltip_text += "\n\n" + GearComparison.text(GearComparison.compare(who, it, state.gear, state.perks, stat_preview))
	var tier: int = clampi(int(it.get("tier", 0)), 0, 3)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#21170e")
	style.border_color = [Color("#a89f8a"), Color("#8fc24f"), Color("#5fa0e6"), Color("#e5902a")][tier]
	style.set_border_width_all(2)
	style.set_content_margin_all(5)
	if id == _selected_gear:
		style.border_color = GameSkin.BRASS
		style.bg_color = Color("#59401f")
	tile.add_theme_stylebox_override("normal", style)
	tile.pressed.connect(func():
		var now := Time.get_ticks_msec()
		var key := location + "|" + id
		if key == _last_tile and now - _last_tap < 420:
			action.call()
			_last_tile = ""
		else:
			_last_tile = key
			_last_tap = now
		_selected_gear = id
		_selected_action = action
		render())
	return tile

static func _stats(it: Dictionary) -> String:
	if it.is_empty():
		return ""
	var parts: Array = []
	if it.has("dmg"):
		parts.append("урон %d" % roundi(float(it.dmg)))
	if it.has("v"):
		parts.append(("защита %s" % str(it.v)) if it.slot != "shield" else ("блок %s" % str(it.v)))
	if it.has("hands") and int(it.hands) == 2:
		parts.append("двуручное")
	parts.append("цена %d" % int(it.get("price", 0)))
	return " · ".join(parts)

## States: power, ruler, nobles, holdings, wars (journalFactionsBody in src/06g_jfactions.js).
func _factions_tab(p) -> void:
	if not _fcat_loaded:
		_fcat_loaded = ContentLoader.populate(_fcat)
	var alive: Array = state.wars.factions_alive()
	var power := {}
	var strongest := 1.0
	for faction in Rules.REAL_FACTIONS:
		power[faction] = state.wars.power(faction) if faction in alive else 0.0
		strongest = maxf(strongest, power[faction])
	var order: Array = Rules.REAL_FACTIONS.duplicate()
	order.sort_custom(func(a, b): return power[a] > power[b])
	if _faction == "" or not _faction in order:
		_faction = p.liege if p.liege in alive else order[0]
	var layout := HBoxContainer.new()
	layout.name = "FactionLayout"
	layout.custom_minimum_size.y = maxf(320, get_viewport().get_visible_rect().size.y - 282)
	layout.add_theme_constant_override("separation", 18)
	body.add_child(layout)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 232
	sidebar.add_theme_constant_override("separation", 7)
	var navigation_scroll := ScrollContainer.new()
	navigation_scroll.name = "FactionNavigation"
	navigation_scroll.custom_minimum_size.x = 246
	navigation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(navigation_scroll)
	navigation_scroll.add_child(sidebar)
	_section(sidebar, "flag", "Державы", str(alive.size()))
	for faction in order:
		_faction_pick(sidebar, faction, power[faction], strongest, faction in alive)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 14)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.name = "FactionDetails"
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(detail_scroll)
	detail_scroll.add_child(detail)
	var f := _faction
	var color := Color(_fcat.get_faction(f).c1)
	var header := _journal_panel(detail, color)
	header.name = "FactionIdentity"
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 14)
	header.add_child(identity)
	identity.add_child(_texture(OriginalArt.crest(f), 76))
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(names)
	_journal_text(names, _fcat.get_faction(f).name, 29)
	var ruler: Dictionary = state.clans.ruler_of(f)
	_icon_line(names, "helm", "Правитель: %s" % ruler.name if not ruler.is_empty() else "Междуцарствие — выбирают правителя", GameSkin.PARCH)
	if not ruler.is_empty():
		_journal_text(names, "Характер: " + state.clans.ruler_trait(f)[0], 14, true)
	var relation := VBoxContainer.new()
	relation.custom_minimum_size.x = 208
	identity.add_child(relation)
	var rel := float(p.rel.get(f, 0))
	_journal_text(relation, "Отношение к тебе", 13, true)
	_journal_text(relation, "%s · %s%d" % [_rel_name(rel), "+" if rel > 0 else "", roundi(rel)], 17)
	_meter(relation, "FactionRelation", rel + 100, 200, _relation_color(rel), "Отношения: от −100 (враг) до +100 (друг)")
	_journal_text(relation, "−100       нейтрально       +100", 12, true)
	if p.liege == f:
		_badge(relation, "Твой сюзерен", GameSkin.BRASS)
	if not f in alive:
		_empty_state(detail, "flag", "Государство пало", "Земель не осталось. Его история сохранена в хронике.")
		return
	var nobles: Array = state.roster.parties.filter(func(q): return q.fac == f and Rules.is_noble(q))
	var lords := nobles.filter(func(q): return q.kind == "lord").size()
	var men := 0
	for noble in nobles:
		men += Economy.troop_count(noble.troops)
	var holdings: Dictionary = state.wars.hold_of(f)
	var metrics := HBoxContainer.new()
	metrics.add_theme_constant_override("separation", 8)
	detail.add_child(metrics)
	_stat_tile(metrics, "charge", "Сила державы", "%d-е из %d" % [order.find(f) + 1, alive.size()], "%s · %d%% от лидера" % [_number(roundi(power[f])), roundi(power[f] / strongest * 100)], "Сила государства по текущей оценке кампании", power[f] / strongest)
	_stat_tile(metrics, "helm", "Знать", str(lords), "%d вассалов · %d родов" % [nobles.size() - lords, state.clans.of_faction(f).size()])
	_stat_tile(metrics, "men", "Бойцов в поле", _number(men), "в отрядах знати")
	_stat_tile(metrics, "flag", "Владения", str(holdings.all), "%d гор. · %d зам. · %d дер." % [holdings.t, holdings.c, holdings.v])
	var diplomacy := HBoxContainer.new()
	diplomacy.add_theme_constant_override("separation", 14)
	detail.add_child(diplomacy)
	var conflicts := VBoxContainer.new()
	conflicts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conflicts.add_theme_constant_override("separation", 7)
	diplomacy.add_child(conflicts)
	var enemies: Array = alive.filter(func(o): return o != f and state.wars.at_war(f, o))
	_section(conflicts, "sword", "Войны", str(enemies.size()))
	for enemy in enemies:
		_war_card(conflicts, f, enemy, power)
	if enemies.is_empty():
		_icon_line(conflicts, "shield", "Государство ни с кем не воюет", Color("#a9c583"))
	_section(conflicts, "shield", "Мир", "")
	var peace := HFlowContainer.new()
	peace.add_theme_constant_override("h_separation", 6)
	peace.add_theme_constant_override("v_separation", 6)
	conflicts.add_child(peace)
	for other in alive:
		if other == f or other in enemies:
			continue
		var chip := Button.new()
		chip.text = _fcat.get_faction(other).name
		chip.icon = OriginalArt.crest(other)
		chip.expand_icon = false
		chip.add_theme_constant_override("icon_max_width", 21)
		chip.add_theme_font_size_override("font_size", 13)
		chip.tooltip_text = "Открыть сведения о государстве"
		chip.pressed.connect(func(): _faction = other; render())
		peace.add_child(chip)
	var map_col := VBoxContainer.new()
	map_col.custom_minimum_size.x = 252
	map_col.add_theme_constant_override("separation", 6)
	diplomacy.add_child(map_col)
	_section(map_col, "flag", "Дипломатия", "")
	_diplomacy_matrix(map_col, alive)
	_section(detail, "helm", "Знатные роды", str(state.clans.of_faction(f).size()))
	var families := GridContainer.new()
	families.name = "FactionFamilies"
	families.columns = 2
	families.add_theme_constant_override("h_separation", 10)
	families.add_theme_constant_override("v_separation", 10)
	detail.add_child(families)
	for family in state.clans.of_faction(f):
		_family_card(families, family)

func _faction_pick(parent: Control, faction: String, power: float, strongest: float, alive: bool) -> void:
	var selected := faction == _faction
	var button := Button.new()
	button.name = "FactionPick_" + faction
	button.custom_minimum_size = Vector2(232, 96)
	button.toggle_mode = true
	button.button_pressed = selected
	button.tooltip_text = _fcat.get_faction(faction).name + " · " + ("сила " + _number(roundi(power)) if alive else "государство пало")
	var tint := Color(_fcat.get_faction(faction).c1)
	for key in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := _card_style(GameSkin.BRASS if selected else tint, 10)
		style.bg_color = Color("#43331c") if selected else Color("#21190fe8")
		if key in ["hover", "hover_pressed"]: style.bg_color = style.bg_color.lightened(0.12)
		button.add_theme_stylebox_override(key, style)
	parent.add_child(button)
	var inset := MarginContainer.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.add_theme_constant_override("margin_left", 10)
	inset.add_theme_constant_override("margin_right", 10)
	inset.add_theme_constant_override("margin_top", 9)
	inset.add_theme_constant_override("margin_bottom", 9)
	button.add_child(inset)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 9)
	inset.add_child(line)
	line.add_child(_texture(OriginalArt.crest(faction), 34))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(col)
	_journal_text(col, _fcat.get_faction(faction).name, 16)
	_journal_text(col, ("Выбрано · " if selected else "") + ("сила " + _number(roundi(power)) if alive else "Государство пало"), 12, true)
	_meter(col, "FactionPower", power, strongest, GameSkin.BRASS, "Доля силы от ведущего государства")
	_ignore_mouse(inset)
	button.pressed.connect(func(): _faction = faction; _scroll.scroll_vertical = 0; render())

func _war_card(parent: Control, faction: String, enemy: String, power: Dictionary) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var panel := _journal_panel(parent, Color("#b95a43"))
	panel.add_theme_stylebox_override("panel", _card_style(Color("#b95a43"), 8))
	panel.add_child(col)
	var row_line := HBoxContainer.new()
	col.add_child(row_line)
	row_line.add_child(_texture(OriginalArt.crest(enemy), 26))
	_journal_text(row_line, _fcat.get_faction(enemy).name, 17)
	var war: Variant = state.wars.wars.get(Rules.war_key(faction, enemy))
	var since := "Давняя вражда" if war == null else "С %d-го дня · длится %d дн." % [int(war.since), maxi(0, int(state.clock.day) - int(war.since))]
	var share: float = power[faction] / maxf(1, power[faction] + power[enemy])
	var balance := _meter(col, "WarBalance", share, 1, Color(_fcat.get_faction(faction).c1).lightened(0.25), "Слева — выбранное государство; справа — противник. Оценка силы, а не прогноз исхода боя.")
	var background := StyleBoxFlat.new()
	background.bg_color = Color(_fcat.get_faction(enemy).c1).lightened(0.15)
	balance.add_theme_stylebox_override("background", background)
	_journal_text(col, "%s · силы %d : %d" % [since, roundi(share * 100), roundi((1 - share) * 100)], 13, true)
	var sieges: Array = []
	for settlement in state.map.settles:
		if settlement.get("siege") is Dictionary and ((settlement.siege.f == faction and settlement.fac == enemy) or (settlement.siege.f == enemy and settlement.fac == faction)):
			sieges.append(settlement.name)
	if not sieges.is_empty(): _icon_line(col, "flag", "Осады: " + ", ".join(sieges), Color("#efaa78"))

func _diplomacy_matrix(parent: Control, alive: Array) -> void:
	var grid := GridContainer.new()
	grid.name = "DiplomacyMatrix"
	grid.columns = alive.size() + 1
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	parent.add_child(grid)
	grid.add_child(Control.new())
	for faction in alive: grid.add_child(_faction_crest(faction))
	for faction in alive:
		grid.add_child(_faction_crest(faction))
		for other in alive:
			var self_cell: bool = faction == other
			var hostile: bool = not self_cell and state.wars.at_war(faction, other)
			var label := Label.new()
			label.text = "—" if self_cell else ("×" if hostile else "·")
			label.custom_minimum_size = Vector2(26, 26)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			var style := _card_style(GameSkin.BRASS if faction == _faction or other == _faction else Color("#5f513a"), 0)
			style.border_width_left = 1
			style.bg_color = Color("#302a20") if self_cell else (Color("#873d30") if hostile else Color("#3c5731"))
			label.add_theme_stylebox_override("normal", style)
			label.add_theme_color_override("font_color", Color("#fff0d0"))
			label.mouse_filter = Control.MOUSE_FILTER_STOP
			label.tooltip_text = "%s / %s: %s" % [_fcat.get_faction(faction).name, _fcat.get_faction(other).name, "одно государство" if self_cell else ("война" if hostile else "мир")]
			grid.add_child(label)
	_journal_text(parent, "× война     · мир     — своё", 13, true)

func _family_card(parent: Control, family: Dictionary) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	_journal_panel(parent, GameSkin.BRASS if family.rule else Color("#756141")).add_child(col)
	_journal_text(col, family.name, 20)
	var family_trait: Dictionary = state.clans.TRAITS[family.trait]
	var badges := HFlowContainer.new()
	col.add_child(badges)
	_badge(badges, family_trait.n, GameSkin.MUTED, family_trait.d)
	if family.rule: _badge(badges, "Правящий род", GameSkin.BRASS)
	var loyalty := int(family.loy)
	_icon_line(col, "shield", "Верность %d / 100 · %s" % [loyalty, "крепкая" if loyalty > 75 else ("обычная" if loyalty > 50 else "шаткая")], GameSkin.MUTED)
	_meter(col, "FamilyLoyalty", loyalty, 100, Color("#8fad60") if loyalty > 65 else (GameSkin.BRASS if loyalty > 40 else Color("#d57860")), "Верность рода своему государству")
	var home: Dictionary = state.map.settlement_by_id(int(family.home)) if family.get("home") != null else {}
	_icon_line(col, "flag", "%s · %s бойцов" % [home.get("name", "Без родовых земель"), _number(state.clans.force(family))], GameSkin.MUTED)
	col.add_child(HSeparator.new())
	for member in state.clans.members(family):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		col.add_child(line)
		if not member.troops.is_empty(): line.add_child(OriginalArt.portrait_control(member.troops[0].type, member.fac, 42))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(info)
		_journal_text(info, member.name, 16)
		var destination: Dictionary = state.map.settlement_by_id(int(member.sid)) if member.get("sid") != null else {}
		var location := "В походе" if member.get("army", false) else "В поле"
		if member.get("fight", false): location = "В бою"
		elif not destination.is_empty(): location += " · к " + String(destination.name)
		_icon_line(info, "men", "%d бойцов · %s" % [Economy.troop_count(member.troops), location], GameSkin.MUTED, 12)

func _journal_panel(parent: Control, accent := Color("#786039")) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _card_style(accent))
	parent.add_child(panel)
	return panel

func _journal_text(parent: Control, text: String, font_size: int, muted := false) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if muted:
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", GameSkin.MUTED)
	else:
		GameSkin.title(label, font_size)
	parent.add_child(label)

func _faction_crest(faction: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = OriginalArt.crest(faction)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = _fcat.get_faction(faction).name
	return icon

static func _rel_name(v: float) -> String:
	if v < -20.0:
		return "Враждебные"
	if v < -5.0:
		return "Недружелюбные"
	if v < 20.0:
		return "Нейтральные"
	if v < 50.0:
		return "Дружелюбные"
	return "Союзные"

func _card_style(accent: Color, padding := 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#20170fef")
	style.border_color = accent.darkened(0.12)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(3)
	style.set_content_margin_all(padding)
	return style

func _texture(texture: Texture2D, extent: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(extent, extent)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _section(parent: Control, icon: String, title: String, detail := "") -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	line.add_child(_texture(GameSkin.icon(icon), 21))
	_journal_text(line, title, 21)
	line.get_child(1).size_flags_stretch_ratio = 4
	if detail != "":
		_journal_text(line, detail, 13, true)
		line.get_child(2).autowrap_mode = TextServer.AUTOWRAP_OFF
		line.get_child(2).size_flags_horizontal = Control.SIZE_SHRINK_END
		line.get_child(2).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _icon_line(parent: Control, icon: String, text: String, color := GameSkin.MUTED, font_size := 14) -> void:
	var line := HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", 6)
	parent.add_child(line)
	line.add_child(_texture(GameSkin.icon(icon), 16))
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	line.add_child(label)

func _meter(parent: Control, id: String, value: float, maximum: float, color := GameSkin.BRASS, hint := "") -> ProgressBar:
	var meter := ProgressBar.new()
	meter.name = id
	meter.max_value = maxf(1, maximum)
	meter.step = 0.01
	meter.value = value
	meter.show_percentage = false
	meter.custom_minimum_size.y = 7
	meter.tooltip_text = hint
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	meter.add_theme_stylebox_override("fill", fill)
	parent.add_child(meter)
	return meter

func _stat_tile(parent: Control, icon: String, caption: String, value: String, detail: String, hint := "", fill := -1.0) -> void:
	var panel := _journal_panel(parent)
	panel.tooltip_text = hint
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)
	_icon_line(col, icon, caption, GameSkin.MUTED, 13)
	_journal_text(col, value, 25)
	_journal_text(col, detail, 13, true)
	if fill >= 0: _meter(col, "StatFill", fill, 1)

func _badge(parent: Control, text: String, color: Color, hint := "") -> void:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", color)
	var style := _card_style(color.darkened(0.4), 4)
	style.border_width_left = 1
	badge.add_theme_stylebox_override("normal", style)
	badge.tooltip_text = hint
	badge.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(badge)

func _empty_state(parent: Control, icon: String, title: String, detail: String) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	_journal_panel(parent).add_child(line)
	line.add_child(_texture(GameSkin.icon(icon), 44))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(col)
	_journal_text(col, title, 22)
	_journal_text(col, detail, 16, true)

func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in control.get_children():
		if child is Control: _ignore_mouse(child)

func _relation_color(value: float) -> Color:
	return Color("#d57860") if value < -5 else (Color("#9dbb75") if value >= 20 else GameSkin.BRASS)

func _number(value: int) -> String:
	var text := str(value)
	var result := ""
	for i in text.length():
		if i > 0 and (text.length() - i) % 3 == 0: result += " "
		result += text[i]
	return result



func _fit() -> void:
	super()
	if is_instance_valid(body):
		var faction_layout := body.find_child("FactionLayout", true, false) as Control
		if faction_layout != null:
			faction_layout.custom_minimum_size.y = maxf(320, get_viewport().get_visible_rect().size.y - 282)
