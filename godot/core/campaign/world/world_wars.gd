extends RefCounted
## Wars between states: declaring and ending them, lords' campaigns, sieges and captures of settlements, garrisons
## and the fall of a state (src/05g_war.js, garrison parts of src/05_world.js). Clans, rulers and oaths are separate modules.
## Since stage 2b (docs/modules/ai/DESIGN.md §5.3) campaigns are operations: a marshal leads the host, part of the
## lords stays home, relief of an own besieged settlement is a defensive operation (one of each kind per faction), a
## campaign is called off when its host is spent or home needs it, and the player's holdings are besieged like any
## other settlement. campaign_ops.gd decides, this file carries it out.
## Since stage 2c (DESIGN.md §5.5) the living answer the undead invasion within these operations: a town or castle an
## undead wave goes for keeps a defender home, and own ruins held by the dead are targets of a campaign even in peace,
## preferred to enemy towns; the host storms them together (WorldUndead.host_retake) instead of a siege.
const Rules = preload("res://core/campaign/world/party_rules.gd")
const Roster = preload("res://core/campaign/world/party_roster.gd")
const WorldMap = preload("res://core/campaign/world/world_map.gd")
const SettlementRecruits = preload("res://core/campaign/rules/settlement_recruits.gd")
const CampaignOps = preload("res://core/campaign/world/campaign_ops.gd")
const Config = preload("res://core/campaign/config.gd")

signal announced(text: String)
signal settlement_changed(settlement: Dictionary)
## News about a holding of the player (a siege of it, its capture or relief); `good` tells the journal its colour.
signal holding_news(settlement: Dictionary, text: String, good: bool)
## Operations as they happen, for observers (the campaign simulator): {what: start|retreat|relief, f, ...}.
signal operation(event: Dictionary)

const MK := 2.0
const GAR_CAP := {"town": 130.0, "castle": 210.0}
const GAR_WAGE := 0.5
const DEF_SIEGE_STONES := {"town": 1.55, "castle": 1.7}

var map: WorldMap
var roster: Roster
var wars: Dictionary = {}     # "a|b" -> {since}
## faction -> offensive campaign {tid, gid, state, t0, t1, t2, army: [ids], marshal: id, s0: strength at the muster,
## keep: [ids of lords left home]}; marshal, s0 and keep are absent in saves made before stage 2b.
var campaigns: Dictionary = {}
var day := 1
var hour := 8
var _tally := 0
var clans: RefCounted = null  # WorldClans, optional: rulers, oaths and clan loyalty
var player: RefCounted = null # PlayerParty, optional: factions hostile to the player besiege his holdings
var vassals: RefCounted = null # WorldVassals, optional: a retinue by its fief helps hold a siege of it
var threat: Callable = Callable() # (x, y, faction) -> enemy strength there on the threat map (WorldState), optional
var doomed: Callable = Callable() # () -> {settlement id: mode}: targets of the undead waves (WorldUndead), optional
var retake: Callable = Callable() # (host, settlement) -> bool: a host storms its ruins held by the dead (WorldUndead), optional
var ops := CampaignOps.new()
var slicer: RefCounted = null  # SliceBudget of the world, optional: war_hour() may rest between factions and routes (awaited)

func _init(world_map: WorldMap, party_roster: Roster) -> void:
	map = world_map
	roster = party_roster
	ops.strength = roster.strength_of

func now_h() -> int:
	return day * 24 + hour

func start() -> void:
	for a in Rules.WAR:
		for b in Rules.WAR[a]:
			if a != "bandit" and b != "bandit":
				wars[Rules.war_key(a, b)] = {"since": 1}
	roster.diplomatic_wars = wars

func hold_of(f: String) -> Dictionary:
	var t := 0
	var c := 0
	var v := 0
	for s in map.settles:
		if s.fac == f:
			if s.kind == "town":
				t += 1
			elif s.kind == "castle":
				c += 1
			elif s.kind == "village":
				v += 1
	return {"t": t, "c": c, "v": v, "all": t + c + v, "core": t + c}

func alive(f: String) -> bool:
	return hold_of(f).core > 0

func factions_alive() -> Array:
	return Rules.REAL_FACTIONS.filter(func(f): return alive(f))

func power(f: String) -> float:
	var s := 0.0
	for p in roster.parties:
		if p.fac == f and Rules.is_noble(p):
			s += roster.strength_of(p)
	var h := hold_of(f)
	return s + h.t * 90 + h.c * 70 + h.v * 12

func at_war(a: String, b: String) -> bool:
	return wars.has(Rules.war_key(a, b))

func _name(f: String) -> String:
	return roster.factions.get_faction(f).name

func _say(text: String) -> void:
	announced.emit(text)

func borders(a: String, b: String) -> bool:
	for s in map.settles:
		if s.fac == a and s.kind != "village":
			for t in map.settles:
				if t.fac == b and Vector2(s.x - t.x, s.y - t.y).length() < 900.0:
					return true
	return false

# ---------- garrisons ----------

