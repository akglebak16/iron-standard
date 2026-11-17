extends RefCounted
## The undead crisis (src/05f_undead.js): between days 40 and 60 one or two bandit lairs become Black Barrows; armies and raids
## of the dead march out, burn villages, storm towns and castles into ruins and raise the fallen. Lords retake their ruins,
## the player destroys barrows. Fields: s.barrow, s.burnt, s.ruinOf, s.ruin, s.name0; state: crisis {day, on, done, src, left,
## waves}.
## Since stage 2c (docs/modules/ai/DESIGN.md §5.5) every barrow sends one wave, steered by undead_director.gd: the armies
## gather at a rally point short of a living town or castle and storm it together, raids burn the villages ahead.
## crisis.waves: str(barrow id) -> {tid: target id or -1, mode: gather|attack, t0: hour the mode began, tt: hour the target
## was chosen or last reconsidered, tw: hour the first army reached the walls or -1, rx, ry: rally point, sc: score of the
## target, bad: ids of targets the wave cannot reach}. Saves made before stage 2c have no waves: they are chosen anew.
const Rules = preload("res://core/campaign/world/party_rules.gd")
const Roster = preload("res://core/campaign/world/party_roster.gd")
const WorldWars = preload("res://core/campaign/world/world_wars.gd")
const SettlementRecruits = preload("res://core/campaign/rules/settlement_recruits.gd")
const Director = preload("res://core/campaign/world/undead_director.gd")
const Config = preload("res://core/campaign/config.gd")

const MK := 2.0
const ARMY_MIN := 350
const ARMY_MAX := 500
const RAID_MIN := 40
const RAID_MAX := 80
const MAX_ARMY := 700
const RAISE := 0.5
const ARMIES_PER_SRC := 6
const ARMIES_AT_ONCE := 3
const RAIDS_AT_ONCE := 3
const SPAWN_EVERY := 3
const BURN_H := 24 * 6
const RUIN_H := 24 * 10
const RAID_MK := 1.0 + (MK - 1.0) * 0.25
const WW := 5200.0
const WH := 3400.0
const MIX := [["z1", 40], ["s1", 28], ["s1a", 15], ["s2", 11], ["s2c", 5], ["s3", 1]]

signal announced(text: String)
signal settlement_changed(settlement: Dictionary)
## Decisions of the director as they happen, for observers (the campaign simulator):
## {what: target|attack|gather|storm, src, tid, ...}.
signal wave(event: Dictionary)

var roster: Roster
var wars: WorldWars
var crisis: Dictionary = {}
var day := 1
var director := Director.new()

func _init(party_roster: Roster, world_wars: WorldWars) -> void:
	roster = party_roster
	wars = world_wars
	director.strength = roster.strength_of
	director.defence = storm_defence
	director.passable = func(c: Vector2) -> bool: return roster.map.paths.passable_type(roster.map.paths.terr_at(c.x, c.y))
	director.width = WW
	director.height = WH

## Living armies around a point as the director sees them: (x, y, faction) -> strength (WorldState: threat map, ADR-023).
func set_field(f: Callable) -> void:
	director.field = f

## Breaks the links to the world so a disposed campaign is freed.
func dispose() -> void:
	director = Director.new()

func _rng() -> RandomNumberGenerator:
	return roster.rng

static func is_undead(p: Dictionary) -> bool:
	return not p.is_empty() and p.get("fac") == "undead"

func gen(n: int, elite: int) -> Array:
	var counts := {}
	var total := 0
	var w: Array = []
	for x in MIX:
		var v: int = x[1] + (elite * 6 if x[0] == "s2" else (elite * 3 if x[0] == "s3" else 0))
		w.append([x[0], v])
		total += v
	for i in n:
		var r := _rng().randf() * total
		for x in w:
			r -= x[1]
			if r <= 0.0:
				counts[x[0]] = int(counts.get(x[0], 0)) + 1
				break
	var out: Array = []
	for k in counts:
		out.append({"type": k, "n": counts[k]})
	return out

