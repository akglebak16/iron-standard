extends RefCounted
## A running world: map, clock and the player's party. Settlement rules, parties and AI plug into step()/hour_tick() in later slices.
const WorldMap = preload("res://campaign/world/world_map.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const WorldClock = preload("res://campaign/world/world_clock.gd")
const PlayerParty = preload("res://campaign/world/player_party.gd")
const PartyRoster = preload("res://campaign/world/party_roster.gd")
const PartyAI = preload("res://campaign/world/party_ai.gd")
const Rules = preload("res://campaign/world/party_rules.gd")

## Starting troops by culture (CULT in src/05_world.js).
const START_TROOPS := {
	"nord": [["n1", 6], ["n2a", 2], ["n2s", 2]], "emp": [["e1", 6], ["e2a", 3], ["e2s", 1]],
	"khan": [["k1", 5], ["k2a", 3], ["k2c", 2]], "kin": [["f1", 6], ["f2a", 3], ["f2s", 1]],
	"dom": [["d1", 6], ["d2x", 3], ["d2s", 1]], "pact": [["p1", 6], ["p2a", 3], ["p2s", 1]],
	"emi": [["m1", 5], ["m2a", 3], ["m2c", 2]],
}

signal party_met(party: Dictionary, forced: bool)

var map: RefCounted
var clock := WorldClock.new()
var player := PlayerParty.new()
var culture := "emp"
var home_id := 0
var hours_passed := 0
var roster: PartyRoster
var ai: PartyAI

static func create(seed_value: int, data: EuropeData, player_culture := "emp") -> RefCounted:
	var state := new()
	state.culture = player_culture
	state.map = WorldMap.create(seed_value, data)
	state._place_player(seed_value)
	for t in START_TROOPS[player_culture]:
		state.player.troops.append({"type": t[0], "n": t[1]})
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
	_meetings()
	ai.step(dh)

## A hostile party that reaches the player forces a meeting (stepWorld).
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

func settlement_near(x: float, y: float, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius
	for s in map.settles:
		var d := sqrt((s.x - x) * (s.x - x) + (s.y - y) * (s.y - y))
		if d < best_d:
			best_d = d
			best = s
	return best