func garrison_of(s: Dictionary) -> Array:
	if not s.has("gar") or s.gar == null:
		if s.kind == "town" or s.kind == "castle":
			var n := roster.rint(85, 120) if s.kind == "town" else roster.rint(130, 175)
			var cult := String(s.get("cult", s.fac))
			s["gar"] = roster.gen_troops(cult if cult in Rules.REAL_FACTIONS else "emp", n, 0.75 if s.kind == "castle" else 0.62)
		else:
			s["gar"] = []
	return s.gar

func gar_cap(s: Dictionary) -> float:
	return GAR_CAP.get(s.kind, 0.0) * MK

func siege_def(s: Dictionary) -> float:
	var h := hold_of(s.fac)
	var retinue := _retinue(s)
	var extra := roster.strength_of(retinue) if not retinue.is_empty() else 0.0
	return (Rules.strength(garrison_of(s), roster.info) + 4.0 + extra) * (1.8 + (0.8 if h.core <= 3 else (0.35 if h.core <= 5 else 0.0))) * (1.0 - 0.4 * float(s.get("dmg", 0.0)))

## The retinue of the player's vassal standing by its fief (WorldVassals.defence_of): it holds the walls with the
## garrison and shares its losses, as it did against the storms before stage 2b. {} for every other settlement.
func _retinue(s: Dictionary) -> Dictionary:
	if vassals == null or s.get("fac") != Config.PLAYER_FACTION:
		return {}
	return vassals.defence_of(s)

## Daily: faction garrisons refill toward 80% of their cap.
func garrison_day() -> void:
	for s in map.settles:
		if s.kind != "town" and s.kind != "castle":
			continue
		var g := garrison_of(s)
		var n := Rules.troop_count(g)
		if s.fac in Rules.REAL_FACTIONS and n < gar_cap(s) * 0.8:
			for a in roster.gen_troops(s.fac, mini(6, roundi(gar_cap(s) * 0.8) - n), 0.6):
				Rules.add_troops(g, a.type, a.n)

# ---------- diplomacy: once a day ----------

func war_day() -> void:
	var alive_list := factions_alive()
	for k in wars.keys():
		var parts: PackedStringArray = k.split("|")
		if not parts[0] in alive_list or not parts[1] in alive_list:
			wars.erase(k)
	var count := func(f: String) -> int:
		var n := 0
		for k in wars:
			if f in k.split("|"):
				n += 1
		return n
	for i in alive_list.size():
		for j in range(i + 1, alive_list.size()):
			var a: String = alive_list[i]
			var b: String = alive_list[j]
			var k := Rules.war_key(a, b)
			var pa := power(a)
			var pb := power(b)
			var r := maxf(pa, pb) / maxf(1.0, minf(pa, pb))
			if wars.has(k):
				var d: int = day - int(wars[k].since)
				if d < 10:
					continue
				var weak := 3.0 if minf(hold_of(a).all, hold_of(b).all) < 9 else 1.0
				var peace_k: float = clans.ruler_peace(a, b) if clans != null else 1.0
				if roster.rng.randf() < clampf(0.012 + d * 0.0005, 0.0, 0.07) * (0.35 if r > 1.7 else 1.0) * weak * peace_k:
					wars.erase(k)
					_say("%s и %s заключили мир." % [_name(a), _name(b)])
			else:
				if count.call(a) >= 3 or count.call(b) >= 3 or not borders(a, b):
					continue
				if clans != null and (clans.kingless(a) or clans.kingless(b)):
					continue
				var lone := (3.0 if count.call(a) == 0 else 1.0) * (2.0 if count.call(b) == 0 else 1.0)
				var top := (pa if pa > pb else pb) / maxf(1.0, (pa + pb) / 2.0)
				var war_k: float = clans.ruler_war(a, b) if clans != null else 1.0
				if roster.rng.randf() < 0.005 * lone * top * war_k:
					wars[k] = {"since": day}
					_say("%s объявляет войну: %s." % [_name(a if pa > pb else b), _name(b if pa > pb else a)])
	_tally += 1
	if _tally % 10 == 0:
		var best := ""
		var best_n := 0
		var total := map.settles.filter(func(s): return s.kind != "camp").size()
		for f in alive_list:
			var n: int = hold_of(f).all
			if n > best_n:
				best_n = n
				best = f
		if best_n > total * 0.5:
			_say("%s правит больше половины земель (%d из %d)." % [_name(best), best_n, total])
	garrison_day()

# ---------- campaigns: muster, march, siege ----------

func _lords_of(f: String) -> Array:
	return roster.parties.filter(func(p): return Rules.is_noble(p) and p.fac == f and not p.get("lock", false) and not p.get("ruler", false))

func war_hour() -> void:
	_sg_hour()
	if hour % 2 == 0:
		for f in factions_alive():
			await _campaign(f)
			await _rest_point()
		for s in map.settles:
			if s.get("siege") != null:
				_siege_tick(s)

## A point where a sliced world step may rest until the next frame (slice_budget.gd).
func _rest_point() -> void:
	if slicer != null and slicer.due():
		await slicer.next_frame()

func _party_ids(c: Dictionary) -> Array:
	return c.army.map(func(id): return roster.party_by_id(id)).filter(func(p): return not p.is_empty() and p.get("army", false))

