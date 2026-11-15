extends RefCounted
## Map-party AI: hunting, fleeing, wandering, resting in settlements and auto-resolved fights between parties (aiParty, vassalIdle, vassalRest, autoFight, stepWorld in src/05_world.js).
## Wars, undead and clan hooks of the browser are separate slices; rulers and sieges are not here yet.
const Rules = preload("res://campaign/world/party_rules.gd")
const Roster = preload("res://campaign/world/party_roster.gd")

const LORD_FULL := 165.0
const VAS_FULL := 70.0
const WW := 5200.0
const WH := 3400.0

var roster: Roster
var player: RefCounted  # PlayerParty: x, y, troops, rel, busy, inside, away

var undead: RefCounted = null  # WorldUndead, optional
var clans: RefCounted = null   # WorldClans, optional: rulers survive lost fights

func _init(r: Roster, p: RefCounted) -> void:
	roster = r
	player = p

func step(dh: float) -> void:
	for p in roster.parties.duplicate():
		if p in roster.parties:
			ai_party(p, dh)
	var list := roster.parties.duplicate()
	for i in list.size():
		var a: Dictionary = list[i]
		if _skip_fight(a) or not (a in roster.parties):
			continue
		for j in range(i + 1, list.size()):
			var b: Dictionary = list[j]
			if _skip_fight(b) or not (b in roster.parties):
				continue
			if Vector2(a.x - b.x, a.y - b.y).length() < 15.0 and Rules.hostile(a, b):
				auto_fight(a, b)
				break

func _skip_fight(p: Dictionary) -> bool:
	return p.hide or p.kind == "camp" or p.get("lock", false) or p.get("fight", false)

func _dist(a, b) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()

func _player_prey() -> bool:
	return not (player.inside or player.away or player.busy != "")

func ai_party(p: Dictionary, dh: float) -> void:
	if p.kind == "camp":
		return
	p.cd -= dh
	if p.get("lock", false) or p.get("fight", false):
		return
	if p.hide:
		_rest_inside(p, dh)
		return
	p.ai -= dh
	if p.ai <= 0.0:
		p.ai = roster.rnd(0.8, 1.6)
		if _think(p):
			return
	if p.state == "hunt":
		_chase(p, dh)
	if p.pi < p.path.size():
		if roster.move_along(p, dh):
			_arrived(p)
	elif p.state == "travel" and p.kind == "caravan":
		var s := roster.map.settlement_by_id(p.sid) if p.sid != null else {}
		if s.is_empty():
			roster.remove(p)
		else:
			roster.path_to(p, s.x, s.y)

## Resting inside a settlement; on leaving, the party tops up its troops there.
func _rest_inside(p: Dictionary, dh: float) -> void:
	p.wait -= dh
	if p.wait > 0.0:
		return
	p.hide = false
	var h := roster.map.settlement_by_id(p.home) if p.home != null else {}
	if not h.is_empty():
		var lord: bool = p.kind == "lord"
		var need := (LORD_FULL if lord else 34.0) * Rules.MK - Rules.troop_count(p.troops)
		if need > 0.0 and h.fac == p.fac:
			var n := mini(ceili(need / Rules.MK), roster.rint(10, 25) if lord else roster.rint(4, 10))
			for a in roster.gen_troops(p.fac, n, 0.6):
				Rules.add_troops(p.troops, a.type, a.n)
	if p.kind == "lord":
		p.state = "idle"

