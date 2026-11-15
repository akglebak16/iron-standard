extends RefCounted
## A running world: map, clock and the player's party. Settlement rules, parties and AI plug into step()/hour_tick() in later slices.
const WorldMap = preload("res://campaign/world/world_map.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const WorldClock = preload("res://campaign/world/world_clock.gd")
const PlayerParty = preload("res://campaign/world/player_party.gd")
const PartyRoster = preload("res://campaign/world/party_roster.gd")
const PartyAI = preload("res://campaign/world/party_ai.gd")
const Rules = preload("res://campaign/world/party_rules.gd")
const PartyEconomy = preload("res://campaign/economy/party_economy.gd")
const WorldWars = preload("res://campaign/world/world_wars.gd")
const WorldSiege = preload("res://campaign/world/world_siege.gd")
const WorldQuests = preload("res://campaign/world/world_quests.gd")
const WorldUndead = preload("res://campaign/world/world_undead.gd")
const WorldClans = preload("res://campaign/world/world_clans.gd")
const WorldVassals = preload("res://campaign/world/world_vassals.gd")
const WorldCompanions = preload("res://campaign/world/world_companions.gd")
const CompanionCatalog = preload("res://characters/data/companion_catalog.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const CompanionProfile = preload("res://characters/rules/companion_profile.gd")
const Market = preload("res://campaign/economy/market.gd")
const GoodsCatalog = preload("res://campaign/data/goods_catalog.gd")
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")
const PerkEffects = preload("res://characters/rules/perk_effects.gd")

## Starting troops by culture (CULT in src/05_world.js).
const START_TROOPS := {
	"nord": [["n1", 6], ["n2a", 2], ["n2s", 2]], "emp": [["e1", 6], ["e2a", 3], ["e2s", 1]],
	"khan": [["k1", 5], ["k2a", 3], ["k2c", 2]], "kin": [["f1", 6], ["f2a", 3], ["f2s", 1]],
	"dom": [["d1", 6], ["d2x", 3], ["d2s", 1]], "pact": [["p1", 6], ["p2a", 3], ["p2s", 1]],
	"emi": [["m1", 5], ["m2a", 3], ["m2c", 2]],
}

signal party_met(party: Dictionary, forced: bool)
signal log_added(text: String)
signal settlement_changed(settlement: Dictionary)
signal settlement_entered(settlement: Dictionary)
signal siege_requested(settlement: Dictionary)

var map: RefCounted
var clock := WorldClock.new()
var player := PlayerParty.new()
var culture := "emp"
var seed_value := 0
var home_id := 0
var hours_passed := 0
var roster: PartyRoster
var perks := PerkCatalog.new()
var market: Market
var wars: WorldWars
var siege: WorldSiege
var quests: WorldQuests
var undead: WorldUndead
var clans: WorldClans
var vassals: WorldVassals
var companions: WorldCompanions
var companion_catalog := CompanionCatalog.new()
var gear: GearCatalog
var journal: Array = []  # [{day, text}]
var ai: PartyAI

static func create(seed_value: int, data: EuropeData, player_culture := "emp") -> RefCounted:
	var state := new()
	state.culture = player_culture
	state.seed_value = seed_value
	state.map = WorldMap.create(seed_value, data)
	state._place_player(seed_value)
	state.player.culture = player_culture
	state.player.hero = {"name": "Безымянный", "lvl": 1, "xp": 0, "pts": 2, "pp": 1, "perks": [], "str": 1, "vit": 1, "agi": 1,
		"int": 1, "cha": 1, "armor": 0, "weapon": 0, "shield": 0, "horse": 1 if player_culture in ["khan", "emi"] else 0, "hp": 1.0, "seed": seed_value % 99999 + 1}
	for t in START_TROOPS[player_culture]:
		state.player.troops.append({"type": t[0], "n": t[1]})
	assert(state.perks.load_data())
	var goods := GoodsCatalog.new()
	assert(goods.load_data())
	state.market = Market.new(goods, RandomNumberGenerator.new())
	state.market.rng.seed = seed_value + 191
	var gear_catalog := GearCatalog.new()
	assert(gear_catalog.load_data())
	state.gear = gear_catalog
	state.market.gear = gear_catalog.definitions()
	state.roster = PartyRoster.new(state.map, seed_value)
	state.roster.populate()
	state.wars = WorldWars.new(state.map, state.roster)
	state.wars.start()
	state.siege = WorldSiege.new(state.wars, state.roster, state.roster.rng)
	state.wars.announced.connect(state.log_world)
	state.wars.settlement_changed.connect(func(s): state.settlement_changed.emit(s))
	state.ai = PartyAI.new(state.roster, state.player)
	state.undead = WorldUndead.new(state.roster, state.wars)
	state.undead.init()
	state.undead.announced.connect(state.log_world)
	state.undead.settlement_changed.connect(func(s): state.settlement_changed.emit(s))
	state.ai.undead = state.undead
	state.clans = WorldClans.new(state.roster, state.wars, state.player)
	state.clans.siege = state.siege
	state.clans.init()
	state.clans.ruler_day()
	state.clans.announced.connect(state.log_world)
	state.clans.message.connect(state.log_world)
	state.wars.clans = state.clans
	state.ai.clans = state.clans
	state.roster.clans_on = true
	assert(state.companion_catalog.load_data())
	state.quests = WorldQuests.new(state.map, state.market.goods, state.roster.catalog, state.wars, state.roster.rng)
	state.quests.message.connect(state.log_world)
	state.quests.gen_boards(state.clock.day)
	state.companions = WorldCompanions.new(state.map, state.companion_catalog, state.roster.rng)
	state.companions.message.connect(state.log_world)
	state.companions.ensure(state.player)
	state.vassals = WorldVassals.new(state.roster, state.siege, state.companions, state.player)
	state.vassals.message.connect(state.log_world)
	state.siege.vassals = state.vassals
	state.ai.vassals = state.vassals
	state.siege.lost.connect(func(s, t): state.log_world(t); state.settlement_changed.emit(s))
	state.siege.held.connect(func(_s, t): state.log_world(t))
	Rules.player_rel = state.player.rel
	return state

func _place_player(seed_value: int) -> void:
	var home: Dictionary = {}
	for s in map.settles:
		if s.fac == culture and s.kind == "town":
			home = s
			break
	assert(not home.is_empty(), "no home town for " + culture)
	home_id = home.id
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var px: float = home.x + 10.0 + rng.randf_range(-24.0, 24.0)
	var py: float = home.y + 34.0
	if not map.paths.passable_type(map.paths.terr_at(px, py)):
		px = home.x
		py = home.y
	player.x = px
	player.y = py

func advance(real_dt: float) -> int:
	return clock.advance(real_dt, step, hour_tick)

func step(dh: float) -> void:
	Rules.player_rel = player.rel
	if player.tid >= 0 and player.busy == "":
		var tg: Dictionary = roster.party_by_id(player.tid)
		if tg.is_empty() or tg.hide:
			player.tid = -1
			player.stop()
		elif Vector2(tg.x - player.x, tg.y - player.y).length() < 24.0:
			player.tid = -1
			player.stop()
			player.busy = "enc"
			party_met.emit(tg, false)
			return
		else:
			player.rp -= dh
			if player.rp <= 0.0:
				player.rp = 0.6
				player.path_to(map.paths, tg.x, tg.y)
	if player.has_route():
		var finished := player.move_along(map.paths, dh)
		if finished:
			player.stop()
			if player.enter_id >= 0:
				enter(map.settlement_by_id(player.enter_id))
	_meetings()
	ai.step(dh)

## A hostile party that reaches the player forces a meeting (stepWorld).
## Enters a settlement (townEnter): the party stops, relations with its owner warm up a little.
func enter(s: Dictionary) -> void:
	player.enter_id = -1
	if s.is_empty() or s.kind == "camp" or Vector2(s.x - player.x, s.y - player.y).length() > 60.0:
		return
	player.stop()
	if WorldSiege.hostile(s, player.rel):
		if s.kind == "village":
			log_world("%s: жители заперлись, эта фракция враждебна тебе." % s.name)
		else:
			siege_requested.emit(s)
		return
	if player.rel.has(s.fac):
		player.rel[s.fac] = minf(100.0, float(player.rel[s.fac]) + 0.5)
	quests.on_enter(player, s, float(player_effects().get("quest", 0.0)))
	settlement_entered.emit(s)

func _meetings() -> void:
	if player.busy != "" or player.inside or player.away:
		return
	for p in roster.parties:
		if p.hide or p.kind == "camp" or p.get("lock", false):
			continue
		if Vector2(p.x - player.x, p.y - player.y).length() < 22.0 and Rules.hostile_to_player(p, player.rel) and p.cd <= 0.0:
			player.stop()
			player.busy = "enc"
			party_met.emit(p, true)
			return

func hour_tick() -> void:
	hours_passed += 1
	roster.hour_tick(clock.hour)
	wars.day = clock.day
	wars.hour = clock.hour
	wars.war_hour()
	undead.day = clock.day
	undead.hour_tick()
	if clock.hour == 12:
		clans.refill()
	if clock.hour % 3 == 0:
		Rules.player_rel = player.rel
		siege.assaults_tick(player)
	if not player.away and player.busy != "battle":
		quests.scout_tick(player)
		var heal := (0.035 if player.inside else (0.006 if player.has_route() else 0.014)) * (1.0 + (float(player.hero.get("int", 1)) - 1.0) * 0.04 + float(player_effects().get("heal", 0.0)))
		player.hero.hp = minf(1.0, float(player.hero.get("hp", 1.0)) + heal)
		WorldCompanions.heal(player, heal)
	if clock.hour == 0:
		_day_tick()

func player_effects() -> Dictionary:
	return CompanionProfile.party_effects(player.hero, player.comps, companion_catalog, perks)

func log_world(text: String) -> void:
	journal.push_front({"day": clock.day, "text": text})
	if journal.size() > 60:
		journal.pop_back()
	log_added.emit(text)

func _day_tick() -> void:
	wars.war_day()
	clans.day_tick()
	undead.day_tick()
	quests.gen_boards(clock.day)
	companions.day(player, clock.day)
	if not player.away:
		vassals.day_tick()
	var held := siege.holdings_day(player, float(player_effects().get("wage", 0.0)))
	if held != "":
		log_world(held)
	if player.away or player.busy == "battle":
		return
	var wage := func(type: String) -> float: return float(roster.catalog.get_troop(type).wage)
	var name := func(type: String) -> String: return roster.catalog.get_troop(type).name
	var fx := player_effects()
	var comp_wage := roundi(companions.wage(player) * (1.0 - float(fx.get("wage", 0.0))))
	if player.gold >= comp_wage:
		player.gold -= comp_wage
	else:
		player.gold = 0
		companions.unpaid(player)
	for line in PartyEconomy.day_tick(player, wage, fx, roster.rng, name):
		log_world(line)
	quests.deadline_day(player, clock.day)

## Party near a map point the player can chase (worldClick).
func party_near(x: float, y: float, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := radius
	for p in roster.parties:
		if p.hide or p.kind == "camp":
			continue
		var d := Vector2(p.x - x, p.y - y).length()
		if d < bd:
			bd = d
			best = p
	return best

## Sets the chase target: a party, or the garrison of a lair. Returns "" or a reason.
func chase(target: Dictionary) -> String:
	player.enter_id = -1
	if target.has("troops"):
		player.tid = target.id
	elif target.get("kind") == "camp":
		if target.get("camp") == null or roster.party_by_id(target.camp).is_empty():
			return "Логово пусто"
		player.tid = int(target.camp)
	var tg: Dictionary = roster.party_by_id(player.tid)
	player.rp = 0.6
	player.path_to(map.paths, tg.x, tg.y)
	return ""

func settlement_near(x: float, y: float, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius
	for s in map.settles:
		var d := sqrt((s.x - x) * (s.x - x) + (s.y - y) * (s.y - y))
		if d < best_d:
			best_d = d
			best = s
	return best