## Factions and pseudo-factions whose settlements `f` may besiege: states at war with it, and the player's holdings
## while the player is its enemy (relations below -20).
func _foes_of(f: String) -> Array:
	var out := factions_alive().filter(func(e): return e != f and at_war(f, e))
	if hostile_to_player(f):
		out.append(Config.PLAYER_FACTION)
	return out

func hostile_to_player(f: String) -> bool:
	return player != null and f in Rules.REAL_FACTIONS and float(player.rel.get(f, 0)) < Config.HOSTILE_BELOW

## Enemy strength around (x, y) on the threat map as faction f feels it; 0 without a threat map.
func _threat_at(x: float, y: float, f: String) -> float:
	return float(threat.call(x, y, f)) if threat.is_valid() else 0.0

## Own towns and castles held by the dead: campaign targets once the dead can be stormed (retake is wired).
func _own_ruins(f: String) -> Array:
	return CampaignOps.own_ruins(f, map.settles) if retake.is_valid() else []

static func _is_own_ruin(f: String, t: Dictionary) -> bool:
	return t.get("fac") == Config.UNDEAD_FACTION and String(t.get("ruinOf", "")) == f

## Strength a host needs to retake ruins: the dead garrison behind the walls (WorldUndead.retake before chance).
func _ruin_def(t: Dictionary) -> float:
	return (Rules.strength(garrison_of(t), roster.info) + 4.0) * Config.OP_RUIN_DEFENCE

func _doomed() -> Dictionary:
	return doomed.call() if doomed.is_valid() else {}

func _campaign(f: String) -> void:
	var enemies := _foes_of(f)
	var c: Variant = campaigns.get(f)
	if c != null:
		await _run_campaign(f, c, enemies)
		return
	if hour % 6 != 0:
		return
	var ruins := _own_ruins(f)
	if enemies.is_empty() and ruins.is_empty():
		return
	if clans != null and clans.kingless(f):
		return
	var lords := _lords_of(f).filter(func(p): return Rules.troop_count(p.troops) >= 20 * MK)
	var total := ops.total(lords)
	if lords.size() < 2 and total < 220.0 * MK:
		return
	var mine := map.settles.filter(func(s): return s.fac == f and s.kind != "camp")
	if mine.is_empty():
		return
	if mine.any(func(s): return s.get("siege") != null and String(s.siege.get("f", "")) != f and not _covered(s)):
		return  # home is besieged and the lords at home cannot relieve it: no new campaign until it is relieved or lost
	# part of the lords stays home: one by each threatened or besieged own town or castle, one while at war
	var free := lords.filter(func(p): return not p.get("fight", false) and not p.get("army", false) and p.get("relief") == null and _ready(p))
	var plan := ops.split(free, ops.alerts(f, map.settles, _threat_at, _doomed()))
	var army: Array = plan.army
	total = ops.total(army)
	if army.is_empty() or (army.size() < 2 and total < 220.0 * MK):
		return
	var best := {}
	var best_ms := {}
	var best_score := 1e9
	var ruin_ids := {}
	for t in ruins:
		ruin_ids[t.id] = true
	for t in map.settles:
		var ruin := ruin_ids.has(t.id)
		if not ruin and (not t.fac in enemies or t.kind == "camp" or t.kind == "village" or t.get("siege") != null):
			continue
		var def := _ruin_def(t) if ruin else siege_def(t)
		if total < def * 0.9:
			continue
		var md := 1e9
		var ms := {}
		for s in mine:
			var d := Vector2(s.x - t.x, s.y - t.y).length()
			if d < md:
				md = d
				ms = s
		var score := md + def * 0.6 + roster.rnd(0.0, 120.0) - (Config.OP_RUIN_PRIORITY if ruin else 0.0)
		if score < best_score:
			best_score = score
			best = t
			best_ms = ms
	if best.is_empty():
		return
	var marshal: Dictionary = plan.marshal
	campaigns[f] = {"tid": best.id, "gid": best_ms.id, "state": "muster", "t0": now_h(), "army": army.map(func(p): return p.id),
		"marshal": marshal.id, "s0": total, "keep": plan.keep.map(func(p): return p.id)}
	for p in army:
		p.army = true
		p.arrived = false
		p.hide = false
		p.wait = 0.0
	await _rest_point()
	await _go_co(marshal, best_ms)
	for p in army:
		if p != marshal:
			await _rest_point()
			await _follow(p, marshal)
	var ruin := ruin_ids.has(best.id)
	if best.fac == Config.PLAYER_FACTION:
		holding_news.emit(best, "%s созывает войска: поход на твой %s %s, ведёт %s." % [_name(f), _kind_name(best), best.name, marshal.name], false)
	if ruin:
		_say("%s созывает войска: отбить у мертвецов %s, ведёт %s." % [_name(f), best.name, marshal.name])
	else:
		_say("%s созывает войска: поход на %s, ведёт %s." % [_name(f), best.name, marshal.name])
	operation.emit({"what": "start", "f": f, "target": best.id, "army": army.size(), "keep": plan.keep.size(), "marshal": marshal.id, "ruin": ruin})
	if clans != null and best.fac != Config.PLAYER_FACTION and not ruin:
		clans.on_campaign(f, best)

