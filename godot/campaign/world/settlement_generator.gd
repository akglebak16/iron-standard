extends RefCounted
## Port of genSettlementsV2 (src/05_world.js): towns, castles, villages and bandit camps of the Europe map.
## Settlements are plain Dictionaries with the same fields the rules in campaign/rules already use.
const Generator = preload("res://campaign/world/terrain_generator.gd")
const WorldNoise = preload("res://campaign/world/noise.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")

var _world: Generator
var _data: EuropeData
var _rng: WorldNoise.Mulberry
var _extra: RandomNumberGenerator   # only for prosperity, which the browser takes from Math.random
var settles: Array = []
var _next_id := 1

## Returns the settlements; `next_id` of the world is read from `next_id()` afterwards.
func generate(world: Generator, data: EuropeData, seed_value: int) -> Array:
	_world = world
	_data = data
	_rng = WorldNoise.Mulberry.new(seed_value + 11)
	_extra = RandomNumberGenerator.new()
	_extra.seed = seed_value
	settles = []
	_next_id = 1
	var factions: Array = data.factions
	for f in factions:
		_place(f, "town", data.town_names[f].town[0], 300.0, [data.regions[f].cap], 1)
	for i in range(1, 4):
		for f in factions:
			_place(f, "town", data.town_names[f].town[i], 300.0, data.regions[f].discs, 8)
	for i in 3:
		for f in factions:
			_place(f, "castle", data.town_names[f].castle[i], 240.0, data.regions[f].discs, 8)
	for i in 8:
		for f in factions:
			_place(f, "village", data.town_names[f].village[i], 150.0, data.regions[f].discs, 6)
	# bandit camps: one set per faction and in the wild lands
	for i in data.camp_names.size():
		var region: String = factions[i % factions.size()] if i < 10 else "wild"
		_place("bandit", "camp", data.camp_names[i], 200.0, data.regions[region].discs, 4)
	return settles

func next_id() -> int:
	return _next_id

func _ok(x: float, y: float, min_dist: float) -> bool:
	if x < 90.0 or y < 90.0 or x > Generator.WW - 90.0 or y > Generator.WH - 90.0:
		return false
	var k := _world.cell_of(x, y)
	if _world.comp[k] != _world.main_comp or _world.cells[k] != 1:
		return false
	var ci := k % Generator.GW
	var cj := k / Generator.GW
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var a := ci + di
			var b := cj + dj
			if a >= 0 and b >= 0 and a < Generator.GW and b < Generator.GH and _world.cells[b * Generator.GW + a] == 5:
				return false
	for s in settles:
		var dx: float = s.x - x
		var dy: float = s.y - y
		if sqrt(dx * dx + dy * dy) < min_dist:
			return false
	return true

func _spot(discs: Array, scale: float) -> Array:
	var total := 0.0
	for d in discs:
		total += float(d[2]) * float(d[3])
	var q := _rng.next() * total
	var disc: Array = discs[discs.size() - 1]
	for c in discs:
		if q < float(c[2]) * float(c[3]):
			disc = c
			break
		q -= float(c[2]) * float(c[3])
	var a := _rng.next() * TAU
	var r := sqrt(_rng.next())
	return [_world.eu_x(float(disc[0]) + cos(a) * r * float(disc[2]) * scale), _world.eu_y(float(disc[1]) + sin(a) * r * float(disc[3]) * scale)]

func _place(fac: String, kind: String, place_name: String, min_dist: float, discs: Array, candidates: int) -> void:
	var best = null
	var best_d := -1.0
	var tries := 0
	var found := 0
	var scale := 1.0
	while found < candidates and tries < 1500:
		tries += 1
		if tries % 250 == 0:
			scale *= 1.2
		var p := _spot(discs, scale)
		if not _ok(p[0], p[1], min_dist):
			continue
		found += 1
		var d := 1e9
		for s in settles:
			d = minf(d, sqrt((s.x - p[0]) * (s.x - p[0]) + (s.y - p[1]) * (s.y - p[1])))
		if d > best_d:
			best_d = d
			best = p
	if best == null:
		while best == null and tries < 6000:
			var p := _spot(discs, 3.0 + tries / 500.0)
			if _ok(p[0], p[1], min_dist * 0.6):
				best = p
			tries += 1
	assert(best != null, "no place for " + place_name)
	settles.append({"id": _next_id, "kind": kind, "fac": fac, "name": place_name, "x": best[0], "y": best[1], "recruits": [], "rt": 0, "pros": _extra.randi_range(2, 5), "camp": null, "cleared": false, "respawn": 0, "hv": 0})
	_next_id += 1
