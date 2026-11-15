extends "res://campaign/presentation/modal_window.gd"
## Party, hero and journal windows (openPanel in src/06_ui.js).
const Economy = preload("res://campaign/economy/party_economy.gd")
var state: RefCounted

func open_for(world_state: RefCounted, tab: String = "troops") -> void:
	state = world_state
	set_tabs([["troops", "Отряд"], ["hero", "Герой"], ["journal", "Журнал"]], tab)
	open_window()

func render() -> void:
	if state == null:
		return
	var p = state.player
	var fx: Dictionary = state.player_effects()
	title_label.text = p.hero.name
	sub_label.text = "Уровень %d · золото %d · порций %d" % [p.hero.lvl, p.gold, Economy.provisions(p)]
	set_tabs([["troops", "Отряд"], ["hero", "Герой"], ["journal", "Журнал"]], current_tab if current_tab != "" else "troops")
	clear_body()
	match current_tab:
		"hero":
			_hero(p)
		"journal":
			_journal()
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