## A campaign under way, every 2 hours: retreat when spent or needed at home, then muster, march, siege and rest
## around the marshal.
func _run_campaign(f: String, c: Dictionary, enemies: Array) -> void:
	var t := map.settlement_by_id(c.tid)
	var army := _party_ids(c).filter(func(p): return p.fac == f)
	if t.is_empty() or not (t.fac in enemies or _is_own_ruin(f, t)) or army.is_empty():
		operation.emit({"what": "end", "f": f, "why": "lost" if army.is_empty() else "target", "state": String(c.state), "hours": now_h() - int(c.t0)})
		_end_campaign(f)
		return
	var now_s := ops.total(army)
	if c.get("s0") == null:
		c.s0 = now_s  # a campaign from a save made before stage 2b goes on from its present strength
	var marshal := roster.party_by_id(c.get("marshal")) if c.get("marshal") != null else {}
	if marshal.is_empty() or not marshal in army:
		marshal = ops.marshal_of(army)
		c.marshal = marshal.id
	if c.state != "rest":
		if CampaignOps.weak(float(c.s0), now_s):
			c.now = now_s
			_retreat(f, c, t, "weak", {})
			return
		var home := ops.recall(f, map.settles, marshal, t, _relief_busy(f, -1), _covered)
		if not home.is_empty():
			_retreat(f, c, t, "home", home)
			return
	var followers := army.filter(func(p): return p != marshal)
	match c.state:
		"muster":
			var rally := map.settlement_by_id(c.gid)
			var at_rally := rally.is_empty() or _dist(marshal, rally) < Config.OP_SIEGE_REACH
			var joined := followers.filter(func(p): return _dist(p, marshal) < Config.OP_MUSTER_RADIUS).size()
			if (at_rally and joined >= ceili(followers.size() * Config.OP_MUSTER_SHARE)) or now_h() - int(c.t0) > Config.OP_MUSTER_HOURS:
				c.state = "march"
				c.t1 = now_h()
				await _go_co(marshal, t)
				for p in followers:
					await _rest_point()
					await _follow(p, marshal)
			else:
				if not at_rally and _idle(marshal):
					await _go_co(marshal, rally)
				for p in followers:
					await _rest_point()
					await _follow(p, marshal)
		"march":
			var near := army.filter(func(p): return _dist(p, t) < Config.OP_SIEGE_GATHER)
			if (_dist(marshal, t) < Config.OP_SIEGE_REACH and near.size() >= ceili(army.size() * 0.5)) or now_h() - int(c.t1) > Config.OP_MARCH_HOURS:
				operation.emit({"what": "siege", "f": f, "near": near.size(), "army": army.size(), "marshal_d": _dist(marshal, t), "busy": t.get("siege") != null, "hours": now_h() - int(c.t1)})
				if _is_own_ruin(f, t):
					_storm_ruin(f, t, c)
				else:
					_begin_siege(f, t, c)
				return
			var keep_up := followers.filter(func(p): return _dist(p, marshal) < Config.OP_MUSTER_RADIUS).size()
			var close := _dist(marshal, t) < Config.OP_SIEGE_APPROACH
			if keep_up < ceili(followers.size() * Config.OP_MARCH_TOGETHER) and not close:
				_halt(marshal)  # the marshal waits for the host
			elif _idle(marshal):
				await _go_co(marshal, t)
			for p in followers:
				await _rest_point()
				if close:
					if _idle(p) and _dist(p, t) >= Config.OP_SIEGE_GATHER:
						await _go_co(p, t)
				else:
					await _follow(p, marshal)
		"siege":
			if t.get("siege") == null:
				c.state = "rest"
				c.t2 = now_h()
			else:
				for p in army:  # stragglers join the siege lines
					if _idle(p) and _dist(p, t) >= 90.0:
						await _go_co(p, t)
		"rest":
			if now_h() - int(c.t2) > 72:
				operation.emit({"what": "end", "f": f, "why": "rested", "state": "rest", "hours": now_h() - int(c.t0)})
				_end_campaign(f)

## A lord rested enough for a campaign: at least OP_READY_SHARE of a full army; battered ones rest first (party_goals).
static func _ready(p: Dictionary) -> bool:
	var full := (Config.GOAL_LORD_FULL if p.kind == Config.LORD_KIND else Config.GOAL_VASSAL_FULL) * MK
	return Rules.troop_count(p.troops) >= full * Config.OP_READY_SHARE

static func _dist(a: Dictionary, b: Dictionary) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()

## A party with no route left and not chasing or fighting anyone.
static func _idle(p: Dictionary) -> bool:
	return p.pi >= p.path.size() and p.state != "hunt" and not p.get("fight", false)

