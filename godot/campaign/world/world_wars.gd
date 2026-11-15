extends RefCounted
## Wars between states: declaring and ending them, lords' campaigns, sieges and captures of settlements, garrisons
## and the fall of a state (src/05g_war.js, garrison parts of src/05_world.js). Clans, rulers and oaths are separate modules.
const Rules = preload("res://campaign/world/party_rules.gd")
const Roster = preload("res://campaign/world/party_roster.gd")
const WorldMap = preload("res://campaign/world/world_map.gd")
const SettlementRecruits = preload("res://campaign/rules/settlement_recruits.gd")

signal announced(text: String)
signal settlement_changed(settlement: Dictionary)

const MK := 2.0
const GAR_CAP := {"town": 130.0, "castle": 210.0}
const GAR_WAGE := 0.5
const DEF_SIEGE_STONES := {"town": 1.55, "castle": 1.7}

var map: WorldMap
var roster: Roster
var wars: Dictionary = {}     # "a|b" -> {since}
var campaigns: Dictionary = {}  # faction -> {tid, gid, state, t0, t1, t2, army: [ids]}
var day := 1
var hour := 8
var _tally := 0
var clans: RefCounted = null  # WorldClans, optional: rulers, oaths and clan loyalty

func _init(world_map: WorldMap, party_roster: Roster) -> void:
	map = world_map
	roster = party_roster

func now_h() -> int:
	return day * 24 + hour

func start() -> void:
	for a in Rules.WAR:
		for b in Rules.WAR[a]:
			if a != "bandit" and b != "bandit":
				wars[Rules.war_key(a, b)] = {"since": 1}
	Rules.wars = wars

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
	return (Rules.strength(garrison_of(s), roster.info) + 4.0) * (1.8 + (0.8 if h.core <= 3 else (0.35 if h.core <= 5 else 0.0))) * (1.0 - 0.4 * float(s.get("dmg", 0.0)))

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
			_campaign(f)
		for s in map.settles:
			if s.get("siege") != null:
				_siege_tick(s)

func _party_ids(c: Dictionary) -> Array:
	return c.army.map(func(id): return roster.party_by_id(id)).filter(func(p): return not p.is_empty() and p.get("army", false))

func _campaign(f: String) -> void:
	var enemies := factions_alive().filter(func(e): return e != f and at_war(f, e))
	var c: Variant = campaigns.get(f)
	if c != null:
		var t := map.settlement_by_id(c.tid)
		var army := _party_ids(c).filter(func(p): return p.fac == f)
		if t.is_empty() or not t.fac in enemies or army.is_empty():
			_end_campaign(f)
			return
		match c.state:
			"muster":
				var arrived := army.filter(func(p): return p.get("arrived", false)).size()
				if arrived >= ceili(army.size() * 0.7) or now_h() - c.t0 > 40:
					c.state = "march"
					c.t1 = now_h()
					for p in army:
						_go(p, t)
				else:
					for p in army:
						if p.pi >= p.path.size() and not p.get("arrived", false):
							_go(p, map.settlement_by_id(c.gid))
			"march":
				var near := army.filter(func(p): return Vector2(p.x - t.x, p.y - t.y).length() < 80.0)
				if near.size() >= ceili(army.size() * 0.5) or now_h() - c.t1 > 70:
					_begin_siege(f, t, c)
				else:
					for p in army:
						if p.pi >= p.path.size():
							_go(p, t)
			"siege":
				if t.get("siege") == null:
					c.state = "rest"
					c.t2 = now_h()
			"rest":
				if now_h() - c.t2 > 72:
					_end_campaign(f)
		return
	if enemies.is_empty() or hour % 6 != 0:
		return
	if clans != null and clans.kingless(f):
		return
	var lords := _lords_of(f).filter(func(p): return Rules.troop_count(p.troops) >= 20 * MK)
	var total := 0.0
	for p in lords:
		total += roster.strength_of(p)
	if lords.size() < 2 and total < 220.0 * MK:
		return
	var mine := map.settles.filter(func(s): return s.fac == f and s.kind != "camp")
	if mine.is_empty():
		return
	var best := {}
	var best_ms := {}
	var best_score := 1e9
	for t in map.settles:
		if not t.fac in enemies or t.kind == "camp" or t.kind == "village" or t.get("siege") != null:
			continue
		var def := siege_def(t)
		if total < def * 0.9:
			continue
		var md := 1e9
		var ms := {}
		for s in mine:
			var d := Vector2(s.x - t.x, s.y - t.y).length()
			if d < md:
				md = d
				ms = s
		var score := md + def * 0.6 + roster.rnd(0.0, 120.0)
		if score < best_score:
			best_score = score
			best = t
			best_ms = ms
	if best.is_empty():
		return
	var army := lords.filter(func(p): return not p.get("fight", false))
	if army.is_empty():
		return
	campaigns[f] = {"tid": best.id, "gid": best_ms.id, "state": "muster", "t0": now_h(), "army": army.map(func(p): return p.id)}
	for p in army:
		p.army = true
		p.arrived = false
		p.hide = false
		p.wait = 0.0
		_go(p, best_ms)
	_say("%s созывает войска: поход на %s." % [_name(f), best.name])
	if clans != null:
		clans.on_campaign(f, best)

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
	_say("%s осаждает %s." % [_name(f), t.name])

