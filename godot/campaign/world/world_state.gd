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
signal settlement_entered(settlement: Dictionary)

var map: RefCounted
var clock := WorldClock.new()
var player := PlayerParty.new()
var culture := "emp"
var home_id := 0
var hours_passed := 0
var roster: PartyRoster
var perks := PerkCatalog.new()
var journal: Array = []  # [{day, text}]
var ai: PartyAI

static func create(seed_value: int, data: EuropeData, player_culture := "emp") -> RefCounted:
	var state := new()
	state.culture = player_culture
	state.map = WorldMap.create(seed_value, data)
	state._place_player(seed_value)
	state.player.culture = player_culture
	state.player.hero = {"name": "Безымянный", "lvl": 1, "xp": 0, "pts": 2, "pp": 1, "perks": [], "str": 1, "vit": 1, "agi": 1,
		"int": 1, "cha": 1, "armor": 0, "weapon": 0, "shield": 0, "horse": 1 if player_culture in ["khan", "emi"] else 0, "hp": 1.0, "seed": seed_value % 99999 + 1}
	for t in START_TROOPS[player_culture]:
		state.player.troops.append({"type": t[0], "n": t[1]})
	assert(state.perks.load_data())
	state.roster = PartyRoster.new(state.map, seed_value)
	state.roster.populate()
	state.ai = PartyAI.new(state.roster, state.player)
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
	if player.rel.has(s.fac):
		player.rel[s.fac] = minf(100.0, float(player.rel[s.fac]) + 0.5)
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
	if clock.hour == 0:
		_day_tick()

func player_effects() -> Dictionary:
	return PerkEffects.own(player.hero, perks)

func log_world(text: String) -> void:
	journal.push_front({"day": clock.day, "text": text})
	if journal.size() > 60:
		journal.pop_back()
	log_added.emit(text)

func _day_tick() -> void:
	if player.away or player.busy == "battle":
		return
	var wage := func(type: String) -> float: return float(roster.catalog.get_troop(type).wage)
	var name := func(type: String) -> String: return roster.catalog.get_troop(type).name
	for line in PartyEconomy.day_tick(player, wage, player_effects(), roster.rng, name):
		log_world(line)

func settlement_near(x: float, y: float, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius
	for s in map.settles:
		var d := sqrt((s.x - x) * (s.x - x) + (s.y - y) * (s.y - y))
		if d < best_d:
			best_d = d
			best = s
	return best