## A follower rides after the marshal when it fell behind (not while chasing or fighting).
func _follow(p: Dictionary, marshal: Dictionary) -> void:
	if p.state == "hunt" or p.get("fight", false) or _dist(p, marshal) <= Config.OP_FOLLOW_KEEP:
		return
	# Already riding to where the marshal stands: the route is not planned again. A search for every straggler every
	# two hours of the muster cost most of the time of the world step and made the map stutter.
	if p.state == "travel" and p.pi < p.path.size() and p.get("sid") == null and p.get("tid") == null:
		var route_end: Vector2 = p.path[p.path.size() - 1]
		if route_end.distance_to(Vector2(marshal.x, marshal.y)) <= Config.OP_FOLLOW_KEEP * 0.75:
			return
	p.state = "travel"
	p.sid = null
	p.tid = null
	p.hide = false
	if not await roster.path_to_co(p, marshal.x + roster.rnd(-20, 20), marshal.y + roster.rnd(10, 30)):
		p.path = []

func _halt(p: Dictionary) -> void:
	if p.state == "hunt" or p.get("fight", false):
		return
	p.path = []
	p.pi = 0

## A campaign is called off: the host is spent ("weak") or an own besieged settlement needs it ("home"); in the second
## case the host becomes the relief of that settlement at once.
func _retreat(f: String, c: Dictionary, t: Dictionary, why: String, home: Dictionary) -> void:
	if t.get("siege") != null and String(t.siege.get("f", "")) == f:
		t.siege = null
		_news(t, "Осада %s снята: осаждающие отступили." % t.name, true)
		settlement_changed.emit(t)
	if why == "weak":
		_say("%s прекращает поход на %s: войско обескровлено." % [_name(f), t.name])
	else:
		_say("%s прекращает поход на %s: войско идёт на выручку осаждённому %s." % [_name(f), t.name, home.name])
	operation.emit({"what": "retreat", "why": why, "f": f, "target": t.id, "state": String(c.state), "s0": float(c.get("s0", 0.0)), "now": float(c.get("now", 0.0)), "hours": now_h() - int(c.t0), "army": c.army.size(), "left": _party_ids(c).size()})
	_end_campaign(f)
	if not home.is_empty():
		_start_relief(home, home.siege, _besiegers(home), Config.OP_RECALL_RANGE)

## _go for the campaign loop (awaited): the route search may rest between frames.
func _go_co(p: Dictionary, s: Dictionary) -> void:
	if s.is_empty():
		return
	p.state = "travel"
	p.sid = s.id
	p.tid = null
	if not await roster.path_to_co(p, s.x + roster.rnd(-26, 26), s.y + roster.rnd(18, 40)):
		p.path = []
	p.arrived = false
	p.hide = false

func _go(p: Dictionary, s: Dictionary) -> void:
	if s.is_empty():
		return
	p.state = "travel"
	p.sid = s.id
	p.tid = null
	if not roster.path_to(p, s.x + roster.rnd(-26, 26), s.y + roster.rnd(18, 40)):
		p.path = []
	p.arrived = false
	p.hide = false

func _end_campaign(f: String) -> void:
	var c: Variant = campaigns.get(f)
	if c != null:
		for id in c.army:
			var p := roster.party_by_id(id)
			if p.is_empty():
				continue
			p.army = false
			p.arrived = false
			p.state = "idle"
			p.path = []
			p.pi = 0
			p.wait = float(roster.rint(1, 4))
			var homes := map.settles.filter(func(s): return s.fac == f and s.kind != "camp")
			homes.sort_custom(func(a, b): return Vector2(a.x - p.x, a.y - p.y).length() < Vector2(b.x - p.x, b.y - p.y).length())
			if not homes.is_empty():
				p.home = homes[0].id
				p.sid = homes[0].id
				p.state = "travel"
				roster.path_to(p, homes[0].x, homes[0].y)
	campaigns.erase(f)

## The host reached its ruins held by the dead: those by the walls storm them together (no siege: the dead do not starve
## and nobody relieves them), then the campaign rests and ends.
func _storm_ruin(f: String, t: Dictionary, c: Dictionary) -> void:
	var army := _party_ids(c)
	var host := army.filter(func(p): return _dist(p, t) < Config.OP_SIEGE_APPROACH and not p.get("fight", false))
	c.state = "rest"
	c.t2 = now_h()
	for p in army:
		p.state = "idle"
		p.path = []
		p.pi = 0
		p.arrived = true
	if host.is_empty() or not retake.is_valid():
		return
	var won: bool = retake.call(host, t)
	operation.emit({"what": "retaken" if won else "repulsed", "f": f, "target": t.id, "host": host.size()})
	if not won:
		_say("%s не смогло отбить %s у мертвецов." % ["Войско " + String(roster.factions.get_faction(f).get("gen", f)), t.name])

func _begin_siege(f: String, t: Dictionary, c: Dictionary) -> void:
	var army := _party_ids(c)
	c.state = "siege"
	var a0 := 0.0
	for p in army:
		p.state = "idle"
		p.path = []
		p.pi = 0
		p.arrived = true
		a0 += roster.strength_of(p)
	if t.get("siege") != null:
		return
	t["siege"] = {"f": f, "t0": now_h(), "a0": maxf(1.0, a0), "g0": maxi(1, Rules.troop_count(garrison_of(t)))}
	if t.fac == Config.PLAYER_FACTION:
		holding_news.emit(t, "%s осаждает твой %s %s! Гарнизон держится, пока его не перебьют; приди на выручку и разбей осаждающих." % [_name(f), _kind_name(t), t.name], false)
		settlement_changed.emit(t)
	else:
		_say("%s осаждает %s." % [_name(f), t.name])