func raise(p: Dictionary, n: float) -> int:
	var k := mini(roundi(n), roundi(MAX_ARMY * MK) - Rules.troop_count(p.troops))
	if k > 0:
		Rules.add_troops(p.troops, "z1", k)
	return maxi(0, k)

func init() -> Dictionary:
	if crisis.is_empty():
		crisis = {"day": day + roster.rint(5, 15) if day > 35 else roster.rint(40, 60), "on": false, "done": false, "src": [], "left": {}}
	return crisis

func _dist(a: Dictionary, b: Dictionary) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()

## Once a day.
func day_tick() -> void:
	var c := init()
	if c.done:
		return
	if not c.on:
		if day >= int(c.day):
			start()
		return
	if day % SPAWN_EVERY == 0:
		for id in c.src:
			var s: Dictionary = roster.map.settlement_by_id(int(id))
			if not s.is_empty() and s.get("barrow", false):
				spawn(s, false)
	var alive := false
	for id in c.src:
		if roster.map.settlement_by_id(int(id)).get("barrow", false):
			alive = true
	var any := roster.parties.any(func(p): return is_undead(p) and p.kind != "camp")
	if not alive and not any:
		c.on = false
		c.done = true
		announced.emit("Нашествие мёртвых отбито! Курганы разрушены, армии нежити истреблены.")

func start() -> void:
	var c := crisis
	var camps: Array = roster.map.settles.filter(func(s): return s.kind == "camp")
	var src: Array = []
	for i in 2:
		if camps.is_empty():
			break
		var best: Dictionary = {}
		var bd := -1.0
		for k in 12:
			var cand: Dictionary = roster.pick(camps)
			if cand in src:
				continue
			var d := _rng().randf()
			if not src.is_empty():
				d = 1e9
				for o in src:
					d = minf(d, _dist(o, cand))
			if d > bd:
				bd = d
				best = cand
		if not best.is_empty():
			src.append(best)
	c.on = true
	c.src = []
	c.left = {}
	for s in src:
		c.src.append(s.id)
		if s.get("camp") != null:
			var old := roster.party_by_id(s.camp)
			if not old.is_empty():
				roster.remove(old)
		s.barrow = true
		s.fac = "undead"
		s.cleared = false
		s.name0 = s.get("name0", s.name)
		s.name = "Чёрный курган"
		c.left[str(s.id)] = ARMIES_PER_SRC
		var camp := roster.make_party("camp", "undead", "Чёрный курган", s.x, s.y, gen(roundi(roster.rint(110, 140) * MK), 1), {"home": s.id, "hide": false})
		s.camp = camp.id
		spawn(s, true)
		settlement_changed.emit(s)
	var where: Array = []
	for s in src:
		var towns: Array = roster.map.settles.filter(func(x): return x.kind == "town")
		towns.sort_custom(func(a, b): return _dist(a, s) < _dist(b, s))
		if not towns.is_empty():
			where.append("у " + towns[0].name)
	announced.emit("Мёртвые восстали! Из Чёрных курганов %s идут армии нежити. Они жгут деревни и берут замки. Разрушь курганы, чтобы остановить нашествие." % " и ".join(where))

func spawn(s: Dictionary, first: bool) -> void:
	var c := crisis
	var key := str(s.id)
	var mine := roster.parties.filter(func(p): return is_undead(p) and p.get("src") == s.id)
	var armies := mine.filter(func(p): return p.kind == "dead").size()
	var raids := mine.filter(func(p): return p.kind == "raid").size()
	var made := 0
	var a := armies
	while a < ARMIES_AT_ONCE and int(c.left.get(key, 0)) > 0:
		c.left[key] = int(c.left[key]) - 1
		made += 1
		var p := roster.make_party("dead", "undead", "Некромант " + roster.unit_name("undead"), s.x + roster.rnd(-40, 40), s.y + 26 + roster.rnd(-10, 20),
			gen(roundi(roster.rint(ARMY_MIN, ARMY_MAX) * MK), 0), {"home": s.id, "src": s.id})
		p.wait = float(a) if first else float(roster.rint(0, 4))
		a += 1
	if made > 0 and not first:
		announced.emit("Из Чёрного кургана вышли новые армии мертвецов: %d." % made if made > 1 else "Из Чёрного кургана вышла новая армия мертвецов.")
	var i := raids
	while i < RAIDS_AT_ONCE and (i < 2 if first else i < raids + 1):
		var p := roster.make_party("raid", "undead", "Мертвецы", s.x + roster.rnd(-30, 30), s.y + roster.rnd(10, 40), gen(roundi(roster.rint(RAID_MIN, RAID_MAX) * RAID_MK), 0), {"home": s.id, "src": s.id})
		p.wait = float(roster.rint(0, 6))
		i += 1

