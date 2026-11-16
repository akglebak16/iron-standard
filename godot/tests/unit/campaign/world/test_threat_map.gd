extends SceneTree
## Threat map (ADR-023): synthetic parties with made-up faction IDs, the empty map, linear cost, and the live world:
## building and refreshing it spends no RNG and does not touch the checkpoint.
const ThreatMap = preload("res://core/campaign/world/threat_map.gd")
const Config = preload("res://core/campaign/config.gd")
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldCheckpoint = preload("res://core/campaign/world/world_checkpoint.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")

func _initialize() -> void:
	_check_empty()
	_check_falloff()
	_check_factions()
	_check_safe_cell()
	_check_front()
	_check_linear_cost()
	_check_world()
	print("Threat map tests passed")
	quit(0)

func _src(fac: String, x: float, y: float, strength: float) -> Dictionary:
	return {"fac": fac, "x": x, "y": y, "strength": strength}

func _check_empty() -> void:
	var m := ThreatMap.new()
	assert(m.cols == 52 and m.rows == 34, "Europe 5200×3400 in 100-unit cells")
	assert(m.threat(500.0, 500.0, ["aa"]) == 0.0, "nothing before the first rebuild")
	m.rebuild([], 7)
	assert(m.factions().is_empty() and m.built_hour == 7 and m.stamped_cells == 0)
	assert(m.influence("aa", 2600.0, 1700.0) == 0.0)
	assert(m.front("aa", "bb").is_empty())
	assert(m.enemies_of("aa", func(_a, _b): return true).is_empty())
	var safe := m.safe_cell(2610.0, 1720.0, 300.0, "aa", [], [])
	assert(safe == m.cell_center(m.cell_index(2610.0, 1720.0)), "an empty map keeps the party where it stands: %s" % safe)
	m.rebuild([_src("aa", 100.0, 100.0, 0.0), _src("aa", 100.0, 100.0, -5.0)])
	assert(m.factions().is_empty() and m.sources == 0, "parties without strength stamp nothing")

func _check_falloff() -> void:
	var m := ThreatMap.new()
	m.rebuild([_src("zz_test", 1050.0, 1050.0, 100.0)])
	assert(is_equal_approx(m.influence("zz_test", 1050.0, 1050.0), 100.0), "full strength in the party's own cell")
	var near := m.influence("zz_test", 1150.0, 1050.0)
	var far := m.influence("zz_test", 1250.0, 1050.0)
	assert(is_equal_approx(near, 100.0 * (1.0 - 100.0 / Config.THREAT_RADIUS)), "linear falloff: %f" % near)
	assert(far < near and far > 0.0)
	assert(m.influence("zz_test", 1050.0 + Config.THREAT_RADIUS + 50.0, 1050.0) == 0.0, "nothing beyond the radius")
	assert(m.influence("other_id", 1050.0, 1050.0) == 0.0, "other factions are separate layers")
	m.rebuild([_src("zz_test", 1050.0, 1050.0, 100.0), _src("zz_test", 1050.0, 1050.0, 40.0)])
	assert(is_equal_approx(m.influence("zz_test", 1050.0, 1050.0), 140.0), "parties of one faction add up")
	# corners and edges clamp instead of failing
	m.rebuild([_src("zz_test", 0.0, 0.0, 10.0), _src("zz_test", 5200.0, 3400.0, 10.0)])
	assert(m.influence("zz_test", 0.0, 0.0) > 0.0 and m.influence("zz_test", 5199.0, 3399.0) > 0.0)
	assert(m.influence("zz_test", -50.0, -50.0) == m.influence("zz_test", 0.0, 0.0), "queries outside clamp to the border cell")

func _check_factions() -> void:
	var m := ThreatMap.new()
	m.rebuild([_src("aa", 2000.0, 1000.0, 100.0), _src("bb", 2050.0, 1000.0, 60.0), _src("cc", 2000.0, 1050.0, 30.0)])
	var hostile := func(a: String, b: String) -> bool: return (a == "aa" and b == "bb") or (a == "bb" and b == "aa")
	assert(m.enemies_of("aa", hostile) == ["bb"])
	assert(m.enemies_of("cc", hostile).is_empty(), "a faction at peace with everyone has no enemies")
	var t := m.threat(2050.0, 1050.0, m.enemies_of("aa", hostile))
	assert(is_equal_approx(t, m.influence("bb", 2050.0, 1050.0)), "threat counts only enemy layers")
	assert(t > 0.0 and m.threat(2050.0, 1050.0, []) == 0.0)
	var wars := {"aa|bb": {"since": 1}}
	assert(ThreatMap.factions_hostile("aa", "bb", wars, {}) and not ThreatMap.factions_hostile("aa", "cc", wars, {}))
	assert(not ThreatMap.factions_hostile("aa", "aa", wars, {}))
	assert(ThreatMap.factions_hostile("aa", Config.BANDIT_FACTION, {}, {}) and ThreatMap.factions_hostile(Config.UNDEAD_FACTION, "aa", {}, {}))
	assert(ThreatMap.factions_hostile(Config.PLAYER_FACTION, "aa", {}, {"aa": -50}))
	assert(not ThreatMap.factions_hostile("aa", Config.PLAYER_FACTION, {}, {"aa": 10}))
	assert(not ThreatMap.factions_hostile(Config.PLAYER_FACTION, "aa", {}, {}), "unknown relation is neutral")