static func _kind_name(s: Dictionary) -> String:
	return "замок" if s.kind == "castle" else ("город" if s.kind == "town" else "посёлок")

## Siege news: about the player's holding to the player (holding_news), about others to the world chronicle.
func _news(s: Dictionary, text: String, good: bool) -> void:
	if s.get("fac") == Config.PLAYER_FACTION:
		holding_news.emit(s, text, good)
	else:
		_say(text)

## Strength of the besiegers of `s` by its walls (the same parties _siege_tick counts).
func _besiegers(s: Dictionary) -> float:
	var sg: Variant = s.get("siege")
	if sg == null:
		return 0.0
	return ops.total(roster.parties.filter(func(p): return p.get("army", false) and p.fac == sg.f and Vector2(p.x - s.x, p.y - s.y).length() < 100.0 and not p.get("fight", false)))

func _siege_tick(s: Dictionary) -> void:
	var sg: Dictionary = s.siege
	var att := roster.parties.filter(func(p): return p.get("army", false) and p.fac == sg.f and Vector2(p.x - s.x, p.y - s.y).length() < 100.0 and not p.get("fight", false))
	if att.is_empty():
		s.siege = null
		_news(s, "Осада %s снята: осаждающих разбили." % s.name, true)
		settlement_changed.emit(s)
		return
	var g := garrison_of(s)
	var a_str := 0.0
	for p in att:
		a_str += roster.strength_of(p)
	var d_str := siege_def(s)
	var k := a_str / d_str
	var dur := now_h() - int(sg.t0)
	var loss_d := clampf(0.05 * k, 0.01, 0.12)
	var loss_a := clampf(0.035 / k, 0.005, 0.08)
	for t in g.duplicate():
		Rules.remove_troops(g, t.type, roundi(t.n * loss_d + (1.0 if roster.rng.randf() < fmod(t.n * loss_d, 1.0) else 0.0)))
	var retinue := _retinue(s)
	if not retinue.is_empty():
		_cut(retinue.troops, loss_d)
		if Rules.troop_count(retinue.troops) < 1:
			roster.remove(retinue)
	for p in att:
		for t in p.troops.duplicate():
			Rules.remove_troops(p.troops, t.type, roundi(t.n * loss_a))
	for p in att.duplicate():
		if Rules.troop_count(p.troops) < 6:
			roster.remove(p)
	att = att.filter(func(p): return p in roster.parties)
	if _sg_tick(s, sg, att, a_str, k):
		return
	var left := Rules.troop_count(g)
	if left <= maxf(7.0, sg.g0 * 0.16) and dur >= 12:
		_capture(s, sg.f, att)
		return
	if a_str < sg.a0 * 0.3:
		s.siege = null
		_news(s, "Осада %s снята: силы осаждающих иссякли." % s.name, true)
		settlement_changed.emit(s)
		return
	if dur > 110:
		if k > 1.25:
			_capture(s, sg.f, att)
		else:
			s.siege = null
			_news(s, "Осада %s снята: осада затянулась." % s.name, true)
			settlement_changed.emit(s)

## A settlement changes hands: the attackers leave part of their men as the garrison.
func _capture(s: Dictionary, f: String, att: Array) -> void:
	var old: String = s.fac
	var kind: String = s.kind
	s.siege = null
	s["cult"] = String(s.get("cult", s.fac))
	var gar_n := (90.0 if s.kind == "castle" else 70.0) * MK
	var total := 1
	for p in att:
		total += Rules.troop_count(p.troops)
	var share := minf(0.5, gar_n / maxf(1, total - 1))
	var take: Array = []
	for p in att:
		for t in p.troops.duplicate():
			var n := roundi(t.n * share)
			if n > 0:
				Rules.remove_troops(p.troops, t.type, n)
				take.append([t.type, n])
	s.fac = f
	s["owner"] = null
	s.gar = []
	for t in take:
		Rules.add_troops(s.gar, t[0], t[1])
	if Rules.troop_count(s.gar) < 25 * MK:
		for a in roster.gen_troops(f, 25, 0.5):
			Rules.add_troops(s.gar, a.type, a.n)
	SettlementRecruits.refresh(s, roster.catalog, roster.rng)
	s["market"] = null
	s["ruin"] = 0
	for p in roster.parties.duplicate():
		if Rules.is_noble(p) and p.fac == old and p.hide and p.home == s.id:
			var homes := map.settles.filter(func(q): return q.fac == old and q.kind != "camp" and q != s)
			if homes.is_empty():
				roster.remove(p)
			else:
				var h: Dictionary = homes[0]
				p.home = h.id
				p.hide = false
				p.x = h.x
				p.y = h.y + 20.0
				p.state = "idle"
	for v in map.settles:
		if v.kind == "village" and v.fac == old and Vector2(v.x - s.x, v.y - s.y).length() < 170.0:
			v["cult"] = String(v.get("cult", v.fac))
			v.fac = f
			settlement_changed.emit(v)
	if old == Config.PLAYER_FACTION:
		holding_news.emit(s, "%s берёт твой %s %s. Владение потеряно." % [_name(f), "замок" if kind == "castle" else "город", s.name], false)
	else:
		_say("%s берёт %s %s (бывший %s)." % [_name(f), "замок" if kind == "castle" else "город", s.name, roster.factions.get_faction(old).get("gen", old)])
	settlement_changed.emit(s)
	_sack_ai(s)
	if clans != null:
		clans.on_capture(s, old, f)
	if old in Rules.REAL_FACTIONS and not alive(old):
		_fall(old, f)

