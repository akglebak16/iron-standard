extends RefCounted
## Companions as the player's vassals (src/05h_vassals.js): a companion gets a town or castle, keeps its garrison, pays
## the player a tribute and hires a retinue (a map party, kind "cvass", faction "player") that guards, patrols or follows.
## Stored in player.vass = [{cid, c, sid, mode, gold, pid, rest, day, trib, inc, up, n}]; the fief is marked s.vass = cid.
const Rules = preload("res://campaign/world/party_rules.gd")
const Roster = preload("res://campaign/world/party_roster.gd")

const MK := 2.0
const TRIB := 0.3
const MAX := 3
const REST := 3
const MODES := {"guard": ["Охранять надел", "дружина стоит у надела и бьёт тех, кто подошёл близко"],
	"patrol": ["Дозор", "дружина ходит по округе и охотится на слабых врагов"],
	"follow": ["За мной", "дружина идёт за тобой и держится рядом"]}
const HELP_RADIUS := 170.0
const WW := 5200.0
const WH := 3400.0

signal message(text: String)

var roster: Roster
var siege: RefCounted      # WorldSiege: income/upkeep/garrisons
var companions: RefCounted # WorldCompanions: taverns for a returning companion
var player: RefCounted

func _init(party_roster: Roster, world_siege: RefCounted, world_companions: RefCounted, player_party: RefCounted) -> void:
	roster = party_roster
	siege = world_siege
	companions = world_companions
	player = player_party

func list() -> Array:
	return player.vass

func of_id(cid: String) -> Dictionary:
	for v in player.vass:
		if v.cid == cid:
			return v
	return {}

func party_of(v: Dictionary) -> Dictionary:
	if v.is_empty() or v.get("pid") == null:
		return {}
	var p: Dictionary = roster.party_by_id(int(v.pid))
	return p if not p.is_empty() and p.kind == "cvass" else {}

func fiefs() -> Array:
	return roster.map.settles.filter(func(s): return s.fac == "player" and s.get("owner", -1) == 0 and (s.kind == "town" or s.kind == "castle"))

func cap(v: Dictionary) -> int:
	return roundi((40 + int(v.c.get("lvl", 1)) * 6 + int(v.c.get("cha", 1)) * 6) * MK)

func net_income(s: Dictionary) -> int:
	return maxi(0, siege.income(s) - siege.upkeep(s))

func _comp(cid: String) -> Dictionary:
	for c in player.comps:
		if c.id == cid:
			return c
	return {}

func why_not(cid: String, sid: int) -> String:
	var s: Dictionary = roster.map.settlement_by_id(sid)
	if _comp(cid).is_empty():
		return "Этого спутника нет в отряде."
	if player.vass.size() >= MAX:
		return "Не больше %d вассалов." % MAX
	if s.is_empty() or s.fac != "player" or s.get("owner", -1) != 0 or (s.kind != "town" and s.kind != "castle"):
		return "Надел — это твой город или замок."
	if s.has("vass"):
		return "Здесь уже сидит вассал."
	return ""

func grant(cid: String, sid: int) -> String:
	var why := why_not(cid, sid)
	if why != "":
		return why
	var c := _comp(cid)
	var s: Dictionary = roster.map.settlement_by_id(sid)
	player.comps.erase(c)
	var v := {"cid": cid, "c": c, "sid": sid, "mode": "guard", "gold": 0.0, "pid": null, "rest": 0, "day": 0}
	player.vass.append(v)
	s.vass = cid
	spawn(v)
	message.emit("%s получает в надел %s и присягает тебе. Подать: %d%% дохода, остальное он тратит на дружину." % [c.name, s.name, roundi(TRIB * 100)])
	return ""

func _cult(s: Dictionary) -> String:
	var c := String(s.get("cult", s.fac))
	return c if c in Rules.REAL_FACTIONS else "emp"

func spawn(v: Dictionary) -> Dictionary:
	var s: Dictionary = roster.map.settlement_by_id(v.sid)
	if s.is_empty():
		return {}
	var old := party_of(v)
	if not old.is_empty():
		return old
	var p := roster.make_party("cvass", "player", v.c.name, s.x + roster.rnd(-20, 20), s.y + 24, roster.gen_troops(_cult(s), 4, 0.45), {"owner": 0, "cid": v.cid, "home": s.id})
	v.pid = p.id
	v.rest = 0
	return p