## Decides between hunting, fleeing and idling. Returns true when the party picked a new goal this tick.
func _think(p: Dictionary) -> bool:
	var me := roster.strength_of(p)
	var tgt = null
	var tb := 1e9
	var threat = null
	for o in roster.parties:
		if o == p or o.hide or o.kind == "camp" or not Rules.hostile(p, o):
			continue
		var d := _dist(o, p)
		if d > 260.0:
			continue
		var so := roster.strength_of(o)
		if so < me * (0.9 if p.kind == "bandit" else 0.75):
			if d < tb:
				tb = d
				tgt = o
		elif so > me * 1.2 and d < 190.0:
			threat = o
	if _player_prey() and Rules.hostile_to_player(p, player.rel):
		var d := _dist(player, p)
		if d < 230.0:
			var sp := Rules.strength(player.troops, roster.info) + 6.0
			if sp < me * 0.95:
				if d < tb:
					tgt = {"id": -1, "x": player.x, "y": player.y, "pl": true}
					tb = d
			elif sp > me * 1.25 and d < 180.0:
				threat = player
	if p.get("army", false):
		threat = null
		if tgt != null and tb > 90.0:
			tgt = null
	if threat != null and tgt == null and p.fac != "undead":
		var a := atan2(p.y - threat.y, p.x - threat.x)
		roster.path_to(p, clampf(p.x + cos(a) * 220.0, 60.0, WW - 60.0), clampf(p.y + sin(a) * 220.0, 60.0, WH - 60.0))
		p.state = "flee"
		p.tid = null
		return true
	if tgt != null:
		p.tid = null if tgt.has("pl") else tgt.id
		p.tpl = tgt.has("pl")
		p.state = "hunt"
		roster.path_to(p, tgt.x, tgt.y)
		return true
	if p.state == "hunt" or p.state == "flee":
		p.state = "idle"
		p.tid = null
		p.tpl = false
		p.path = []
	if p.state == "idle" and p.pi >= p.path.size() and not p.get("army", false):
		_idle(p)
	return false

func _idle(p: Dictionary) -> void:
	if p.fac == "undead":
		p.wait -= 1.2
		if p.wait <= 0.0 and undead != null:
			undead.idle(p)
		return
	match p.kind:
		"lord":
			p.wait -= 1.2
			if p.wait <= 0.0:
				var targets := roster.map.settles.filter(func(s): return s.fac == p.fac and s.kind != "camp")
				var ruins: Array = undead.ruins_for(p.fac) if undead != null else []
				if not ruins.is_empty() and roster.rng.randf() < 0.5:
					targets = ruins
				if targets.is_empty():
					p.wait = 5.0
				else:
					var d: Dictionary = roster.pick(targets)
					p.sid = d.id
					p.state = "travel"
					roster.path_to(p, d.x, d.y)
		"vassal":
			p.wait -= 1.2
			if p.wait <= 0.0:
				_vassal_idle(p)
		"bandit":
			var c := roster.map.settlement_by_id(p.home) if p.home != null else {}
			var a := roster.rnd(0.0, TAU)
			var r := roster.rnd(80.0, 340.0)
			var bx: float = c.x if not c.is_empty() else p.x
			var by: float = c.y if not c.is_empty() else p.y
			if not roster.path_to(p, clampf(bx + cos(a) * r, 60.0, WW - 60.0), clampf(by + sin(a) * r, 60.0, WH - 60.0)):
				p.path = []
			p.state = "roam"
		"caravan":
			p.state = "travel"

func _chase(p: Dictionary, dh: float) -> void:
	if p.get("tpl", false):
		if not _player_prey() or _dist(player, p) > 300.0:
			p.state = "idle"
			p.path = []
			p.tpl = false
		else:
			p.rp -= dh
			if p.rp <= 0.0:
				p.rp = 0.7
				roster.path_to(p, player.x, player.y)
	else:
		var t := roster.party_by_id(p.tid)
		if t.is_empty() or t.hide:
			p.state = "idle"
			p.path = []
		else:
			p.rp -= dh
			if p.rp <= 0.0:
				p.rp = 0.7
				roster.path_to(p, t.x, t.y)

func _arrived(p: Dictionary) -> void:
	if p.state == "travel":
		var s := roster.map.settlement_by_id(p.sid) if p.sid != null else {}
		if s.is_empty() or Vector2(s.x - p.x, s.y - p.y).length() >= 40.0:
			return
		if p.get("army", false):
			p.state = "idle"
			p.path = []
			p.pi = 0
			p.arrived = true
			return
		if p.fac == "undead" and undead != null:
			undead.arrive(p, s)
			return
		if s.fac == "undead" and Rules.is_noble(p) and undead != null and not undead.noble_retake(p, s):
			p.state = "idle"
			p.path = []
			p.wait = float(roster.rint(3, 8))
			if Rules.troop_count(p.troops) < 10:
				roster.remove(p)
			return
		if p.kind == "caravan":
			if s.fac != "bandit":
				roster.remove(p)
			return
		if s.fac == "player":
			p.state = "idle"
			p.path = []
			p.wait = float(roster.rint(4, 10))
			return
		if p.kind == "vassal":
			_vassal_rest(p, s)
			return
		p.hide = true
		p.wait = float(roster.rint(5, 20))
		p.home = s.id
		p.x = s.x
		p.y = s.y
		p.state = "idle"
		p.path = []
	elif p.state == "roam":
		p.state = "idle"
		p.wait = float(roster.rint(2, 6)) if p.kind == "vassal" else 0.0

