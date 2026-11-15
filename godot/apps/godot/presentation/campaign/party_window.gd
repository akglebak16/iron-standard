extends "res://apps/godot/presentation/campaign/modal_window.gd"
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## Party, hero and journal windows (openPanel in src/06_ui.js).
const Economy = preload("res://core/campaign/economy/party_economy.gd")
const CompanionText = preload("res://apps/godot/presentation/campaign/companion_text.gd")
const TABS := [["troops", "Отряд"], ["hero", "Герой"], ["gear", "Обоз"], ["quests", "Задания"], ["factions", "Фракции"], ["comps", "Спутники"], ["journal", "Журнал"]]
const HeroGear = preload("res://core/equipment/rules/hero_gear.gd")
const HeroEquip = preload("res://core/equipment/rules/hero_equip.gd")
const GearComparison = preload("res://apps/godot/presentation/campaign/gear_comparison.gd")
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
	set_width(1040 if current_tab in ["hero", "gear", "factions"] else WIDTH)
	var p = state.player
	var fx: Dictionary = state.player_effects()
	title_label.text = p.hero.name
	sub_label.text = "Уровень %d · золото %d · порций %d" % [p.hero.lvl, p.gold, Economy.provisions(p)]
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

func _troops(p, fx: Dictionary) -> void:
	note("В отряде %d из %d бойцов. Жалованье в день: %d." % [Economy.troop_count(p.troops), Economy.size_cap(p.hero, fx),
		Economy.wage_day(p.troops, func(t): return float(state.roster.catalog.get_troop(t).wage), fx)])
	var list: Array = p.troops.duplicate()
	list.sort_custom(func(a, b): return state.roster.info[a.type].tier > state.roster.info[b.type].tier)
	for s in list:
		var troop: Dictionary = state.roster.catalog.get_troop(s.type)
		var buttons: Array = []
		for up_id in troop.up:
			var up: Dictionary = state.roster.catalog.get_troop(up_id)
			var cost := Economy.upgrade_cost(troop, fx)
			buttons.append({"text": "→ %s (%d)" % [up.name, cost], "disabled": p.gold < cost, "call": func(): Economy.upgrade(p, troop, up_id, fx)})
		if Economy.troop_count(p.troops) > 1:
			buttons.append({"text": "Распустить", "call": func(): Economy.remove_troops(p.troops, s.type, 1)})
		row("%s ×%d" % [troop.name, s.n], "ур. %d · жалованье %d" % [troop.tier, troop.wage], buttons, s.type)

func _hero(p) -> void:
	var h: Dictionary = p.hero
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	body.add_child(top)
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
	var values := Label.new()
	values.text = "Опыт %d / %d · Броня %s\nБойцов %d / %d" % [h.xp, int(xp.max_value), str(resolved.armor), Economy.troop_count(p.troops), Economy.size_cap(h, state.player_effects())]
	stats.add_child(values)
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
		attr_col.add_child(title)
		var detail := Label.new()
		detail.text = Economy.ATTRS[key][1]
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size.x = 140
		detail.add_theme_font_size_override("font_size", 13)
		attr_col.add_child(detail)
		var plus := Button.new()
		plus.text = "+"
		plus.disabled = int(h.pts) < 1
		plus.pressed.connect(func(): Economy.spend_attribute(h, key); render())
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
	box.bg_color = Color("#33260f") if rank == 3 else Color("#2c1f14")
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
			0: label.text = "◆".repeat(rank) + "◇".repeat(3 - rank) + "   " + " · ".join(perk.req.map(func(v): return str(v)))
			1: label.text = perk.n
			2:
				label.text = OriginalArt.MANIFEST.perks.get(perk.id, "")
				label.size_flags_vertical = Control.SIZE_EXPAND_FILL
			3: label.text = "Максимум" if rank >= 3 else ("Изучить · 1 очко" if why.is_empty() else why)
		label.add_theme_font_size_override("font_size", 12 if i != 1 else 17)
		label.add_theme_color_override("font_color", GameSkin.BRASS if i in [0, 1] and rank > 0 else GameSkin.PARCH)
		if i == 1: label.add_theme_font_override("font", GameSkin.DISPLAY)
		col.add_child(label)
	button.pressed.connect(func(): Economy.buy_perk(h, perk); render())
	return button