## Takes the fief back: the retinue joins the garrison, the vassal's purse goes to the player, the companion returns.
func revoke(cid: String, why := " оставляет надел") -> bool:
	var v := of_id(cid)
	if v.is_empty():
		return false
	var s: Dictionary = roster.map.settlement_by_id(v.sid)
	var p := party_of(v)
	if not p.is_empty():
		if not s.is_empty() and s.fac == "player" and s.get("owner", -1) == 0:
			for t in p.troops:
				Rules.add_troops(siege.wars.garrison_of(s), t.type, int(t.n))
		roster.remove(p)
	player.vass.erase(v)
	if not s.is_empty() and s.get("vass") == cid:
		s.erase("vass")
	if float(v.gold) > 0:
		player.gold += roundi(float(v.gold))
	var c: Dictionary = v.c
	if player.comps.size() < companions.COMP_MAX:
		player.comps.append(c)
		message.emit("%s%s и возвращается в твой отряд. Казна вассала (%d) — тебе." % [c.name, why, roundi(float(v.gold))])
	else:
		companions.saved[cid] = c
		var all: Array = companions.towns()
		var at: Dictionary = s if not s.is_empty() else {"x": player.x, "y": player.y}
		all.sort_custom(func(a, b): return Vector2(a.x - at.x, a.y - at.y).length() < Vector2(b.x - at.x, b.y - at.y).length())
		if not all.is_empty():
			companions.pos[cid] = all[0].id
		message.emit("%s%s: в отряде нет места, он ждёт в таверне." % [c.name, why])
	return true

func _wage(p: Dictionary) -> int:
	var w := 0.0
	for t in p.troops:
		w += float(roster.catalog.get_troop(t.type).wage) * int(t.n)
	return roundi(w / 3.0)

func _cost(type: String) -> int:
	return int(roster.catalog.get_troop(type).get("cost", 40))

## Once a day: tribute, the vassal's purse, retinue wages and hiring.
func day_tick() -> void:
	for v in player.vass.duplicate():
		var s: Dictionary = roster.map.settlement_by_id(v.sid)
		if s.is_empty() or s.fac != "player" or s.get("owner", -1) != 0:
			message.emit("%s потерял надел и вернулся к тебе." % v.c.name)
			revoke(v.cid, " лишился надела")
			continue
		var p := party_of(v)
		if p.is_empty():
			if v.get("pid") != null:
				v.pid = null
				v.rest = REST
				message.emit("Дружина %s разбита. Он соберёт новую за %d дн." % [v.c.name, REST])
			else:
				v.rest = int(v.rest) - 1
				if v.rest <= 0:
					p = spawn(v)
		var net := net_income(s)
		var trib := roundi(net * TRIB)
		player.gold += trib
		v.gold = float(v.gold) + net - trib
		v.trib = trib
		v.inc = net
		if p.is_empty():
			continue
		var up := _wage(p)
		v.gold = float(v.gold) - up
		v.up = up
		if float(v.gold) < 0.0:
			v.gold = 0.0
			for t in p.troops.duplicate():
				Rules.remove_troops(p.troops, t.type, ceili(int(t.n) * 0.08))
			if p.troops.is_empty():
				for a in roster.gen_troops(_cult(s), 1, 0.3):
					Rules.add_troops(p.troops, a.type, a.n)
			message.emit("Казна %s пуста: дружина без жалованья, часть людей разбежалась." % v.c.name)
			continue
		var budget := float(v.gold) - up * 3.0
		var room := cap(v) - Rules.troop_count(p.troops)
		var spent := 0
		if budget > 25.0 and room > 0:
			for a in roster.gen_troops(_cult(s), mini(6, ceili(room / MK)), 0.55):
				for i in int(a.n):
					var c := _cost(a.type)
					if budget * 0.6 < c or room <= 0:
						break
					budget -= c
					spent += c
					room -= 1
					Rules.add_troops(p.troops, a.type, 1)
		v.gold = float(v.gold) - spent
		v.n = Rules.troop_count(p.troops)

## The retinue standing by its fief helps the garrison against an assault.
func defence_of(s: Dictionary) -> Dictionary:
	if not s.has("vass"):
		return {}
	var p := party_of(of_id(s.vass))
	if p.is_empty() or p.hide or Vector2(p.x - s.x, p.y - s.y).length() > 90.0:
		return {}
	return p

func defence_hit(p: Dictionary, r: float, win: bool) -> void:
	if p.is_empty():
		return
	for t in p.troops.duplicate():
		Rules.remove_troops(p.troops, t.type, roundi(int(t.n) * r * (0.3 if win else 0.5)))
	if p.troops.is_empty():
		roster.remove(p)

