extends RefCounted
## Every non-player party on the map: lords, vassals, bandits, caravans and camp garrisons, plus their spawning (newWorld/hourTick in src/05_world.js).
const Rules = preload("res://core/campaign/world/party_rules.gd")
const Generation = preload("res://core/troops/rules/generation.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const FactionCatalog = preload("res://core/campaign/data/faction_catalog.gd")
const WorldMap = preload("res://core/campaign/world/world_map.gd")
const SettlementRecruits = preload("res://core/campaign/rules/settlement_recruits.gd")

const LORD_MIN := 130
const LORD_MAX := 190
const LORD_NEW_MIN := 95
const LORD_NEW_MAX := 145
const LORDS_PER_FACTION := 5
const VASSALS_PER_FACTION := 4
const VAS_MIN := 50
const VAS_MAX := 80
const VAS_NEW_MIN := 35
const VAS_NEW_MAX := 55
const BANDIT_N := 1.3
const BANDIT_BIG := 0.25
const VASSAL_TITLE := {"nord": "Хёвдинг", "emp": "Трибун", "khan": "Багатур", "kin": "Шевалье", "emi": "Сипахи"}

var map: WorldMap
var player: RefCounted
var diplomatic_wars: Variant = null
var rng := RandomNumberGenerator.new()
var catalog: Catalog
var factions: FactionCatalog
var clans_on := false  # houses refill lords themselves (WorldClans.refill)
var info := {}  # troop id -> {tier, mounted, pw}
var parties: Array = []
var _next_party_id := 1000000  # party ids stay clear of settlement ids

func _init(world_map: WorldMap, seed_value: int, troops: Catalog, faction_definitions: FactionCatalog) -> void:
	map = world_map
	rng.seed = seed_value + 77
	catalog = troops
	factions = faction_definitions
	for f in Rules.REAL_FACTIONS + ["bandit", "undead"]:
		for t in catalog.for_faction(f):
			info[t.id] = {"tier": t.tier, "mounted": t.mounted, "pw": t.get("pw", 1.0)}

func hostile(a: Dictionary, b: Dictionary) -> bool:
	# Read from the owning player, even after save loading replaces the relation dictionary.
	return Rules.hostile(a, b, diplomatic_wars, player.rel if player != null else {})

func rnd(a: float, b: float) -> float:
	return rng.randf_range(a, b)

func rint(a: int, b: int) -> int:
	return rng.randi_range(a, b)

func pick(list: Array):
	return list[rng.randi_range(0, list.size() - 1)]

func party_by_id(id) -> Dictionary:
	for p in parties:
		if p.id == id:
			return p
	return {}

func remove(p: Dictionary) -> void:
	parties.erase(p)

func strength_of(p: Dictionary) -> float:
	return Rules.strength(p.troops, info)

func unit_name(fac: String) -> String:
	var f := factions.get_faction(fac)
	var names: Array = f.get("names", [])
	if names.is_empty():
		names = factions.get_faction("nord").names
	var n: String = pick(names)
	var nicks: Array = f.get("nicks", [])
	if not nicks.is_empty() and rng.randf() < 0.45:
		return n + " " + str(pick(nicks))
	return n

func lord_name(fac: String) -> String:
	var title: String = factions.get_faction(fac).title
	return title.substr(0, 1).to_upper() + title.substr(1) + " " + unit_name(fac)

func gen_troops(fac: String, n: int, quality: float) -> Array:
	var count := n
	if count > 1:
		count = roundi(n * (1.0 if fac == "bandit" else Rules.MK))
	return Generation.army(catalog, fac, count, quality, rng)

func make_party(kind: String, fac: String, name: String, x: float, y: float, troops: Array, extra := {}) -> Dictionary:
	var p := {"id": _next_party_id, "kind": kind, "fac": fac, "name": name, "x": x, "y": y, "troops": troops,
		"path": [], "pi": 0, "tid": null, "sid": null, "home": null, "state": "idle", "wait": 0.0,
		"hide": false, "gold": 0, "hold": 0, "cd": 0.0, "ai": 0.0, "rp": 0.0, "fx": 1.0,
		# goal of the AI (party_goals.gd): kind ("" = none), target id, hours held, score when taken; old saves lack them
		"goal": "", "gid": null, "ga": 0.0, "gs": 0.0}
	_next_party_id += 1
	p.merge(extra, true)
	parties.append(p)
	return p

func respawn_camp(c: Dictionary) -> void:
	var camp := make_party("camp", "bandit", "Лагерь: " + c.name, c.x, c.y, gen_troops("bandit", rint(12, 20), 0.4), {"home": c.id, "hide": false})
	c.cleared = false
	c.camp = camp.id

func spawn_vassal(f: String, h: Dictionary, n: int) -> Dictionary:
	var lords := parties.filter(func(q): return q.kind == "lord" and q.fac == f)
	var title: String = VASSAL_TITLE.get(f, "Вассал")
	var p := make_party("vassal", f, title + " " + unit_name(f), h.x + rnd(-20, 20), h.y + 24, gen_troops(f, n, 0.55),
		{"home": h.id, "lid": pick(lords).id if not lords.is_empty() else null})
	p.wait = float(rint(1, 12))
	return p

func spawn_caravan(t: Dictionary):
	if t.is_empty() or not (t.fac in Rules.REAL_FACTIONS):
		return null
	var dsts := map.settles.filter(func(s): return s.kind == "town" and s != t and s.fac in Rules.REAL_FACTIONS)
	if dsts.is_empty():
		return null
	var near := dsts.filter(func(s): return Vector2(s.x - t.x, s.y - t.y).length() < 1300.0)
	var dst: Dictionary = pick(near if not near.is_empty() else dsts)
	var p := make_party("caravan", t.fac, "Караван", t.x + 10, t.y + 20, gen_troops(t.fac, rint(3, 5), 0.3), {"home": t.id, "sid": dst.id, "state": "travel"})
	_path_to(p, dst.x, dst.y)
	return p

## Initial population: lords, vassals, camp garrisons and caravans (newWorld).
func populate() -> void:
	for s in map.settles:
		if s.kind == "camp":
			respawn_camp(s)
		else:
			SettlementRecruits.refresh(s, catalog, rng)
	for f in Rules.REAL_FACTIONS:
		var hs := map.settles.filter(func(s): return s.fac == f)
		if hs.is_empty():
			continue
		var noble := hs.filter(func(s): return s.kind != "village")
		for i in LORDS_PER_FACTION:
			var h: Dictionary = hs[0] if i == 0 else pick(noble if not noble.is_empty() else hs)
			var p := make_party("lord", f, lord_name(f), h.x + 12, h.y + 20, gen_troops(f, rint(LORD_MIN, LORD_MAX), 0.6), {"home": h.id})
			p.wait = float(rint(1, 20))
	for f in Rules.REAL_FACTIONS:
		var hs := map.settles.filter(func(s): return s.fac == f and s.kind != "camp")
		for i in VASSALS_PER_FACTION:
			if not hs.is_empty():
				spawn_vassal(f, pick(hs), rint(VAS_MIN, VAS_MAX))
	var towns := map.settles.filter(func(s): return s.kind == "town")
	for i in 8:
		spawn_caravan(pick(towns))

## Hourly settlement upkeep and spawns (hourTick); hour is the clock hour after the tick.
func hour_tick(hour: int) -> void:
	for s in map.settles:
		if s.kind == "camp":
			if s.cleared:
				s.respawn -= 1
				if s.respawn <= 0:
					respawn_camp(s)
			continue
		s.rt += 1
		if s.rt >= 72:
			s.rt = 0
			SettlementRecruits.refresh(s, catalog, rng)
	if hour % 6 == 0:
		_spawn_bandits_and_caravans()
	if hour == 6:
		for f in Rules.REAL_FACTIONS:
			var n := parties.filter(func(p): return p.kind == "vassal" and p.fac == f).size()
			var hs := map.settles.filter(func(s): return s.fac == f and s.kind != "camp")
			if n < VASSALS_PER_FACTION and not hs.is_empty():
				spawn_vassal(f, pick(hs), rint(VAS_NEW_MIN, VAS_NEW_MAX))
	if hour == 12 and not clans_on:
		for f in Rules.REAL_FACTIONS:
			var n := parties.filter(func(p): return p.kind == "lord" and p.fac == f).size()
			var hs := map.settles.filter(func(s): return s.fac == f and s.kind != "village")
			if n < LORDS_PER_FACTION and not hs.is_empty():
				var h: Dictionary = pick(hs)
				make_party("lord", f, lord_name(f), h.x + 10, h.y + 20, gen_troops(f, rint(LORD_NEW_MIN, LORD_NEW_MAX), 0.6), {"home": h.id})

func _spawn_bandits_and_caravans() -> void:
	var bands := parties.filter(func(p): return p.kind == "bandit").size()
	var big := parties.filter(func(p): return p.kind == "bandit" and p.get("big", false)).size()
	var cars := parties.filter(func(p): return p.kind == "caravan").size()
	var camps := map.settles.filter(func(s): return s.kind == "camp" and s.camp != null and not s.get("barrow", false))
	var cap := roundi(10.0 * BANDIT_N)
	if bands - big < cap and not camps.is_empty() and rng.randf() < 0.5 * BANDIT_N:
		var c: Dictionary = pick(camps)
		make_party("bandit", "bandit", unit_name("bandit") + " и шайка", c.x + rnd(-30, 30), c.y + rnd(20, 40), gen_troops("bandit", rint(9, 30), 0.4), {"home": c.id})
	if big < roundi(cap * BANDIT_BIG) and not camps.is_empty() and rng.randf() < 0.25:
		var c: Dictionary = pick(camps)
		make_party("bandit", "bandit", unit_name("bandit") + " и банда", c.x + rnd(-30, 30), c.y + rnd(20, 40), gen_troops("bandit", rint(32, 48), 0.9), {"home": c.id, "big": true})
	if cars < 9 and rng.randf() < 0.5:
		var towns := map.settles.filter(func(s): return s.kind == "town" and s.fac in Rules.REAL_FACTIONS)
		if not towns.is_empty():
			spawn_caravan(pick(towns))

## Walking speed (speedOf): mounted-only parties are faster, bandits slightly so.
func speed_of(p: Dictionary) -> float:
	var base := 17.0
	var any := false
	var mounted := true
	for s in p.troops:
		any = true
		if not info[s.type].mounted:
			mounted = false
	if any and mounted:
		base = 22.0
	var w := map.terrain
	var k: int = w.cell_of(p.x, p.y)
	var t: int = w.cells[k]
	var m := 0.72 if t == 2 else 0.78 if t == 3 else 1.0
	if w.bio[k] == 1:
		m *= 0.85
	if map.paths.road[k] != 0:
		m *= 1.3
	if p.kind == "bandit":
		m *= 1.04
	return base * m

func move_along(p: Dictionary, dh: float) -> bool:
	var rem := speed_of(p) * dh
	while rem > 0.0 and p.pi < p.path.size():
		var t: Vector2 = p.path[p.pi]
		var dx: float = t.x - p.x
		var dy: float = t.y - p.y
		var d := sqrt(dx * dx + dy * dy)
		if d <= rem:
			p.x = t.x
			p.y = t.y
			p.pi += 1
			rem -= d
		else:
			p.x += dx / d * rem
			p.y += dy / d * rem
			p.fx = dx / d
			rem = 0.0
	return p.pi >= p.path.size()

func _path_to(p: Dictionary, x: float, y: float) -> bool:
	var found = map.paths.find_path(p.x, p.y, x, y)
	p.path = found if found != null else []
	p.pi = 0
	return found != null

func path_to(p: Dictionary, x: float, y: float) -> bool:
	return _path_to(p, x, y)