const CHRONICLE_LIMIT := 30
const CHRONICLE_COLORS := [Color("#d8c9a5"), Color("#e0705a"), Color("#7fb2e0"), Color("#8fc24f")]

## Chronicle (jqChronicle in src/06f_jquests.js): last 30 entries, newest first, grouped by day.
func _journal() -> void:
	if state.journal.is_empty():
		note("Записей пока нет.")
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
			body.add_child(box)
		var line := Label.new()
		line.name = "ChronicleEvent"
		line.text = "• " + String(e.text)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_color_override("font_color", CHRONICLE_COLORS[clampi(int(e.get("kind", 0)), 0, 3)])
		box.add_child(line)

func _comps(p) -> void:
	var comps = state.companions
	note("Спутники бьются сами в своей группе и слушаются приказов. В бою их не убивают, а ранят: раненый ниже 25%% здоровья пропускает бои, пока не подлечится. Жалованье спутников: %d в день." % comps.wage(p))
	if p.comps.is_empty():
		note("Спутников нет. Ищи их в тавернах городов.")
	for c in p.comps.duplicate():
		var d: Dictionary = state.companion_catalog.get_companion(c.id)
		var ok: bool = comps.fit(c)
		var btn: Dictionary
		if _confirm == c.id:
			btn = {"text": "Точно отпустить?", "call": func(): comps.fire(p, c.id); _confirm = ""}
		else:
			btn = {"text": "Отпустить", "call": func(): _confirm = c.id}
		var grant := {"text": "Выбери надел ↓" if _pick == c.id else "Дать надел", "call": func(): _pick = "" if _pick == c.id else c.id}
		row("%s · %s · ур. %d%s" % [c.name, d.role, c.lvl, "" if ok else " · ранен"], "здоровье %d%% · опыт %d\n%s: %s" % [roundi(float(c.hp) * 100.0), int(c.get("xp", 0)), d.skn, CompanionText.skill_text(d, c)], [grant, btn])
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
				[{"text": "Отдать", "call": func(): sub_label.text = vs.grant(c.id, s.id); _pick = ""}])

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
			buttons.append({"text": vs.MODES[m][0], "disabled": v.get("mode", "guard") == m, "call": func(): vs.set_mode(v.cid, m)})
		buttons.append({"text": "+200", "disabled": p.gold < 200, "call": func(): vs.give(v.cid, 200)})
		if _confirm == "v" + v.cid:
			buttons.append({"text": "Точно забрать?", "call": func(): vs.revoke(v.cid); _confirm = ""})
		else:
			buttons.append({"text": "Забрать надел", "call": func(): _confirm = "v" + v.cid})
		row("%s · вассал · ур. %d" % [v.c.name, v.c.lvl], detail, buttons)