func _siege_tick(s: Dictionary) -> void:
	var sg: Dictionary = s.siege
	var att := roster.parties.filter(func(p): return p.get("army", false) and p.fac == sg.f and Vector2(p.x - s.x, p.y - s.y).length() < 100.0 and not p.get("fight", false))
	if att.is_empty():
		s.siege = null
		_say("Осада %s снята: осаждающих разбили." % s.name)
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
		_say("Осада %s снята: силы осаждающих иссякли." % s.name)
		return
	if dur > 110:
		if k > 1.25:
			_capture(s, sg.f, att)
		else:
			s.siege = null
			_say("Осада %s снята: осада затянулась." % s.name)

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
	_say("%s берёт %s %s (бывший %s)." % [_name(f), "замок" if kind == "castle" else "город", s.name, roster.factions.get_faction(old).get("gen", old)])
	settlement_changed.emit(s)
	_sack_ai(s)
	if clans != null:
		clans.on_capture(s, old, f)
	if not alive(old):
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
		_say("В %s %s начался пожар." % ["замке" if s.kind == "castle" else "городе", s.name])
	if dur > 60:
		for p in att:
			_cut(p.troops, 0.02)
		if not sg.get("hun", false):
			sg.hun = true
			_say("Осаждающие %s голодают и дезертируют." % s.name)
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
		_say("Гарнизон %s ночной вылазкой ударил по осаждающим: у них потери." % s.name)
	else:
		_cut(g, roster.rnd(0.06, 0.1))
		for p in att:
			_cut(p.troops, roster.rnd(0.01, 0.02))
		_say("Вылазка гарнизона %s отбита, защитники понесли потери." % s.name)

func _free_relief(p: Dictionary) -> void:
	p.army = false
	p.erase("relief")
	p.arrived = false
	p.state = "idle"
	p.path = []
	p.pi = 0
	p.wait = float(roster.rint(2, 6))

func _relief(s: Dictionary, sg: Dictionary, att: Array, a_str: float, dur: int) -> bool:
	var rel: Array = []
	for id in sg.get("rel", []):
		var p := roster.party_by_id(int(id))
		if not p.is_empty() and p.get("relief") == s.id:
			rel.append(p)
	if rel.is_empty() and dur >= 10 and int(sg.get("relN", 0)) < 2 and now_h() - int(sg.get("relAt", -99)) > 24:
		var cands: Array = roster.parties.filter(func(p): return p.kind == "lord" and p.fac == s.fac and not p.hide and not p.get("army", false) and not p.get("fight", false) and p.get("relief") == null and Rules.troop_count(p.troops) >= 18 * MK and Vector2(p.x - s.x, p.y - s.y).length() < 480.0)
		cands.sort_custom(func(a, b): return Vector2(a.x - s.x, a.y - s.y).length() < Vector2(b.x - s.x, b.y - s.y).length())
		cands = cands.slice(0, 3)
		if not cands.is_empty():
			sg.relN = int(sg.get("relN", 0)) + 1
			sg.relAt = now_h()
			sg.rel = cands.map(func(p): return p.id)
			for p in cands:
				p.relief = s.id
				p.army = true
				_go(p, s)
			_say("К осаждённому городу %s спешит подмога: %s." % [s.name, ", ".join(cands.map(func(p): return p.name))])
	if rel.is_empty():
		return false
	var near := rel.filter(func(p): return Vector2(p.x - s.x, p.y - s.y).length() < 130.0)
	if near.size() < maxi(1, ceili(rel.size() * 0.6)) and now_h() - int(sg.get("relAt", 0)) < 40:
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
		_say("Подмога разбила осаждающих: осада %s снята." % s.name)
		settlement_changed.emit(s)
		return true
	for p in near:
		_cut(p.troops, roster.rnd(0.4, 0.6))
	for p in att:
		_cut(p.troops, roster.rnd(0.1, 0.18))
	for p in rel:
		_free_relief(p)
	_say("Подмога осаждённому %s разбита." % s.name)
	return false

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