## An undead party with nothing to do picks a settlement to burn or storm.
func idle(p: Dictionary) -> void:
	var army: bool = p.kind == "dead"
	var radius := 1100.0 if army else 600.0
	var c: Array = roster.map.settles.filter(func(s): return s.kind != "camp" and s.fac != "undead" and not (s.kind == "village" and int(s.get("burnt", 0)) > 0) and _dist(s, p) < radius)
	if army:
		var big := c.filter(func(s): return s.kind != "village")
		if not big.is_empty() and _rng().randf() < 0.55:
			c = big
	else:
		c = c.filter(func(s): return s.kind == "village")
	c.sort_custom(func(a, b): return _dist(a, p) < _dist(b, p))
	if not c.is_empty():
		var d: Dictionary = roster.pick(c.slice(0, 4))
		p.sid = d.id
		p.state = "travel"
		if not roster.path_to(p, d.x, d.y + 20):
			p.state = "idle"
			p.wait = 3.0
	else:
		var ang := roster.rnd(0.0, TAU)
		roster.path_to(p, clampf(p.x + cos(ang) * 300.0, 60.0, WW - 60.0), clampf(p.y + sin(ang) * 300.0, 60.0, WH - 60.0))
		p.state = "roam"

func _cut(list: Array, share: float) -> void:
	for t in list.duplicate():
		Rules.remove_troops(list, t.type, roundi(int(t.n) * share))

## The dead reach a settlement: a village burns, a castle or a town is stormed by calculation. An army of a wave that
## reached the target of its attack waits at the walls for the rest; the director storms with all of them (wave_tick).
func arrive(p: Dictionary, s: Dictionary) -> void:
	p.state = "idle"
	p.path = []
	p.pi = 0
	p.wait = float(roster.rint(1, 4))
	if s.fac == "undead":
		return
	if s.kind == "village":
		s.burnt = BURN_H
		s.recruits = []
		var k := raise(p, roster.rint(4, 10))
		announced.emit("Нежить сожгла деревню %s%s." % [s.name, (" и подняла %d мертвецов" % k) if k > 0 else ""])
		settlement_changed.emit(s)
		return
	var w := _wave_of(p)
	if p.kind == "dead" and not w.is_empty() and int(w.tid) == int(s.id) and String(w.mode) == "attack":
		p.wait = Config.UNDEAD_WALL_WAIT
		if int(w.tw) < 0:
			w.tw = wars.now_h()
		return
	storm(s, [p])

## Lords and vassals of the settlement's faction resting inside it: they hold the walls with the garrison.
func _defenders(s: Dictionary) -> Array:
	return roster.parties.filter(func(q): return q.hide and q.home == s.id and q.fac == s.fac and Rules.is_noble(q))

## What a storm of `s` has to beat before chance: garrison and lords inside, times the walls. Spends no RNG: a garrison
## never raised yet counts as UNDEAD_UNKNOWN_GARRISON.
func storm_defence(s: Dictionary) -> float:
	var g: Variant = s.get("gar")
	var ds: float = (Rules.strength(g, roster.info) if g is Array else Config.UNDEAD_UNKNOWN_GARRISON) + 4.0
	for q in _defenders(s):
		ds += roster.strength_of(q)
	return ds * Config.UNDEAD_STORM_DEFENCE

