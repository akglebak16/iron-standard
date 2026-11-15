extends RefCounted
## A running world: map, clock and the player's party. Settlement rules, parties and AI plug into step()/hour_tick() in later slices.
const WorldMap = preload("res://campaign/world/world_map.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const WorldClock = preload("res://campaign/world/world_clock.gd")
const PlayerParty = preload("res://campaign/world/player_party.gd")

var map: RefCounted
var clock := WorldClock.new()
var player := PlayerParty.new()
var culture := "emp"
var home_id := 0
var hours_passed := 0

static func create(seed_value: int, data: EuropeData, player_culture := "emp") -> RefCounted:
	var state := new()
	state.culture = player_culture
	state.map = WorldMap.create(seed_value, data)
	state._place_player(seed_value)
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

func hour_tick() -> void:
	hours_passed += 1

func settlement_near(x: float, y: float, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius
	for s in map.settles:
		var d := sqrt((s.x - x) * (s.x - x) + (s.y - y) * (s.y - y))
		if d < best_d:
			best_d = d
			best = s
	return best
