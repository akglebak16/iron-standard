extends "res://campaign/presentation/modal_window.gd"
## The siege of a hostile town or castle: defenders, talks and the choice between calculating and storming (openSiege,
## openTalk and the sack/spare choice in src/06_ui.js and src/06i_siege.js).
const Siege = preload("res://campaign/world/world_siege.gd")
const Rules = preload("res://campaign/world/party_rules.gd")
const AutoBattle = preload("res://campaign/world/auto_battle.gd")
const SettlementLayer = preload("res://campaign/presentation/settlement_layer.gd")
const FactionCatalog = preload("res://campaign/data/faction_catalog.gd")

signal assault(settlement: Dictionary, calculate: bool)
signal captured(settlement: Dictionary)
var state: RefCounted
var settlement: Dictionary = {}
var mode := "main"   # main | talk | loot
var message := ""
var _factions := FactionCatalog.new()

func _ready() -> void:
	super()
	assert(_factions.load_data())

func open_for(world_state: RefCounted, s: Dictionary) -> void:
	state = world_state
	settlement = s
	mode = "main"
	message = ""
	open_window()

func open_loot(world_state: RefCounted, s: Dictionary) -> void:
	state = world_state
	settlement = s
	mode = "loot"
	message = ""
	open_window()

func render() -> void:
	if state == null:
		return
	set_tabs([], "")
	clear_body()
	var s := settlement
	title_label.text = ("Осада: " if mode != "loot" else "Взят: ") + s.name
	var siege_party: Dictionary = state.siege.siege_party(s)
	sub_label.text = "%s · %s · %d защитников" % [SettlementLayer.KIND_NAMES.get(s.kind, ""), _factions.get_faction(s.fac).get("name", ""), Rules.troop_count(siege_party.troops)]
	if message != "":
		note(message)
	match mode:
		"talk":
			_talk()
		"loot":
			_loot()
		_:
			_main(siege_party)

func _main(siege_party: Dictionary) -> void:
	note("Ворота закрыты. %s" % Siege.note(settlement))
	if siege_party.lord != null:
		note("В стенах стоит %s со своим отрядом." % siege_party.lord)
	var calc: Array = state.siege.defenders_for_calc(settlement)
	var power: Array = AutoBattle.relative_power(state.player.troops, calc, state.roster.info)
	row("Расчёт сил: %s" % power[0], "")
	var list: Array = siege_party.troops.duplicate()
	for t in list:
		row("%s" % state.roster.catalog.get_troop(t.type).name, "ур. %d" % state.roster.info[t.type].tier + "   ×%d" % int(t.n))
	heading("Что делаем")
	row("Отойти от стен", "", [{"text": "Отойти", "call": func(): close_window()}])
	if settlement.fac in Rules.REAL_FACTIONS:
		var food: float = state.siege.food_of(settlement)
		var food_text := "кончилась" if food <= 0.0 else ("на исходе (около %d дн.)" % ceili(food) if food < 3.0 else "около %d дн." % ceili(food))
		row("Переговоры и выкуп", "Запасы еды в городе: %s." % food_text, [{"text": "Говорить", "call": func(): mode = "talk"; message = ""}])
		if not settlement.has("blk"):
			row("Блокада", "Стой у стен, пока в городе не кончится еда: голодный гарнизон сдаётся.", [{"text": "Блокада", "call": func(): state.log_world(state.siege.block_start(state.player, settlement)); close_window()}])
		else:
			note("Город в блокаде.")
	row("Рассчитать штурм", "Без боя на поле: исход решают силы и случай.", [{"text": "Рассчитать", "call": func(): assault.emit(settlement, true); close_window()}])
	row("Штурм", "Ты ведёшь людей в бой у стен.", [{"text": "На штурм!", "call": func(): assault.emit(settlement, false); close_window()}])

func _talk() -> void:
	var p = state.player
	var s := settlement
	var wait := maxi(0, int(s.get("talkT", 0)) - state.siege.now_h())
	var price: int = state.siege.bribe(s)
	note("Чем больше твоё войско, чем выше Обаяние героя, чем голоднее и разрушеннее город, тем охотнее он сдаётся. Неудача закрывает переговоры на сутки и портит отношения.")
	row("Потребовать сдачи", "шансы %s" % _chance_word(state.siege.talk_chance(p, s, false)), [{"text": "Потребовать", "disabled": wait > 0, "call": func(): _go(false)}])
	row("Выкуп за %d золота" % price, "шансы %s" % _chance_word(state.siege.talk_chance(p, s, true)), [{"text": "Предложить", "disabled": wait > 0 or p.gold < price, "call": func(): _go(true)}])
	if wait > 0:
		note("Гонцов не пускают ещё %d ч." % wait)
	row("Назад", "", [{"text": "Назад", "call": func(): mode = "main"; message = ""}])

func _go(gold: bool) -> void:
	var r: Variant = state.siege.talk(state.player, settlement, gold)
	if r == null:
		return
	if r:
		state.settlement_changed.emit(settlement)
		state.log_world("%s сдался без боя. Город твой, жители целы." % settlement.name)
		captured.emit(settlement)
		close_window()
	else:
		message = "Гонцов прогнали: «Мы не сдадимся». Отношение к ним ухудшилось."

func _loot() -> void:
	note("Город пал. Решай, что будет с ним и с жителями.")
	row("Разграбить", "Золото сейчас, но жители возненавидят тебя, а доход упадёт.", [{"text": "Грабить", "call": func(): _finish(state.siege.sack(state.player, settlement))}])
	row("Пощадить", "Жители поднесут дары, отношение к их фракции улучшится.", [{"text": "Пощадить", "call": func(): _finish(state.siege.spare(state.player, settlement))}])

func _finish(text: String) -> void:
	state.log_world(text)
	state.settlement_changed.emit(settlement)
	close_window()

static func _chance_word(p: float) -> String:
	if p < 0.2:
		return "почти никаких"
	if p < 0.4:
		return "слабые"
	if p < 0.6:
		return "неплохие"
	if p < 0.8:
		return "хорошие"
	return "отличные"