## A vassal without work follows its lord half of the time, otherwise rides around the faction's villages and castles.
func _vassal_idle(p: Dictionary) -> void:
	var lord := roster.party_by_id(p.lid) if p.get("lid") != null else {}
	if lord.is_empty() or lord.fac != p.fac:
		var ls := roster.parties.filter(func(q): return q.kind == "lord" and q.fac == p.fac)
		lord = roster.pick(ls) if not ls.is_empty() else {}
		p.lid = lord.id if not lord.is_empty() else null
	if not lord.is_empty() and roster.rng.randf() < 0.5:
		var a := roster.rnd(0.0, TAU)
		var tx := clampf(lord.x + cos(a) * 45.0, 60.0, WW - 60.0)
		var ty := clampf(lord.y + sin(a) * 45.0 + 20.0, 60.0, WH - 60.0)
		if _dist(lord, p) > 80.0 and roster.path_to(p, tx, ty):
			p.state = "roam"
			return
	var own := roster.map.settles.filter(func(s): return s.fac == p.fac and s.kind != "camp" and s.kind != "town")
	own.sort_custom(func(a, b): return _dist(a, p) < _dist(b, p))
	var near := own.slice(0, 6)
	if near.is_empty():
		p.wait = 5.0
		return
	var d: Dictionary = roster.pick(near)
	p.sid = d.id
	p.state = "travel"
	roster.path_to(p, d.x + roster.rnd(-15, 15), d.y + 24.0)

## At its own settlement a vassal stands by the walls for a few hours and tops up its men.
func _vassal_rest(p: Dictionary, s: Dictionary) -> void:
	p.state = "idle"
	p.path = []
	p.pi = 0
	p.wait = float(roster.rint(3, 8))
	p.home = s.id
	var need := VAS_FULL * Rules.MK - Rules.troop_count(p.troops)
	if need > 0.0 and s.fac == p.fac:
		for a in roster.gen_troops(p.fac, mini(ceili(need / Rules.MK), roster.rint(4, 10)), 0.55):
			Rules.add_troops(p.troops, a.type, a.n)

## Auto-resolves a meeting of two AI parties: the stronger one wins and loses part of its men, the loser disappears.
func auto_fight(a: Dictionary, b: Dictionary) -> void:
	var sa := roster.strength_of(a) * roster.rnd(0.8, 1.25)
	var sb := roster.strength_of(b) * roster.rnd(0.8, 1.25)
	var w: Dictionary = a if sa >= sb else b
	var l: Dictionary = b if w == a else a
	var ratio := minf(sa, sb) / maxf(sa, sb)
	var wl := minf(0.85, ratio * 0.85)
	if w.fac == "undead" and undead != null:
		undead.raise(w, Rules.troop_count(l.troops) * undead.RAISE)
	for s in w.troops.duplicate():
		var dead := 0
		for i in int(s.n):
			if roster.rng.randf() < wl:
				dead += 1
		Rules.remove_troops(w.troops, s.type, dead)
	if l.get("ruler", false) and clans != null and roster.rng.randf() < 0.75:
		for t in l.troops.duplicate():
			Rules.remove_troops(l.troops, t.type, floori(int(t.n) * 0.55))
		clans.ruler_home(l)
	else:
		roster.remove(l)
	if w.troops.is_empty() or Rules.troop_count(w.troops) < 2:
		roster.remove(w)
	w.state = "idle"
	w.path = []
	w.pi = 0
	w.cd = 3.0
	w.gold += 20
