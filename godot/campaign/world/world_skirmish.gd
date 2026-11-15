extends RefCounted
## Fights between map parties that last for hours (warContact, skirmHour, skEnd, warAllyStr, warRally in src/05g_war.js)
## and allies of the enemy joining the player's battle (encHelpers, encMerge, encSplit).
const Rules = preload("res://campaign/world/party_rules.gd")
const Roster = preload("res://campaign/world/party_roster.gd")

const MK := 2.0
const LOSS := 0.06 # share a side loses per hour against equal strength
const HELP_RADIUS := 170.0
const WW := 5200.0
const WH := 3400.0

var roster: Roster
var clans: RefCounted = null  # rulers are carried off lost fields
var undead: RefCounted = null # the dead raise the fallen
var fights: Array = []        # {id, A: [ids], B: [ids], t0, x, y, a0, b0}
var next_id := 1
var hour_now := 0

func _init(party_roster: Roster) -> void:
	roster = party_roster

func _count(list: Array) -> int:
	var n := 0
	for p in list:
		n += Rules.troop_count(p.troops)
	return n

## Two hostile parties meet: small bands or caravans settle it at once, armies start a fight that lasts hours.
func contact(a: Dictionary, b: Dictionary, auto_fight: Callable) -> void:
	var small := func(x): return Rules.troop_count(x.troops) < 12 * MK
	if a.kind == "caravan" or b.kind == "caravan" or (small.call(a) and small.call(b)):
		auto_fight.call(a, b)
		return
	var side := func(x: Dictionary, o: Dictionary) -> Array:
		return roster.parties.filter(func(c): return c != o and not c.hide and c.kind != "camp" and not c.get("fight") and not c.get("lock", false) and c.fac == x.fac and Vector2(c.x - x.x, c.y - x.y).length() < 70.0 and not Rules.hostile(c, o) and c.kind != "caravan")
	var sa: Array = side.call(a, b)
	var sb: Array = side.call(b, a)
	if not a in sa:
		sa.append(a)
	if not b in sb:
		sb.append(b)
	var sk := {"id": next_id, "A": sa.map(func(p): return p.id), "B": sb.map(func(p): return p.id), "t0": hour_now, "x": (a.x + b.x) / 2.0, "y": (a.y + b.y) / 2.0, "a0": _count(sa), "b0": _count(sb)}
	next_id += 1
	for p in sa + sb:
		p.fight = sk.id
		p.path = []
		p.pi = 0
		p.tid = null
		p.state = "idle"
	fights.append(sk)

