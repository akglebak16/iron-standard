extends RefCounted
## Operations of a faction on the campaign map (docs/modules/ai/DESIGN.md §5.3, stage 2b): who leads a campaign, who
## stays home, who relieves an own besieged settlement and when a campaign is called off. world_wars.gd carries the
## operations out; this evaluator only reads parties and settlements passed to it and spends no RNG, so it runs on
## synthetic data. Numbers are OP_* in core/campaign/config.gd.
##
## - Offensive campaign: led by a marshal, the strongest lord of the host; the others muster and march around him.
## - Defenders: part of the lords stays home, one per own town or castle under siege or with enemies around it on the
##   threat map, plus one while the faction is at war; never more than half of the free lords.
## - Defensive operation: relief of an own besieged settlement, the nearest lords until they clearly outmatch the besiegers.
## - Retreat: the host fell below a share of its strength at the muster, or an own besieged settlement near the marshal
##   is worth more than the target.
const Config = preload("res://core/campaign/config.gd")

var strength: Callable  # (party) -> float

## Worth of a settlement for the operations: what its loss or capture means to a faction.
static func value(s: Dictionary) -> float:
	return float(Config.OP_VALUE.get(String(s.get("kind", "")), 0.0))

static func _dist(a: Dictionary, b: Dictionary) -> float:
	return Vector2(float(a.x) - float(b.x), float(a.y) - float(b.y)).length()

func _strength(p: Dictionary) -> float:
	return float(strength.call(p)) if strength.is_valid() else 0.0

## Total strength of parties.
func total(parties: Array) -> float:
	var s := 0.0
	for p in parties:
		s += _strength(p)
	return s

## The marshal: the strongest lord of the host (a faction vassal only when no lord is in it); equal strength goes to
## the older party (lower id).
func marshal_of(host: Array) -> Dictionary:
	var lords := host.filter(func(p): return p.get("kind") == Config.LORD_KIND)
	var best: Dictionary = {}
	var best_s := -1.0
	for p in (lords if not lords.is_empty() else host):
		var s := _strength(p)
		if s > best_s or (s == best_s and not best.is_empty() and int(p.id) < int(best.id)):
			best = p
			best_s = s
	return best

## Own towns and castles that need a defender: besieged ones, and those with enemy strength `threat` around them
## (threat: (x, y, faction) -> enemy strength on the threat map). Most urgent first: besieged, then by threat × worth.
func alerts(f: String, settles: Array, threat: Callable) -> Array:
	var out: Array = []
	for s in settles:
		if s.fac != f or (s.kind != Config.SETTLEMENT_TOWN and s.kind != Config.SETTLEMENT_CASTLE):
			continue
		var besieged: bool = s.get("siege") != null and String(s.siege.get("f", "")) != f
		var enemy := float(threat.call(s.x, s.y, f)) if threat.is_valid() else 0.0
		if besieged or enemy >= Config.OP_HOME_THREAT:
			out.append({"s": s, "threat": enemy, "besieged": besieged, "urgency": (1e9 if besieged else 0.0) + enemy * value(s)})
	out.sort_custom(func(a, b): return float(a.urgency) > float(b.urgency) or (float(a.urgency) == float(b.urgency) and int(a.s.id) < int(b.s.id)))
	return out

## How many of `free_n` lords free for a campaign stay home.
static func keep_count(free_n: int, alert_n: int) -> int:
	if free_n <= 1:
		return 0
	var want := alert_n + (Config.OP_KEEP_BASE if free_n >= Config.OP_KEEP_MIN_LORDS else 0)
	return mini(want, floori(free_n * Config.OP_KEEP_MAX_SHARE))

## Splits the free lords into the host and those who stay home: {army, keep, marshal}. The marshal always goes; the
## nearest lord stays by each alerted settlement, the remaining places at home go to the weakest lords.
func split(lords: Array, alert_list: Array) -> Dictionary:
	if lords.is_empty():
		return {"army": [], "keep": [], "marshal": {}}
	var marshal := marshal_of(lords)
	var n := keep_count(lords.size(), alert_list.size())
	var rest: Array = lords.filter(func(p): return p != marshal)
	var keep: Array = []
	for a in alert_list:
		if keep.size() >= n or rest.is_empty():
			break
		var s: Dictionary = a.s
		var best: Dictionary = {}
		for p in rest:
			if best.is_empty() or _dist(p, s) < _dist(best, s) or (_dist(p, s) == _dist(best, s) and int(p.id) < int(best.id)):
				best = p
		keep.append(best)
		rest.erase(best)
	if keep.size() < n:
		rest.sort_custom(func(a, b): return _strength(a) < _strength(b) or (_strength(a) == _strength(b) and int(a.id) < int(b.id)))
		while keep.size() < n and not rest.is_empty():
			keep.append(rest.pop_front())
	var army: Array = lords.filter(func(p): return not p in keep)
	return {"army": army, "keep": keep, "marshal": marshal}

## Relief host for an own besieged settlement `s`: candidates are taken nearest first until they, with 0.3 of the
## garrison, are OP_RELIEF_MARGIN times the besiegers' strength (at most OP_RELIEF_MAX_LORDS). An empty list when even
## the whole host would be weaker than OP_RELIEF_MIN_RATIO of the besiegers: relief is not thrown away.
func relief_host(cands: Array, s: Dictionary, besiegers: float, garrison: float) -> Array:
	var sorted := cands.duplicate()
	sorted.sort_custom(func(a, b): return _dist(a, s) < _dist(b, s) or (_dist(a, s) == _dist(b, s) and int(a.id) < int(b.id)))
	var host: Array = []
	var r := 0.3 * garrison
	for p in sorted:
		if host.size() >= Config.OP_RELIEF_MAX_LORDS or r >= besiegers * Config.OP_RELIEF_MARGIN:
			break
		host.append(p)
		r += _strength(p)
	if host.is_empty() or r < besiegers * Config.OP_RELIEF_MIN_RATIO:
		return []
	return host

## Whether a campaign has to end because its host is too weak: below OP_RETREAT_SHARE of its strength at the muster.
static func weak(start_strength: float, now_strength: float) -> bool:
	return start_strength > 0.0 and now_strength < start_strength * Config.OP_RETREAT_SHARE

## An own besieged settlement that recalls the host of a campaign against `target`: worth more than the target
## (OP_HOME_WEIGHT), within OP_RECALL_RANGE of the marshal, most valuable then nearest. Settlements the lords at home
## relieve or can relieve themselves (`covered`: (settlement) -> bool) do not recall it: then the offensive and the
## defensive operation go on side by side. {} when there is none or the faction already runs a defensive operation
## (`relief_busy`).
func recall(f: String, settles: Array, marshal: Dictionary, target: Dictionary, relief_busy: bool, covered := Callable()) -> Dictionary:
	if relief_busy or marshal.is_empty():
		return {}
	var best: Dictionary = {}
	for s in settles:
		if s.fac != f or s.get("siege") == null or String(s.siege.get("f", "")) == f:
			continue
		if covered.is_valid() and bool(covered.call(s)):
			continue
		if value(s) * Config.OP_HOME_WEIGHT <= value(target) or _dist(marshal, s) > Config.OP_RECALL_RANGE:
			continue
		if best.is_empty() or value(s) > value(best) or (value(s) == value(best) and _dist(marshal, s) < _dist(marshal, best)):
			best = s
	return best