## Retinue AI (cvAI).
func ai(p: Dictionary, dh: float) -> void:
	var v := of_id(String(p.get("cid", "")))
	var s: Dictionary = roster.map.settlement_by_id(v.sid) if not v.is_empty() else {}
	if v.is_empty() or s.is_empty():
		roster.remove(p)
		return
	p.ai = float(p.get("ai", 0.0)) - dh
	if p.ai <= 0.0:
		p.ai = roster.rnd(0.8, 1.6)
		var me := roster.strength_of(p)
		var mode: String = v.get("mode", "guard")
		var radius := 150.0 if mode == "guard" else 260.0
		var tgt: Dictionary = {}
		var tb := 1e9
		var threat: Dictionary = {}
		for o in roster.parties:
			if o == p or o.hide or o.kind == "camp" or o.get("fight", false) or o.get("lock", false) or not Rules.hostile(p, o):
				continue
			var d := Vector2(o.x - p.x, o.y - p.y).length()
			if d > radius or (mode == "guard" and Vector2(o.x - s.x, o.y - s.y).length() > 230.0):
				continue
			var so := roster.strength_of(o)
			if so < me * 0.8:
				if d < tb:
					tb = d
					tgt = o
			elif so > me * 1.2 and d < 150.0:
				threat = o
		if not threat.is_empty() and tgt.is_empty():
			var home_x: float = player.x if mode == "follow" and not player.away else s.x
			var home_y: float = player.y if mode == "follow" and not player.away else s.y
			p.state = "flee"
			p.tid = null
			roster.path_to(p, home_x, home_y)
		elif not tgt.is_empty():
			p.tid = tgt.id
			p.state = "hunt"
			roster.path_to(p, tgt.x, tgt.y)
		else:
			if p.state == "hunt" or p.state == "flee":
				p.state = "idle"
				p.tid = null
			if p.pi >= p.path.size():
				if mode == "follow" and not player.away:
					if Vector2(player.x - p.x, player.y - p.y).length() > 70.0:
						roster.path_to(p, player.x + roster.rnd(-40, 40), player.y + roster.rnd(20, 50))
						p.state = "travel"
				elif mode == "patrol":
					var a := roster.rnd(0.0, TAU)
					var r := roster.rnd(80.0, 300.0)
					if roster.path_to(p, clampf(s.x + cos(a) * r, 60.0, WW - 60.0), clampf(s.y + sin(a) * r, 60.0, WH - 60.0)):
						p.state = "travel"
				else:
					var far := Vector2(s.x - p.x, s.y - p.y).length() > 110.0
					if far or roster.rng.randf() < 0.25:
						var a := roster.rnd(0.0, TAU)
						var r := 20.0 if far else roster.rnd(30.0, 90.0)
						if roster.path_to(p, clampf(s.x + cos(a) * r, 60.0, WW - 60.0), clampf(s.y + 22 + sin(a) * r, 60.0, WH - 60.0)):
							p.state = "travel"
	if p.state == "hunt":
		var t: Dictionary = roster.party_by_id(p.tid) if p.tid != null else {}
		if t.is_empty() or t.hide:
			p.state = "idle"
			p.path = []
			p.tid = null
		else:
			p.rp = float(p.get("rp", 0.0)) - dh
			if p.rp <= 0.0:
				p.rp = 0.7
				roster.path_to(p, t.x, t.y)
	if p.pi < p.path.size():
		if roster.move_along(p, dh) and p.state == "travel":
			p.state = "idle"
			p.path = []
			p.pi = 0

func set_mode(cid: String, mode: String) -> void:
	var v := of_id(cid)
	if v.is_empty() or not MODES.has(mode):
		return
	v.mode = mode
	var p := party_of(v)
	if not p.is_empty():
		p.path = []
		p.pi = 0
		p.state = "idle"
		p.tid = null
		p.ai = 0.0

func give(cid: String, gold: int) -> bool:
	var v := of_id(cid)
	if v.is_empty() or player.gold < gold:
		return false
	player.gold -= gold
	v.gold = float(v.gold) + gold
	return true

## Retinues near the fight join the player's battle (cvHelpers).
func helpers(enemy: Dictionary) -> Array:
	if enemy.kind in ["camp", "siege", "caravan"]:
		return []
	var out: Array = []
	for o in roster.parties:
		if o.kind != "cvass" or o == enemy or o.hide or o.get("fight", false) or o.get("lock", false) or Rules.troop_count(o.troops) < 1:
			continue
		if not Rules.hostile(o, enemy):
			continue
		if minf(Vector2(o.x - enemy.x, o.y - enemy.y).length(), Vector2(o.x - player.x, o.y - player.y).length()) < HELP_RADIUS:
			out.append(o)
	return out
