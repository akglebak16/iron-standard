extends RefCounted
## Taverns: free companions wander between towns, can be hired and fired; they heal, draw wages and may leave unpaid
## (src/05e_comps.js: compsInit, compsAt, compsDay, compRumor, doCompHire, doCompFire, compsHeal, compsUnpaid, compWage, compStr).
const CompanionCatalog = preload("res://characters/data/companion_catalog.gd")

const COMP_MAX := 5
const COMP_FIT := 0.25

signal message(text: String)

var map: RefCounted
var catalog: CompanionCatalog
var rng: RandomNumberGenerator
var pos: Dictionary = {}    # companion id -> settlement id (cpos)
var saved: Dictionary = {}  # companion id -> profile of a companion who left the party (cstate)

func _init(world_map: RefCounted, companions: CompanionCatalog, random: RandomNumberGenerator) -> void:
	map = world_map
	catalog = companions
	rng = random

static func hash_str(s: String) -> int:
	var h := 2166136261
	for i in s.length():
		h = (h ^ s.unicode_at(i)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h

func new_profile(id: String) -> Dictionary:
	var d := catalog.get_companion(id)
	var a: Array = d.a
	return {"id": id, "name": d.name, "lvl": 1, "xp": 0, "str": a[0], "vit": a[1], "agi": a[2], "int": a[3], "cha": a[4], "pts": 0, "pp": 0,
		"perks": d.perks.duplicate(), "eq": d.eq.duplicate(), "sel": d.sel, "hp": 1.0, "seed": hash_str(id) % 99999 + 1,
		"beard": d.get("beard", 1), "hair": d.get("hair")}

func towns() -> Array:
	return map.settles.filter(func(s): return s.kind == "town" and s.fac != "bandit")

static func hired(p, id: String) -> bool:
	for c in p.comps:
		if c.id == id:
			return true
	for v in p.get("vass") if p.get("vass") != null else []:
		if v.cid == id:
			return true
	return false

func fixed_town(d: Dictionary) -> Dictionary:
	var all := towns()
	for s in all:
		if s.name == d.fixed:
			return s
	var x: float = map.terrain.eu_x(26.85)
	var y: float = map.terrain.eu_y(54.88)
	all.sort_custom(func(a, b): return Vector2(a.x - x, a.y - y).length() < Vector2(b.x - x, b.y - y).length())
	return all[0] if not all.is_empty() else {}

func place(id: String, avoid := -1) -> void:
	var all := towns()
	if all.is_empty():
		return
	var d := catalog.get_companion(id)
	if d.get("fixed", "") != "":
		var t := fixed_town(d)
		if not t.is_empty():
			pos[id] = t.id
			return
	var busy := {}
	for k in pos:
		busy[pos[k]] = true
	var home := all.filter(func(s): return String(s.get("cult", s.fac)) == d.fac and s.id != avoid and not busy.has(s.id))
	var free := all.filter(func(s): return s.id != avoid and not busy.has(s.id))
	var from: Array = home if not home.is_empty() and rng.randf() < 0.6 else (free if not free.is_empty() else all)
	pos[id] = from[rng.randi_range(0, from.size() - 1)].id

func ensure(p) -> void:
	for id in catalog.ids():
		if hired(p, id):
			continue
		if not pos.has(id) or map.settlement_by_id(pos[id]).is_empty():
			place(id)

## Free companions sitting in this town's tavern.
func at(p, s: Dictionary) -> Array:
	ensure(p)
	var out: Array = []
	for id in catalog.ids():
		if pos.get(id, -1) == s.id and not hired(p, id):
			out.append(saved.get(id, new_profile(id)))
	return out

## Every 4 days half of the wanderers move to another town.
func day(p, day_n: int) -> void:
	ensure(p)
	if day_n % 4 != 0:
		return
	for id in catalog.ids():
		if catalog.get_companion(id).get("fixed", "") == "" and not hired(p, id) and rng.randf() < 0.5:
			var was: int = pos.get(id, -1)
			pos.erase(id)
			place(id, was)

## The nearest free companion in another town, for the innkeeper's rumour.
func rumor(p, s: Dictionary) -> Dictionary:
	ensure(p)
	var best := {}
	var bd := 1e9
	for id in catalog.ids():
		var sid: int = pos.get(id, -1)
		if sid < 0 or sid == s.id or hired(p, id):
			continue
		var t: Dictionary = map.settlement_by_id(sid)
		if t.is_empty():
			continue
		var d := Vector2(t.x - s.x, t.y - s.y).length()
		if d < bd:
			bd = d
			best = {"c": catalog.get_companion(id), "t": t}
	return best

## "" on success, otherwise the reason.
func hire(p, s: Dictionary, id: String) -> String:
	ensure(p)
	var d := catalog.get_companion(id)
	if d.is_empty() or pos.get(id, -1) != s.id or hired(p, id):
		return "Этого человека здесь уже нет."
	if p.comps.size() >= COMP_MAX:
		return "Больше %d спутников в отряде не уживутся." % COMP_MAX
	if p.gold < int(d.price):
		return "Не хватает золота."
	p.gold -= int(d.price)
	var c: Dictionary = saved.get(id, new_profile(id))
	saved.erase(id)
	pos.erase(id)
	p.comps.append(c)
	message.emit("%s присоединяется к отряду." % c.name)
	return ""

func fire(p, id: String, why := " уходит из отряда") -> bool:
	var c := {}
	for x in p.comps:
		if x.id == id:
			c = x
	if c.is_empty():
		return false
	p.comps.erase(c)
	saved[id] = c
	var d := catalog.get_companion(id)
	var near := {}
	if d.get("fixed", "") != "":
		near = fixed_town(d)
	else:
		var all := towns()
		all.sort_custom(func(a, b): return Vector2(a.x - p.x, a.y - p.y).length() < Vector2(b.x - p.x, b.y - p.y).length())
		if not all.is_empty():
			near = all[0]
	if not near.is_empty():
		pos[id] = near.id
	message.emit("%s%s%s." % [c.name, why, (" и будет ждать в таверне " + near.name) if not near.is_empty() else ""])
	return true

func wage(p) -> int:
	var w := 0
	for c in p.comps:
		w += int(catalog.get_companion(c.id).get("wage", 0))
	return w

static func fit(c: Dictionary) -> bool:
	return float(c.get("hp", 1.0)) >= COMP_FIT

static func heal(p, amount: float) -> void:
	for c in p.comps:
		c.hp = minf(1.0, float(c.get("hp", 1.0)) + amount)

func unpaid(p) -> void:
	if p.comps.is_empty() or rng.randf() > 0.25:
		return
	fire(p, p.comps[rng.randi_range(0, p.comps.size() - 1)].id, " ушёл: жалованье не плачено,")

## Strength the companions add to a calculated battle (compStr).
static func strength(p) -> float:
	var s := 0.0
	for c in p.comps:
		if fit(c):
			s += (8.0 + float(c.get("lvl", 1)) * 0.8) * (1.35 if c.get("eq", {}).get("horse") != null else 1.0)
	return s

## Calculated battle: fit companions lose health like the hero (compsAuto).
func auto_outcomes(p, win: bool) -> Dictionary:
	var out := {}
	for c in p.comps:
		if fit(c):
			out[c.id] = {"hp": clampf(float(c.hp) - (rng.randf_range(0.05, 0.35) if win else rng.randf_range(0.35, 0.6)), 0.0, 1.0), "down": false, "kills": 0}
	return out

func to_dict() -> Dictionary:
	return {"pos": pos.duplicate(), "saved": saved.duplicate(true)}

func from_dict(d: Dictionary) -> void:
	pos = {}
	for k in d.get("pos", {}):
		pos[k] = int(d.pos[k])
	saved = d.get("saved", {}).duplicate(true)