func _check_safe_cell() -> void:
	var m := ThreatMap.new()
	var enemy := Vector2(2000.0, 1500.0)
	m.rebuild([_src("bb", enemy.x, enemy.y, 300.0)])
	var start := Vector2(2120.0, 1520.0)
	var safe := m.safe_cell(start.x, start.y, 400.0, "aa", ["bb"], [])
	assert(m.threat(safe.x, safe.y, ["bb"]) < m.threat(start.x, start.y, ["bb"]), "the safe cell has less threat")
	assert(safe.distance_to(enemy) > start.distance_to(enemy))
	assert(safe.distance_to(start) <= 400.0 + 0.01)
	# with a haven the party runs home, not just away
	var haven := Vector2(2200.0, 1900.0)
	var home := m.safe_cell(start.x, start.y, 400.0, "aa", ["bb"], [haven])
	assert(home.distance_to(haven) < safe.distance_to(haven), "haven pulls the choice: %s vs %s" % [home, safe])
	assert(m.threat(home.x, home.y, ["bb"]) < m.threat(start.x, start.y, ["bb"]))
	# own strength shelters, rejected cells are never picked
	m.rebuild([_src("bb", enemy.x, enemy.y, 300.0), _src("aa", 2100.0, 1150.0, 500.0)])
	var shelter := m.safe_cell(start.x, start.y, 400.0, "aa", ["bb"], [])
	assert(shelter.distance_to(Vector2(2100.0, 1150.0)) < safe.distance_to(Vector2(2100.0, 1150.0)), "allies attract")
	var east := m.safe_cell(start.x, start.y, 400.0, "aa", ["bb"], [], func(c: Vector2) -> bool: return c.x <= 2200.0)
	assert(east.x <= 2200.0)
	var none := m.safe_cell(start.x, start.y, 400.0, "aa", ["bb"], [], func(_c: Vector2) -> bool: return false)
	assert(none == start, "nothing accepted: stay")
	assert(m.safe_cell(start.x, start.y, 400.0, "aa", ["bb"], []) == shelter, "deterministic")

func _check_front() -> void:
	var m := ThreatMap.new()
	m.rebuild([_src("aa", 1000.0, 1000.0, 100.0), _src("bb", 1300.0, 1000.0, 100.0)])
	var f := m.front("aa", "bb")
	assert(not f.is_empty(), "equal neighbours meet in the middle")
	var mean := 0.0
	for c in f:
		assert(c.x > 1000.0 and c.x < 1300.0, "front lies between them: %s" % c)
		mean += c.x
	mean /= f.size()
	assert(absf(mean - 1150.0) < 1.0, "symmetric front: %f" % mean)
	assert(m.front("aa", "bb") == m.front("bb", "aa"))
	assert(m.front("aa", "missing").is_empty())
	m.rebuild([_src("aa", 1000.0, 1000.0, 100.0), _src("bb", 1300.0, 1000.0, 400.0)])
	var g := m.front("aa", "bb")
	var mean_g := 0.0
	for c in g:
		mean_g += c.x
	mean_g /= maxi(1, g.size())
	assert(not g.is_empty() and mean_g < mean, "a stronger side pushes the front back: %f < %f" % [mean_g, mean])

func _check_linear_cost() -> void:
	var m := ThreatMap.new()
	var list: Array = []
	for i in 10:
		list.append(_src("f%d" % (i % 3), 600.0 + i * 37.0, 700.0 + i * 23.0, 50.0))
	m.rebuild(list)
	var one := m.stamped_cells
	assert(one == 10 * 49, "an inner party visits a 7×7 square: %d" % one)
	for i in 10:
		list.append(_src("f%d" % (i % 3), 2600.0 + i * 41.0, 1700.0 + i * 19.0, 50.0))
	m.rebuild(list)
	assert(m.stamped_cells == 2 * one and m.sources == 20, "twice the parties, twice the work")

func _check_world() -> void:
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var s := WorldState.create(3, data, "emp", ContentLoader.registry())
	assert(s.threat == null, "nothing is built until someone asks")
	var before := WorldCheckpoint.capture(s)
	var rng_state: int = s.roster.rng.state
	var market_state: int = s.market.rng.state
	var m: ThreatMap = s.threat_map()
	assert(m.built_hour == s.hours_passed and m.sources > 50)
	var lords: Array = s.roster.parties.filter(func(p): return p.kind == "lord")
	assert(m.influence("emp", lords[0].x, lords[0].y) > 0.0 or lords[0].fac != "emp")
	var enemies: Array = s.threat_enemies("emp")
	assert("nord" in enemies and "bandit" in enemies, "default wars of the empire: %s" % [enemies])
	assert(not "kin" in enemies and not "emp" in enemies)
	assert(not "player" in s.threat_enemies("emp"), "player at peace by default")
	assert(s.roster.rng.state == rng_state and s.market.rng.state == market_state, "the map spends no RNG")
	assert(WorldCheckpoint.capture(s) == before, "the map leaves the saved world untouched")
	for component in WorldCheckpoint.FIELDS:
		for field in WorldCheckpoint.FIELDS[component]:
			assert(not "threat" in String(field), "the threat map is never saved")
	s.player.away = true
	s.step(0.2)
	s.hour_tick()
	assert(s.threat_map() == m and m.built_hour == s.hours_passed, "hour_tick refreshes the map once it is in use")
	assert(not s.threat_sources().any(func(x): return x.fac == Config.PLAYER_FACTION), "an absent player stamps nothing")
	s.dispose()
	assert(s.threat == null)