func _fall(old: String, by: String) -> void:
	_say("Государство «%s» пало." % _name(old))
	if clans != null:
		clans.on_fall(old, by) # houses of the fallen state go over first, so their lords survive
	for v in map.settles:
		if v.fac == old:
			v["cult"] = String(v.get("cult", v.fac))
			v.fac = by
			settlement_changed.emit(v)
	for p in roster.parties.duplicate():
		if p.fac == old:
			roster.remove(p)
	campaigns.erase(old)
	for k in wars.keys():
		if old in k.split("|"):
			wars.erase(k)


func start_time(d: int, h: int) -> void:
	day = d
	hour = h


# ---------- siege extras (src/05i_siege.js): sorties, relief, fires, hunger, wall repair, sacking ----------

const SG_DMG_H := 24 * 10 # hours for walls to be repaired completely

func _cut(list: Array, rate: float) -> void:
	# random rounding: small stacks melt too (sgCut)
	for t in list.duplicate():
		Rules.remove_troops(list, t.type, floori(t.n * rate + roster.rng.randf()))

## Every 2 hours of a siege. True when the siege ended (relief broke the besiegers).
func _sg_tick(s: Dictionary, sg: Dictionary, att: Array, a_str: float, k: float) -> bool:
	var dur := now_h() - int(sg.t0)
	var g := garrison_of(s)
	s.dmg = minf(1.0, float(s.get("dmg", 0.0)) + 0.008 + 0.014 * clampf(k, 0.0, 2.0))
	if not int(s.get("fire", 0)) > 0 and roster.rng.randf() < 0.04 + 0.05 * clampf(k, 0.0, 2.0):
		s.fire = roster.rint(30, 70)
		_news(s, "В %s %s начался пожар." % ["замке" if s.kind == "castle" else "городе", s.name], false)
	if dur > 60:
		for p in att:
			_cut(p.troops, 0.02)
		if not sg.get("hun", false):
			sg.hun = true
			_news(s, "Осаждающие %s голодают и дезертируют." % s.name, true)
	_sortie(s, sg, att, a_str, g, dur)
	return _relief(s, sg, att, a_str, dur)

func _sortie(s: Dictionary, sg: Dictionary, att: Array, a_str: float, g: Array, dur: int) -> void:
	if dur < 6 or Rules.troop_count(g) < 10 or roster.rng.randf() > 0.12:
		return
	var gs := Rules.strength(g, roster.info) + 4.0
	var ratio := gs * 1.3 / maxf(1.0, a_str)
	var ok := roster.rng.randf() < clampf(0.2 + 0.5 * ratio, 0.2, 0.8)
	sg.sally = int(sg.get("sally", 0)) + 1
	if ok:
		for p in att:
			_cut(p.troops, roster.rnd(0.05, 0.1))
		_cut(g, roster.rnd(0.02, 0.04))
		_news(s, "Гарнизон %s ночной вылазкой ударил по осаждающим: у них потери." % s.name, true)
	else:
		_cut(g, roster.rnd(0.06, 0.1))
		for p in att:
			_cut(p.troops, roster.rnd(0.01, 0.02))
		_news(s, "Вылазка гарнизона %s отбита, защитники понесли потери." % s.name, false)

func _free_relief(p: Dictionary) -> void:
	p.army = false
	p.erase("relief")
	p.arrived = false
	p.state = "idle"
	p.path = []
	p.pi = 0
	p.wait = float(roster.rint(2, 6))

## The defensive operation of a besieged settlement's faction (stage 2b): relief comes after OP_RELIEF_DELAY hours,
## at most OP_RELIEF_TRIES times a day apart, and only while the faction relieves no other settlement. When the
## relief has gathered by the walls (or waited long enough) it fights the besiegers. True when the siege ended.
func _relief(s: Dictionary, sg: Dictionary, att: Array, a_str: float, dur: int) -> bool:
	var rel := _relief_lords(s, sg)
	if rel.is_empty() and dur >= Config.OP_RELIEF_DELAY and int(sg.get("relN", 0)) < Config.OP_RELIEF_TRIES and now_h() - int(sg.get("relAt", -99)) > 24:
		if _relief_busy(String(s.fac), int(s.id)):
			operation.emit({"what": "no_relief", "f": String(s.fac), "sid": s.id, "why": "busy"})
		elif not _start_relief(s, sg, a_str, Config.OP_RELIEF_RANGE):
			operation.emit({"what": "no_relief", "f": String(s.fac), "sid": s.id, "why": "weak"})
	if rel.is_empty():
		return false
	var near := rel.filter(func(p): return Vector2(p.x - s.x, p.y - s.y).length() < 130.0)
	if near.size() < maxi(1, ceili(rel.size() * 0.6)) and now_h() - int(sg.get("relAt", 0)) < Config.OP_RELIEF_WAIT_HOURS:
		return false
	if near.is_empty():
		for p in rel:
			_free_relief(p)
		return false
	var r := 0.3 * Rules.strength(garrison_of(s), roster.info)
	for p in near:
		r += roster.strength_of(p)
	var win := r * roster.rnd(0.8, 1.2) > a_str * roster.rnd(0.8, 1.2)
	if win:
		for p in att:
			_cut(p.troops, roster.rnd(0.35, 0.55))
		for p in near:
			_cut(p.troops, roster.rnd(0.1, 0.2))
		for p in rel:
			_free_relief(p)
		s.siege = null
		_news(s, "Подмога разбила осаждающих: осада %s снята." % s.name, true)
		settlement_changed.emit(s)
		return true
	for p in near:
		_cut(p.troops, roster.rnd(0.4, 0.6))
	for p in att:
		_cut(p.troops, roster.rnd(0.1, 0.18))
	for p in rel:
		_free_relief(p)
	_news(s, "Подмога осаждённому %s разбита." % s.name, false)
	return false