## Armies of the dead storm a town or castle together. On success it becomes ruins of the dead: lords inside fall, the
## armies leave a share of their men as the garrison and raise the fallen defenders. True when it fell.
func storm(s: Dictionary, armies: Array) -> bool:
	var g := wars.garrison_of(s)
	var lords := _defenders(s)
	var def0 := Rules.troop_count(g)
	var ds := Rules.strength(g, roster.info) + 4.0
	for q in lords:
		def0 += Rules.troop_count(q.troops)
		ds += roster.strength_of(q)
	var power := 0.0
	for p in armies:
		power += roster.strength_of(p)
	var att := power * roster.rnd(0.8, 1.2)
	var def := ds * Config.UNDEAD_STORM_DEFENCE * roster.rnd(0.8, 1.2)
	var r := minf(att, def) / maxf(att, def)
	var won := att > def
	if won:
		for p in armies:
			_cut(p.troops, r * 0.55)
		var names: Array = []
		for q in lords:
			names.append(q.name)
			roster.remove(q)
		var was: String = s.fac
		s.cult = String(s.get("cult", was)) if String(s.get("cult", was)) in Rules.REAL_FACTIONS else "emp"
		s.ruinOf = String(s.get("ruinOf", s.cult)) if was == "player" else was
		s.fac = "undead"
		s.owner = null
		s.board = []
		s.recruits = []
		s.ruin = 0
		s.erase("siege")
		var total := 0
		for p in armies:
			total += Rules.troop_count(p.troops)
		total = maxi(1, total)
		var gn := maxi(25, roundi(total * 0.2))
		for p in armies:
			for t in p.troops.duplicate():
				Rules.remove_troops(p.troops, t.type, roundi(int(t.n) * float(gn) / total))
		s.gar = gen(gn, 0)
		Rules.add_troops(s.gar, "z1", roundi(def0 * RAISE * 0.5))
		for p in armies:
			raise(p, def0 * RAISE * 0.5 / armies.size())
		var who := ""
		if not names.is_empty():
			who = ", %s погиб%s при обороне" % [", ".join(names), "ли" if names.size() > 1 else ""]
		announced.emit("%s %s пал под натиском мертвецов%s. Теперь это руины нежити." % ["Город" if s.kind == "town" else "Замок", s.name, who])
		settlement_changed.emit(s)
	else:
		_cut(g, r * 0.4)
		for p in armies:
			_cut(p.troops, 0.35 + r * 0.4)
		announced.emit("Гарнизон %s отбил натиск мертвецов." % s.name)
	for p in armies:
		p.state = "idle"
		p.path = []
		p.pi = 0
		p.wait = maxf(float(p.get("wait", 0.0)), 1.0)
		if Rules.troop_count(p.troops) < 8:
			roster.remove(p)
	return won

## A lord or vassal of the old faction at the ruins storms them by calculation. True when retaken.
func noble_retake(p: Dictionary, s: Dictionary) -> bool:
	return retake([p], s, String(p.name))

## A host of the old faction (a campaign, stage 2c) storms its ruins together. True when retaken.
func host_retake(host: Array, s: Dictionary) -> bool:
	if host.is_empty():
		return false
	return retake(host, s, "Войско %s" % String(roster.factions.get_faction(String(host[0].fac)).get("gen", host[0].fac)))

func retake(host: Array, s: Dictionary, who: String) -> bool:
	var g := wars.garrison_of(s)
	var power := 0.0
	for p in host:
		power += roster.strength_of(p)
	var att := power * roster.rnd(0.8, 1.2)
	var def := (Rules.strength(g, roster.info) + 4.0) * Config.OP_RUIN_DEFENCE * roster.rnd(0.8, 1.2)
	var r := minf(att, def) / maxf(att, def)
	if att > def:
		for p in host:
			_cut(p.troops, r * 0.5)
		s.fac = host[0].fac
		s.ruin = RUIN_H
		s.gar = roster.gen_troops(host[0].fac, 20, 0.5)
		s.recruits = []
		announced.emit("%s отбил%s %s у мертвецов." % [who, "о" if host.size() > 1 or who.begins_with("Войско") else "", s.name])
		settlement_changed.emit(s)
		return true
	_cut(g, r * 0.4)
	for p in host:
		_cut(p.troops, 0.3 + r * 0.4)
	return false

