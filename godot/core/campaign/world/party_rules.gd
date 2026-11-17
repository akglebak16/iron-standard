extends RefCounted
## Pure helpers for map parties: strength, troop lists, hostility (strength/troopCount/addT/remT, hostile/WAR in src/01_core.js and src/05_world.js).

## Who fights whom by default (WAR in src/05_world.js); dynamic wars come in a later slice.
const WAR := {
	"nord": ["emp", "kin", "dom"], "emp": ["nord", "khan", "emi", "pact"], "khan": ["emp", "dom"],
	"kin": ["emi", "nord", "pact"], "emi": ["kin", "emp"], "dom": ["khan", "nord", "pact"],
	"pact": ["kin", "dom", "emp"],
	"bandit": ["nord", "emp", "khan", "kin", "emi", "dom", "pact"],
}
const REAL_FACTIONS := ["nord", "emp", "khan", "kin", "emi", "dom", "pact"]
const MK := 2.0  # single-player army multiplier (MASS in src/01_core.js)

static func troop_count(list: Array) -> int:
	var n := 0
	for s in list:
		n += int(s.n)
	return n

## info: {troop id: {tier, mounted, pw}}.
static func strength(list: Array, info: Dictionary) -> float:
	var total := 0.0
	for s in list:
		var d: Dictionary = info[s.type]
		var tier := float(d.tier)
		total += s.n * (tier * tier * 0.6 + 0.8) * (1.35 if d.mounted else 1.0) * float(d.get("pw", 1.0))
	return total

## The same strength with the per-type factors read once: `table` is troop id -> [tier part, mounted part, pw], made by
## strength_table(). The products keep their order, so the result is bit for bit the one of strength().
static func strength_cached(list: Array, table: Dictionary) -> float:
	var total := 0.0
	for s in list:
		var f: Array = table[s.type]
		total += s.n * f[0] * f[1] * f[2]
	return total

static func strength_table(info: Dictionary) -> Dictionary:
	var table := {}
	for id in info:
		var d: Dictionary = info[id]
		var tier := float(d.tier)
		table[id] = [tier * tier * 0.6 + 0.8, 1.35 if d.mounted else 1.0, float(d.get("pw", 1.0))]
	return table

static func add_troops(list: Array, type: String, n: int) -> void:
	for s in list:
		if s.type == type:
			s.n += n
			return
	list.append({"type": type, "n": n})

static func remove_troops(list: Array, type: String, n: int) -> void:
	for i in list.size():
		if list[i].type == type:
			list[i].n -= n
			if list[i].n <= 0:
				list.remove_at(i)
			return

static func war_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

## Context is explicit; null selects the historical default for standalone rules.
static func at_war(a: String, b: String, wars: Variant = null) -> bool:
	if a == "bandit" or b == "bandit":
		return WAR.has(a) and b in WAR[a]
	if wars != null:
		return wars.has(war_key(a, b))
	return WAR.has(a) and b in WAR[a]

## Whether two map parties fight each other when they meet (hostile() without caravan-vassals and undead).
static func hostile(a: Dictionary, b: Dictionary, wars: Variant = null, player_rel: Dictionary = {}) -> bool:
	if a.kind == "cvass" or b.kind == "cvass":
		var o: Dictionary = b if a.kind == "cvass" else a
		if o.fac == "player" or o.kind == "caravan":
			return false
		if o.fac == "undead" or o.kind == "bandit":
			return true
		return o.fac in REAL_FACTIONS and float(player_rel.get(o.fac, 0)) < -20.0
	if (a.fac == "undead") != (b.fac == "undead"):
		return true
	if a.fac == "undead":
		return false
	if a.kind == "caravan" and b.kind == "caravan":
		return false
	if a.kind == "bandit" and b.fac != "bandit":
		return true
	if b.kind == "bandit" and a.fac != "bandit":
		return true
	return a.fac != b.fac and at_war(a.fac, b.fac, wars) and a.kind != "caravan" and b.kind != "caravan"

static func hostile_to_player(p: Dictionary, rel: Dictionary) -> bool:
	if p.kind == "bandit" or p.kind == "camp" or p.fac == "undead":
		return true
	if p.kind == "caravan":
		return false
	return float(rel.get(p.fac, 0)) < -20.0

static func is_noble(p: Dictionary) -> bool:
	return p.kind == "lord" or p.kind == "vassal"