func _quests(p) -> void:
	if p.quests.is_empty():
		note("Заданий нет. Их дают на досках в городах.")
	for q in p.quests:
		var left: int = int(q.dl) - int(state.clock.day)
		var target: Dictionary = state.map.settlement_by_id(q.from if q.type == "scout" and q.get("seen", false) else q.sid)
		var buttons: Array = []
		if not target.is_empty() and q.type != "purge":
			buttons.append({"text": "На карте", "call": func(): quest_target.emit(target.x, target.y); close_window()})
		row(state.quests.text(q), "%s · награда %d" % ["срок вышел" if left < 0 else ("последний день" if left == 0 else "осталось дней: %d" % left), q.reward], buttons)

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
	equipment.custom_minimum_size.x = 368
	inventory.add_child(equipment)
	var backpack := VBoxContainer.new()
	backpack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory.add_child(backpack)
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
			{"text": "Ближнее", "disabled": h.get("sel") != "ranged", "call": func(): HeroEquip.wield(h, "melee")},
			{"text": "Стрелковое", "disabled": h.get("sel") == "ranged", "call": func(): HeroEquip.wield(h, "ranged")}])
	var stats := GridContainer.new()
	stats.columns = 3
	equipment.add_child(stats)
	for stat in [["Броня", str(resolved.armor)], ["Урон оружия", str(resolved.weapon.get("dmg", 0))], ["Блок", "%d%%" % roundi(float(resolved.block) * 100)], ["Удар", str(resolved.weapon.get("spd", 1)) + " с"], ["Длина", str(30 + int(resolved.weapon.get("reach", 0)))], ["Урон по типу", {"cut": "Режущий", "pierce": "Колотый", "blunt": "Дробящий"}.get(resolved.weapon.get("dt", ""), "—")]]:
		var label := Label.new()
		label.text = "%s\n%s" % stat
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = 116
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
	cargo.text = "Обоз                                              %s / %d" % [str(weight), capacity]
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
			row(it.name, _stats(it), [{"text": "Снять" if _selected_gear in eq.values() else "Надеть", "call": _selected_action}])
			if not _selected_gear in eq.values():
				_comparison(GearComparison.compare(h, it, gear, state.perks, stat_preview))
		else:
			var good: Dictionary = state.market.goods.get(_selected_gear, {})
			row(good.get("n", _selected_gear), "Торговый товар · продай на рынке города")
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
	var wars = state.wars
	var clans = state.clans
	var alive: Array = wars.factions_alive()
	var power := {}
	var top := 1.0
	for f in Rules.REAL_FACTIONS:
		power[f] = wars.power(f) if f in alive else 0.0
		top = maxf(top, power[f])
	var order: Array = alive.duplicate()
	order.sort_custom(func(a, b): return power[a] > power[b])
	for f in Rules.REAL_FACTIONS:
		if not f in alive:
			order.append(f)
	if _faction == "" or not _faction in Rules.REAL_FACTIONS:
		_faction = p.liege if p.liege != "" and p.liege in alive else (order[0] if not order.is_empty() else "emp")
	var picks: Array = []
	for f in order:
		picks.append({"text": String(_fcat.get_faction(f).name).split(" ")[0], "disabled": f == _faction, "call": func(): _faction = f})
	row("Государство", "", picks)
	var f := _faction
	var look := _fcat.get_faction(f)
	heading(look.name)
	if not f in alive:
		note("Государство пало: земель не осталось.")
		return
	var ruler: Dictionary = clans.ruler_of(f)
	if not ruler.is_empty():
		note("Правитель: %s · %s" % [ruler.name, clans.ruler_trait(f)[0]])
	elif clans.kingless(f):
		note("Междуцарствие: роды выбирают нового правителя, походов нет.")
	var rank: int = order.find(f) + 1
	var nobles: Array = state.roster.parties.filter(func(q): return q.fac == f and Rules.is_noble(q))
	var lords := nobles.filter(func(q): return q.kind == "lord").size()
	var men := 0
	for q in nobles:
		men += Economy.troop_count(q.troops)
	var h: Dictionary = wars.hold_of(f)
	row("Сила: %d-е место из %d" % [rank, alive.size()], "%d · %s" % [roundi(power[f]), "сильнейшая" if rank == 1 else "%d%% от первой" % roundi(power[f] / top * 100.0)])
	row("Знать: %d лордов, %d вассалов, %d родов" % [lords, nobles.size() - lords, clans.of_faction(f).size()], "бойцов в отрядах знати: %d" % men)
	row("Владения: %d" % h.all, "%d гор. · %d зам. · %d дер." % [h.t, h.c, h.v])
	row("Отношение к тебе: %s (%d)" % [_rel_name(float(p.rel.get(f, 0))), roundi(float(p.rel.get(f, 0)))], "ты служишь им" if p.liege == f else "")
	heading("Войны")
	var any := false
	for o in alive:
		if o == f or not wars.at_war(f, o):
			continue
		any = true
		var w: Variant = wars.wars.get(Rules.war_key(f, o))
		var since := ("с %d-го дня" % int(w.since)) if w != null else "давняя вражда"
		var share := roundi(power[f] / maxf(1.0, power[f] + power[o]) * 100.0)
		var sieges: Array = []
		for q in state.map.settles:
			if q.get("siege") is Dictionary and ((q.siege.f == f and q.fac == o) or (q.siege.f == o and q.fac == f)):
				sieges.append(q.name)
		row(_fcat.get_faction(o).name, "%s · соотношение сил %d на %d%s" % [since, share, 100 - share, (" · осады: " + ", ".join(sieges)) if not sieges.is_empty() else ""])
	if not any:
		note("Ни с кем не воюет.")
	heading("Роды")
	for c in clans.of_faction(f):
		var loy := int(c.loy)
		row("%s%s" % [c.name, " · правящий" if c.rule else ""], "%s род · верность %s · лордов %d" % [clans.TRAITS[c.trait].n, "крепкая" if loy > 75 else ("обычная" if loy > 50 else ("шаткая" if loy > 30 else "на исходе")), clans.members(c).size()])

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
