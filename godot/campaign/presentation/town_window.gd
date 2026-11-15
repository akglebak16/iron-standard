extends "res://campaign/presentation/modal_window.gd"
## A settlement: recruits, market (food, hero gear) and waiting (renderTown in src/06_ui.js).
const Economy = preload("res://campaign/economy/party_economy.gd")
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
	var tabs := [["recruit", "Рекруты"], ["market", "Рынок"]]
	set_tabs(tabs, "recruit")
	open_window()

func render() -> void:
	if state == null:
		return
	var p = state.player
	var fx: Dictionary = state.player_effects()
	var mine: bool = settlement.fac == "player"
	title_label.text = settlement.name
	sub_label.text = "%s · %s   ·   золото %d" % [SettlementLayer.KIND_NAMES.get(settlement.kind, ""), _factions.get_faction(settlement.fac).get("name", ""), p.gold]
	set_tabs([["recruit", "Рекруты"], ["market", "Рынок"]], current_tab if current_tab != "" else "recruit")
	clear_body()
	if current_tab == "market":
		_market(p, fx)
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