func ruins_for(f: String) -> Array:
	return roster.map.settles.filter(func(s): return s.fac == "undead" and s.kind != "camp" and s.get("ruinOf") == f)

# ---------- the director of the invasion (stage 2c) ----------

## Armies of the dead on the map by barrow: str(src) -> [parties], in roster order.
func _armies() -> Dictionary:
	var out := {}
	for p in roster.parties:
		if p.kind != "dead" or p.fac != "undead" or p.get("src") == null:
			continue
		var key := str(int(p.src))
		if not out.has(key):
			out[key] = []
		out[key].append(p)
	return out

## Hourly while the crisis is on: every wave keeps or changes its target, gathers or attacks, and its armies at the
## walls storm together. Waves without armies are forgotten; new armies of their barrow start a new one.
func wave_tick() -> void:
	if not crisis.get("on", false):
		return
	if not crisis.get("waves") is Dictionary:
		crisis.waves = {}
	var by_src := _armies()
	for key in crisis.waves.keys():
		if not by_src.has(key):
			crisis.waves.erase(key)
	for key in by_src:
		_wave_tick(String(key), by_src[key])

func _new_wave(now: int) -> Dictionary:
	return {"tid": -1, "mode": "gather", "t0": now, "tt": now, "tw": -1, "rx": 0.0, "ry": 0.0, "sc": 0.0, "bad": []}

func _wave_tick(key: String, armies: Array) -> void:
	var now := wars.now_h()
	if not crisis.waves.has(key):
		crisis.waves[key] = _new_wave(now)
	var w: Dictionary = crisis.waves[key]
	var free := armies.filter(func(p): return not p.get("fight", false))
	var t := roster.map.settlement_by_id(int(w.tid)) if int(w.tid) >= 0 else {}
	if t.is_empty() or not Director.is_target(t):
		t = _retarget(key, w, armies, now, true)
	elif String(w.mode) == "gather" and now - int(w.tt) >= Config.UNDEAD_RETARGET_HOURS:
		t = _retarget(key, w, armies, now, false)
	if t.is_empty():
		return
	var m := director.mode(String(w.mode), armies, Vector2(float(w.rx), float(w.ry)), t, float(now - int(w.t0)))
	if m != String(w.mode):
		w.mode = m
		w.t0 = now
		w.tw = -1
		wave.emit({"what": m, "src": int(key), "tid": int(t.id), "power": director.total(armies), "need": director.storm_defence(t)})
	if m != "attack":
		return
	var here := Director.at_walls(free, t)
	if here.is_empty():
		return
	if int(w.tw) < 0:
		w.tw = now
	if not director.storm_ready(armies, t, float(now - int(w.tw))):
		for p in here:  # they wait at the walls for the rest of the wave
			if p.pi >= p.path.size():
				p.wait = maxf(float(p.get("wait", 0.0)), Config.UNDEAD_WALL_WAIT)
		return
	var won := storm(t, here)
	wave.emit({"what": "storm", "src": int(key), "tid": int(t.id), "armies": here.size(), "won": won})
	w.mode = "gather"
	w.t0 = now
	w.tw = -1
	if won:
		_retarget(key, w, _armies().get(key, []), now, true)