func _side(sk: Dictionary, ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var p := roster.party_by_id(int(id))
		if not p.is_empty() and p.get("fight") == sk.id:
			out.append(p)
	return out

func _cut(list: Array, l: float) -> void:
	for p in list:
		for t in p.troops.duplicate():
			var f: float = t.n * l
			var n := floori(f) + (1 if roster.rng.randf() < fmod(f, 1.0) else 0)
			if n > 0:
				Rules.remove_troops(p.troops, t.type, n)

func _spared(p: Dictionary) -> bool:
	return clans != null and clans.ruler_spared(p)

## Hourly: neighbours join, both sides lose men, a side that falls under a quarter breaks.
func hour_tick() -> void:
	for sk in fights.duplicate():
		for p in roster.parties:
			if p.get("fight") or p.hide or p.kind == "camp" or p.kind == "caravan" or p.get("lock", false) or Vector2(p.x - sk.x, p.y - sk.y).length() > 90.0:
				continue
			var a := _side(sk, sk.A)
			var b := _side(sk, sk.B)
			if a.is_empty() or b.is_empty():
				break
			var ha := a.any(func(q): return Rules.hostile(p, q))
			var hb := b.any(func(q): return Rules.hostile(p, q))
			if hb and not ha:
				sk.A.append(p.id)
				p.fight = sk.id
				sk.a0 += Rules.troop_count(p.troops)
			elif ha and not hb:
				sk.B.append(p.id)
				p.fight = sk.id
				sk.b0 += Rules.troop_count(p.troops)
			if p.get("fight"):
				p.path = []
				p.pi = 0
				p.tid = null
				p.state = "idle"
		var sa := _side(sk, sk.A)
		var sb := _side(sk, sk.B)
		if sa.is_empty() or sb.is_empty():
			_end(sk, sa, sb, 0 if not sa.is_empty() else 1)
			continue
		var stra := 0.0
		var strb := 0.0
		for p in sa:
			stra += roster.strength_of(p)
		for p in sb:
			strb += roster.strength_of(p)
		var la := clampf(LOSS * strb / maxf(1.0, stra), LOSS / 8.0, LOSS * 2.5) * roster.rnd(0.85, 1.15)
		var lb := clampf(LOSS * stra / maxf(1.0, strb), LOSS / 8.0, LOSS * 2.5) * roster.rnd(0.85, 1.15)
		_cut(sa, la)
		_cut(sb, lb)
		var a2 := sa.filter(func(p): return Rules.troop_count(p.troops) > 0)
		var b2 := sb.filter(func(p): return Rules.troop_count(p.troops) > 0)
		for p in sa + sb:
			if Rules.troop_count(p.troops) < 1 and not _spared(p):
				roster.remove(p)
		var ma := _count(a2)
		var mb := _count(b2)
		if a2.is_empty() or b2.is_empty() or ma < sk.a0 * 0.25 or mb < sk.b0 * 0.25:
			var winner := 1 if (a2.is_empty() or (not b2.is_empty() and float(ma) / maxf(1.0, sk.a0) < float(mb) / maxf(1.0, sk.b0))) else 0
			_end(sk, a2, b2, winner)

func _end(sk: Dictionary, a: Array, b: Array, winner: int) -> void:
	var w: Array = b if winner == 1 else a
	var l: Array = a if winner == 1 else b
	var lost_men: int = int(sk.a0 if winner == 1 else sk.b0) - _count(l)
	fights.erase(sk)
	for p in w:
		p.fight = null
		p.state = "idle"
		p.path = []
		p.pi = 0
		p.cd = 3.0
		p.gold += 20 + roundi(lost_men * 2)
		if p.fac == "undead" and undead != null:
			undead.raise(p, maxi(0, lost_men) * undead.RAISE)
	for p in l:
		p.fight = null
		p.cd = 6.0
		if (Rules.troop_count(p.troops) < 8 and not _spared(p)) or p.kind == "bandit":
			roster.remove(p)
		else:
			var ang := atan2(p.y - w[0].y, p.x - w[0].x) if not w.is_empty() else roster.rnd(0.0, TAU)
			p.state = "flee"
			roster.path_to(p, clampf(p.x + cos(ang) * 240.0, 60.0, WW - 60.0), clampf(p.y + sin(ang) * 240.0, 60.0, WH - 60.0))

## Friendly strength nearby, weighed when a party decides whether to attack.
func ally_strength(p: Dictionary) -> float:
	var s := 0.0
	for o in roster.parties:
		if o != p and o.fac == p.fac and not o.hide and not o.get("fight") and not o.get("army", false) and o.kind != "caravan" and o.kind != "camp" and Vector2(o.x - p.x, o.y - p.y).length() < 150.0:
			s += roster.strength_of(o) * 0.85
	return s

## Neighbours of the same side go after the same target.
func rally(p: Dictionary, tgt: Dictionary) -> void:
	for o in roster.parties:
		if o == p or o.fac != p.fac or o.hide or o.get("fight") or o.get("army", false) or o.kind == "caravan" or o.kind == "camp" or o.get("lock", false) or o.state == "hunt":
			continue
		if Vector2(o.x - p.x, o.y - p.y).length() > 160.0:
			continue
		o.state = "hunt"
		o.tid = tgt.id
		o.tpl = false
		roster.path_to(o, tgt.x, tgt.y)

# ---------- allies of the enemy in the player's battle ----------

func helpers(player, enemy: Dictionary) -> Array:
	if enemy.kind in ["camp", "siege", "caravan"]:
		return []
	var out: Array = []
	for o in roster.parties:
		if o == enemy or o.hide or o.get("fight") or o.get("lock", false) or o.kind in ["camp", "siege", "caravan"] or o.fac != enemy.fac:
			continue
		if not Rules.hostile_to_player(o, player.rel):
			continue
		if minf(Vector2(o.x - enemy.x, o.y - enemy.y).length(), Vector2(o.x - player.x, o.y - player.y).length()) < HELP_RADIUS:
			out.append(o)
	return out

## Before the battle the allies pour into the enemy party and leave the map (encMerge).
func merge(enemy: Dictionary, help: Array) -> void:
	help = help.filter(func(h): return h in roster.parties and not h.get("fight"))
	if help.is_empty():
		return
	enemy.help = [{"own": true, "n": Rules.troop_count(enemy.troops)}]
	for h in help:
		enemy.help.append({"h": h, "n": Rules.troop_count(h.troops)})
		for t in h.troops:
			Rules.add_troops(enemy.troops, t.type, int(t.n))
		roster.parties.erase(h)

## After the battle the survivors go back in proportion to what each brought (encSplit).
func split(enemy: Dictionary) -> void:
	if not enemy.has("help"):
		return
	var hp: Array = enemy.help
	enemy.erase("help")
	if not enemy in roster.parties:
		return # the enemy was routed: the allies fell with it
	var tot := 0
	for x in hp:
		tot += int(x.n)
	tot = maxi(1, tot)
	var left: Array = enemy.troops.duplicate(true)
	for x in hp:
		if x.get("own", false):
			continue
		var f := float(x.n) / tot
		var mine: Array = []
		for t in left:
			var k := mini(int(t.n), roundi(t.n * f))
			if k > 0:
				mine.append({"type": t.type, "n": k})
				Rules.remove_troops(enemy.troops, t.type, k)
		if Rules.troop_count(mine) > 0:
			var h: Dictionary = x.h
			h.troops = mine
			h.fight = null
			h.state = "idle"
			h.path = []
			h.pi = 0
			h.cd = 10.0
			h.lock = false
			roster.parties.append(h)
	if Rules.troop_count(enemy.troops) == 0:
		Rules.add_troops(enemy.troops, left[0].type if not left.is_empty() else "n1", 1)

func to_dict() -> Dictionary:
	return {"fights": fights.duplicate(true), "next_id": next_id}

func from_dict(d: Dictionary) -> void:
	fights = []
	for sk in d.get("fights", []):
		var x: Dictionary = sk.duplicate(true)
		for k in ["id", "t0", "a0", "b0"]:
			x[k] = int(x[k])
		x.A = x.A.map(func(i): return int(i))
		x.B = x.B.map(func(i): return int(i))
		fights.append(x)
	next_id = int(d.get("next_id", next_id))
