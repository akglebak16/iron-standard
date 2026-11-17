extends RefCounted
## A running world: map, clock and the player's party. Settlement rules, parties and AI plug into step()/hour_tick() in later slices.
const WorldMap = preload("res://core/campaign/world/world_map.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const WorldClock = preload("res://core/campaign/world/world_clock.gd")
const PlayerParty = preload("res://core/campaign/world/player_party.gd")
const PartyRoster = preload("res://core/campaign/world/party_roster.gd")
const PartyAI = preload("res://core/campaign/world/party_ai.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const PartyEconomy = preload("res://core/campaign/economy/party_economy.gd")
const WorldWars = preload("res://core/campaign/world/world_wars.gd")
const WorldSiege = preload("res://core/campaign/world/world_siege.gd")
const WorldQuests = preload("res://core/campaign/world/world_quests.gd")
const WorldUndead = preload("res://core/campaign/world/world_undead.gd")
const WorldClans = preload("res://core/campaign/world/world_clans.gd")
const WorldVassals = preload("res://core/campaign/world/world_vassals.gd")
const WorldSkirmish = preload("res://core/campaign/world/world_skirmish.gd")
const WorldCompanions = preload("res://core/campaign/world/world_companions.gd")
const CompanionCatalog = preload("res://core/characters/data/companion_catalog.gd")
const GearCatalog = preload("res://core/equipment/data/gear_catalog.gd")
const CompanionProfile = preload("res://core/characters/rules/companion_profile.gd")
const Market = preload("res://core/campaign/economy/market.gd")
const GoodsCatalog = preload("res://core/campaign/data/goods_catalog.gd")
const PerkCatalog = preload("res://core/characters/data/perk_catalog.gd")
const PerkEffects = preload("res://core/characters/rules/perk_effects.gd")
const TroopCatalog = preload("res://core/troops/data/catalog.gd")
const FactionCatalog = preload("res://core/campaign/data/faction_catalog.gd")
const ThreatMap = preload("res://core/campaign/world/threat_map.gd")
const Config = preload("res://core/campaign/config.gd")

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
var skirmish: WorldSkirmish
var companions: WorldCompanions
var companion_catalog := CompanionCatalog.new()
var gear: GearCatalog
var journal: Array = []  # [{day, text}]
var ai: PartyAI
var threat: ThreatMap = null  # derived from parties (ADR-023): rebuilt on the first request after each step or hour; never saved
var _threat_step := 0         # world steps and hours so far in this session (not saved): the map is rebuilt when it changes
var _threat_built := -1
## Standing still on purpose (G.wait): time passes although the party does not move. Not saved, like in the browser.
var waiting := false

## Release owned subscriptions and the deliberate cross-links between campaign systems.
## Called when leaving the campaign; disposing one context must not clear another's data.
func dispose() -> void:
	for source in [wars, undead, clans, quests, companions, vassals, siege]:
		if source == null: continue
		for info in source.get_signal_list():
			for connection in source.get_signal_connection_list(info.name):
				source.disconnect(info.name, connection.callable)
	if wars != null:
		wars.clans = null
		wars.player = null
		wars.vassals = null
		wars.threat = Callable()
		wars.doomed = Callable()
		wars.retake = Callable()
	if undead != null: undead.dispose()
	if ai != null: ai.dispose()
	if clans != null: clans.siege = null
	ai = null
	threat = null
	wars = null
	clans = null
	siege = null
	quests = null
	undead = null
	vassals = null
	skirmish = null
	companions = null
	roster = null

static func create(seed_value: int, data: EuropeData, player_culture: String, definitions: Dictionary) -> RefCounted:
	if not START_TROOPS.has(player_culture) or data == null: return null
	if not definitions.get("troops") is TroopCatalog or not definitions.get("factions") is FactionCatalog: return null
	if not definitions.get("gear") is GearCatalog or not definitions.get("goods") is GoodsCatalog: return null
	if not definitions.get("perks") is PerkCatalog or not definitions.get("companions") is CompanionCatalog: return null
	if not data.is_ready(): return null
	for key in ["troops", "factions", "gear", "goods", "perks", "companions"]:
		if not definitions[key].is_ready(): return null
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
	state.perks = definitions.perks
	var goods: GoodsCatalog = definitions.goods
	state.market = Market.new(goods, RandomNumberGenerator.new())
	state.market.rng.seed = seed_value + 191
	var gear_catalog: GearCatalog = definitions.gear
	state.gear = gear_catalog
	state.market.gear = gear_catalog.definitions()
	state.roster = PartyRoster.new(state.map, seed_value, definitions.troops, definitions.factions)
	state.roster.player = state.player
	state.roster.populate()
	state.wars = WorldWars.new(state.map, state.roster)
	state.wars.start()
	state.siege = WorldSiege.new(state.wars, state.roster, state.roster.rng)
	state.wars.announced.connect(func(t): state.log_world(t, JOURNAL_INFO))
	state.wars.settlement_changed.connect(func(s): state.settlement_changed.emit(s))
	state.wars.holding_news.connect(func(s, t, good): state.log_world(t, JOURNAL_GOOD if good else JOURNAL_BAD); state.settlement_changed.emit(s))
	state.wars.player = state.player
	state.wars.threat = func(x: float, y: float, f: String) -> float: return state.threat_map().threat(x, y, state.threat_enemies(f))
	state.ai = PartyAI.new(state.roster, state.player)
	state.undead = WorldUndead.new(state.roster, state.wars)
	state.undead.init()
	state.undead.announced.connect(func(t): state.log_world(t, JOURNAL_BAD))
	state.undead.settlement_changed.connect(func(s): state.settlement_changed.emit(s))
	state.ai.undead = state.undead
	state.undead.set_field(func(x: float, y: float, f: String) -> float: return state.threat_map().influence(f, x, y))
	state.wars.doomed = state.undead.doomed
	state.wars.retake = state.undead.host_retake
	state.clans = WorldClans.new(state.roster, state.wars, state.player)
	state.clans.siege = state.siege
	state.clans.init()
	state.clans.ruler_day()
	state.clans.announced.connect(func(t): state.log_world(t, JOURNAL_INFO))
	state.clans.message.connect(func(t): state.log_world(t, JOURNAL_INFO))
	state.wars.clans = state.clans
	state.ai.clans = state.clans
	state.roster.clans_on = true
	state.companion_catalog = definitions.companions
	state.quests = WorldQuests.new(state.map, state.market.goods, state.roster.catalog, state.wars, state.roster.rng)
	state.quests.message.connect(state.log_world)
	state.quests.gen_boards(state.clock.day)
	state.companions = WorldCompanions.new(state.map, state.companion_catalog, state.roster.rng)
	state.companions.message.connect(state.log_world)
	state.companions.ensure(state.player)
	state.vassals = WorldVassals.new(state.roster, state.siege, state.companions, state.player)
	state.vassals.message.connect(func(t): state.log_world(t, JOURNAL_INFO))
	state.wars.vassals = state.vassals
	state.ai.vassals = state.vassals
	state.siege.captured.connect(func(_s, t): state.log_world(t, JOURNAL_GOOD))
	state.siege.surrendered.connect(func(s, t): state.log_world(t, JOURNAL_INFO); state.settlement_changed.emit(s))
	state.skirmish = WorldSkirmish.new(state.roster)
	state.skirmish.clans = state.clans
	state.skirmish.undead = state.undead
	state.ai.skirmish = state.skirmish
	state.ai.threat_map = state.threat_map
	state.ai.enemies = state.threat_enemies
	state.rel_watch()
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

## The world only lives while the party travels, chases someone or waits (worldUpdate in src/07_main.js).
func advance(real_dt: float) -> int:
	if not (waiting or is_moving()):
		return 0
	return clock.advance(real_dt, step, hour_tick)

## The same time flow as advance(), split for a simulation that runs elsewhere (world_sim_thread.gd): tick_time() lets
## real time pass, advance_one() runs one due step.
func tick_time(real_dt: float) -> void:
	if waiting or is_moving():
		clock.add_time(real_dt)

func advance_one() -> bool:
	if not (waiting or is_moving()):
		return false
	return clock.advance_one(step, hour_tick)

func is_moving() -> bool:
	return player.has_route() or player.tid >= 0

## Z on the map: stand and let time pass, or go on again.
func toggle_wait() -> String:
	waiting = not waiting
	if waiting:
		player.stop()
		player.tid = -1
	return "Отряд ждёт" if waiting else "Снова в путь"

## Attacking a party the player is at peace with (encAttack).
func attack(p: Dictionary) -> void:
	player.rel[p.fac] = maxf(-100.0, float(player.rel.get(p.fac, 0)) - (12.0 if p.kind == "caravan" else 30.0))
	log_world("Ты напал на %s. Отношения испорчены." % roster.factions.get_faction(p.fac).get("gen", p.fac), JOURNAL_BAD)
	rel_watch()

func step(dh: float) -> void:
	_threat_step += 1
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
	waiting = false
	if s.is_empty() or s.kind == "camp" or Vector2(s.x - player.x, s.y - player.y).length() > 60.0:
		return
	player.stop()
	if WorldSiege.hostile(s, player.rel):
		if s.kind == "village":
			log_world("%s: жители заперлись, эта фракция враждебна тебе." % s.name, JOURNAL_BAD)
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
	rel_watch()
	skirmish.hour_now = wars.now_h()
	skirmish.hour_tick()
	if clock.hour == 12:
		clans.refill()
	for line in siege.block_hour(player, clock.hour):
		log_world(line)
	if not player.away and player.busy != "battle":
		quests.scout_tick(player)
		var heal := (0.035 if player.inside else (0.006 if player.has_route() else 0.014)) * (1.0 + (float(player.hero.get("int", 1)) - 1.0) * 0.04 + float(player_effects().get("heal", 0.0)))
		player.hero.hp = minf(1.0, float(player.hero.get("hp", 1.0)) + heal)
		WorldCompanions.heal(player, heal)
	if clock.hour == 0:
		_day_tick()
	_threat_step += 1
	undead.wave_tick()
	ai.hour_tick()

## Threat map of the current world step (DESIGN.md §5.1, ADR-023). The first request after a step or an hour rebuilds
## it from the parties, so a loaded world sees exactly the map the saved one would have seen. It spends no RNG and is
## not saved. Party goals (party_ai.gd, party_goals.gd) read it for risk, flight and alarms, the operations of factions
## (world_wars.gd) for threats at home, the director of the undead invasion (world_undead.gd) for living armies around
## its targets.
func threat_map() -> ThreatMap:
	if threat == null:
		threat = ThreatMap.new(PartyAI.WW, PartyAI.WH)
	if _threat_built != _threat_step:
		_threat_built = _threat_step
		threat.rebuild(threat_sources(), hours_passed)
	return threat

## Every party with troops, plus the player's own party while it is on the map.
func threat_sources() -> Array:
	var out: Array = []
	for p in roster.parties:
		out.append({"fac": p.fac, "x": p.x, "y": p.y, "strength": roster.strength_of(p)})
	if not player.away and not player.troops.is_empty():
		out.append({"fac": Config.PLAYER_FACTION, "x": player.x, "y": player.y, "strength": Rules.strength(player.troops, roster.info)})
	return out

## Factions hostile to `fac` that have strength on the threat map.
func threat_enemies(fac: String) -> Array:
	return threat_map().enemies_of(fac, func(a: String, b: String) -> bool: return ThreatMap.factions_hostile(a, b, wars.wars, player.rel))

var _hostile := {}

## Tells the player when a state turns hostile or makes peace with him (relWatch).
func rel_watch() -> void:
	for f in Rules.REAL_FACTIONS:
		var h: bool = float(player.rel.get(f, 0)) < -20.0
		if not _hostile.has(f):
			_hostile[f] = h
			continue
		if _hostile[f] == h:
			continue
		_hostile[f] = h
		var gen: String = roster.factions.get_faction(f).get("gen", f)
		log_world(("Ты теперь враг %s: их лорды нападут, ворота их городов закрыты." if h else "Ты больше не враг %s.") % gen, JOURNAL_BAD if h else JOURNAL_GOOD)

## The player declares war to besiege a town of a state he is at peace with (declareWar).
func declare_war(f: String) -> void:
	if not f in Rules.REAL_FACTIONS:
		return
	player.rel[f] = minf(float(player.rel.get(f, 0)), -45.0)
	rel_watch()

func player_effects() -> Dictionary:
	return CompanionProfile.party_effects(player.hero, player.comps, companion_catalog, perks)

## Journal entry kinds (logW kind in src/05_world.js): neutral, bad, info, good.
const JOURNAL_NEUTRAL := 0
const JOURNAL_BAD := 1
const JOURNAL_INFO := 2
const JOURNAL_GOOD := 3

func log_world(text: String, kind: int = JOURNAL_NEUTRAL) -> void:
	journal.push_front({"day": clock.day, "text": text, "kind": kind})
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