func _relief_lords(s: Dictionary, sg: Dictionary) -> Array:
	var rel: Array = []
	for id in sg.get("rel", []):
		var p := roster.party_by_id(int(id))
		if not p.is_empty() and p.get("relief") == s.id:
			rel.append(p)
	return rel

## Relief host the lords at home could send to the besieged s from within reach (campaign_ops.gd relief_host); when
## those cannot outmatch the besiegers, lords from within OP_RELIEF_FAR_RANGE are gathered too.
func _relief_host(s: Dictionary, a_str: float, reach: float) -> Array:
	var cands: Array = roster.parties.filter(func(p): return p.kind == Config.LORD_KIND and p.fac == s.fac and not p.get("army", false) and not p.get("fight", false) and not p.get("lock", false) and p.get("relief") == null and Rules.troop_count(p.troops) >= Config.OP_RELIEF_MIN_TROOPS and Vector2(p.x - s.x, p.y - s.y).length() < maxf(reach, Config.OP_RELIEF_FAR_RANGE))
	var gar := Rules.strength(garrison_of(s), roster.info)
	var host := ops.relief_host(cands.filter(func(p): return Vector2(p.x - s.x, p.y - s.y).length() < reach), s, a_str, gar)
	if host.is_empty() and reach < Config.OP_RELIEF_FAR_RANGE:
		host = ops.relief_host(cands, s, a_str, gar)
	return host

## A besieged own settlement the lords at home take care of: relief is on its way, or they can send it.
func _covered(s: Dictionary) -> bool:
	if roster.parties.any(func(p): return p.get("relief") == s.id):
		return true
	return not _relief_host(s, _besiegers(s), Config.OP_RELIEF_RANGE).is_empty()

## Whether faction f already relieves a besieged settlement other than except_id (one defensive operation at a time).
func _relief_busy(f: String, except_id: int) -> bool:
	for p in roster.parties:
		if p.get("relief") != null and int(p.relief) != except_id and p.fac == f:
			return true
	return false

## Sends relief to the besieged s: free lords of its faction within reach (also those resting inside settlements),
## nearest first, enough to outmatch the besiegers (campaign_ops.gd relief_host). False when none can be sent.
func _start_relief(s: Dictionary, sg: Dictionary, a_str: float, reach: float) -> bool:
	var host := _relief_host(s, a_str, reach)
	if host.is_empty():
		return false
	sg.relN = int(sg.get("relN", 0)) + 1
	sg.relAt = now_h()
	sg.rel = host.map(func(p): return p.id)
	for p in host:
		p.relief = s.id
		p.army = true
		_go(p, s)
	_news(s, "К осаждённому %s %s спешит подмога: %s." % ["замку" if s.kind == "castle" else "городу", s.name, ", ".join(host.map(func(p): return p.name))], true)
	operation.emit({"what": "relief", "f": String(s.fac), "sid": s.id, "lords": host.size()})
	return true

## Hourly: fires burn out, walls are repaired, relief lords go home when their siege is over.
func _sg_hour() -> void:
	for s in map.settles:
		if int(s.get("fire", 0)) > 0:
			s.fire = int(s.fire) - 1
		if s.get("siege") == null and float(s.get("dmg", 0.0)) > 0.0:
			s.dmg = maxf(0.0, float(s.dmg) - 1.0 / SG_DMG_H)
	for p in roster.parties:
		if p.get("relief") != null:
			var s := map.settlement_by_id(int(p.relief))
			if s.is_empty() or s.get("siege") == null:
				_free_relief(p)
				p.wait = float(roster.rint(1, 4))

## Lords who took a town sometimes plunder it (sgSackAI).
func _sack_ai(s: Dictionary) -> void:
	if roster.rng.randf() > 0.5:
		return
	s.dmg = maxf(float(s.get("dmg", 0.0)), 0.5)
	s.fire = maxi(int(s.get("fire", 0)), roster.rint(24, 60))
	s.recruits = []
	_say("%s %s разграблен." % ["Замок" if s.kind == "castle" else "Город", s.name])
