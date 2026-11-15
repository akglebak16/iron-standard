extends "res://campaign/presentation/modal_window.gd"
## Party, hero and journal windows (openPanel in src/06_ui.js).
const Economy = preload("res://campaign/economy/party_economy.gd")
const CompanionText = preload("res://campaign/presentation/companion_text.gd")
const TABS := [["troops", "Отряд"], ["comps", "Спутники"], ["hero", "Герой"], ["quests", "Задания"], ["journal", "Журнал"]]
var _confirm := ""
var _pick := ""
var state: RefCounted

func open_for(world_state: RefCounted, tab: String = "troops") -> void:
	state = world_state
	set_tabs(TABS, tab)
	open_window()

func render() -> void:
	if state == null:
		return
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
		row("%s ×%d" % [troop.name, s.n], "ур. %d · жалованье %d" % [troop.tier, troop.wage], buttons)

func _hero(p) -> void:
	var h: Dictionary = p.hero
	note("Опыт: %d / %d" % [h.xp, 100 + int(h.lvl) * 80])
	heading("Характеристики (очков: %d)" % h.pts)
	for key in Economy.ATTRS:
		row("%s: %d" % [Economy.ATTRS[key][0], h.get(key, 1)], Economy.ATTRS[key][1], [{"text": "+1", "disabled": int(h.pts) < 1, "call": func(): Economy.spend_attribute(h, key)}])
	heading("Перки (очков: %d)" % h.pp)
	for perk in state.perks.list():
		var rank := Economy.perk_rank(h, perk.id)
		var why := Economy.perk_why(h, perk)
		row("%s  %s" % [perk.n, "●".repeat(rank) + "○".repeat(3 - rank)], why if not why.is_empty() else "можно улучшить", [{"text": "Взять", "disabled": not why.is_empty(), "call": func(): Economy.buy_perk(h, perk)}])

func _journal() -> void:
	if state.journal.is_empty():
		note("Пока ничего не случилось.")
	for e in state.journal:
		row("День %d" % e.day, e.text)

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
		row(state.quests.text(q), "%s · награда %d" % ["срок вышел" if left < 0 else ("последний день" if left == 0 else "осталось дней: %d" % left), q.reward])