## Picks the wave's target: the best one (undead_director.gd), a reachable one; `force` when the old one is no target
## any more, else it is replaced only by a clearly better one. Returns the target or {}.
func _retarget(key: String, w: Dictionary, armies: Array, now: int, force: bool) -> Dictionary:
	var barrow := roster.map.settlement_by_id(int(key))
	var from := Director.centre(armies, barrow)
	var power := director.total(armies)
	var cur := roster.map.settlement_by_id(int(w.tid)) if int(w.tid) >= 0 else {}
	w.tt = now
	for i in 3:
		var cand := director.best_target(from, power, roster.map.settles, w.bad)
		if cand.is_empty():
			w.tid = -1
			return {}
		if not force and not Director.switch(cur, director.score(cur, from, power, roster.map.settles), cand):
			return cur
		var s: Dictionary = cand.s
		if roster.map.paths.find_path(from.x, from.y, float(s.x), float(s.y)) == null:
			w.bad.append(int(s.id))  # across the sea: the dead do not go there
			continue
		var rally := director.rally_point(from, s)
		w.tid = int(s.id)
		w.sc = float(cand.score)
		w.rx = rally.x
		w.ry = rally.y
		w.mode = "gather"
		w.t0 = now
		w.tw = -1
		announced.emit("Армии мертвецов идут на %s %s." % ["город" if s.kind == "town" else "замок", s.name])
		wave.emit({"what": "target", "src": int(key), "tid": int(s.id), "score": float(cand.score), "dist": from.distance_to(Vector2(s.x, s.y)), "kind": String(s.kind), "fac": String(s.fac)})
		return s
	return cur if Director.is_target(cur) else {}

func _wave_of(p: Dictionary) -> Dictionary:
	if p.get("src") == null or not crisis.get("waves") is Dictionary:
		return {}
	return crisis.waves.get(str(int(p.src)), {})

## The wave of an army as its goals see it: {mode, tid, x, y (target), rx, ry (rally point)}; {} without one.
func wave_of(p: Dictionary) -> Dictionary:
	if p.get("kind") != "dead":
		return {}
	var w := _wave_of(p)
	if w.is_empty() or int(w.tid) < 0:
		return {}
	var t := roster.map.settlement_by_id(int(w.tid))
	if t.is_empty():
		return {}
	return {"mode": String(w.mode), "tid": int(w.tid), "x": float(t.x), "y": float(t.y), "rx": float(w.rx), "ry": float(w.ry)}

## Where the dead of p's barrow strike: the target of its wave, else the barrow itself. {x, y}; {} without a barrow.
func front_of(p: Dictionary) -> Dictionary:
	var w := _wave_of(p)
	if not w.is_empty() and int(w.tid) >= 0:
		var t := roster.map.settlement_by_id(int(w.tid))
		if not t.is_empty():
			return {"x": float(t.x), "y": float(t.y)}
	var b := roster.map.settlement_by_id(int(p.src)) if p.get("src") != null else {}
	if b.is_empty() and p.get("home") != null:
		b = roster.map.settlement_by_id(int(p.home))
	return {} if b.is_empty() else {"x": float(b.x), "y": float(b.y)}

## Towns and castles of the living the waves are going for: id -> mode (gather|attack). Their factions defend them.
func doomed() -> Dictionary:
	var out := {}
	if not crisis.get("on", false) or not crisis.get("waves") is Dictionary:
		return out
	for key in crisis.waves:
		var w: Dictionary = crisis.waves[key]
		if int(w.tid) >= 0:
			out[int(w.tid)] = String(w.mode)
	return out

## The player destroyed a barrow: the lair becomes an ordinary one again.
func barrow_destroyed(p, c: Dictionary) -> void:
	c.barrow = false
	c.fac = "bandit"
	c.name = c.get("name0", c.name)
	if crisis.has("left"):
		crisis.left[str(c.id)] = 0
	for f in Rules.REAL_FACTIONS:
		p.rel[f] = minf(100.0, float(p.rel.get(f, 0)) + 5.0)
	announced.emit("Чёрный курган разрушен! Отсюда больше не выйдут мертвецы. Все фракции благодарны тебе (+5 к отношениям).")
	settlement_changed.emit(c)

## Hourly: villages are rebuilt, ruins recover.
func hour_tick() -> void:
	for s in roster.map.settles:
		if int(s.get("burnt", 0)) > 0:
			s.burnt = int(s.burnt) - 1
			if s.burnt <= 0:
				s.burnt = 0
				SettlementRecruits.refresh(s, roster.catalog, roster.rng)
		if int(s.get("ruin", 0)) > 0 and s.fac != "undead":
			s.ruin = int(s.ruin) - 1
