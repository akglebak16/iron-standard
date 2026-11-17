extends RefCounted
## Director of the undead invasion (docs/modules/ai/DESIGN.md §5.5, stage 2c). Every barrow sends one wave: its armies
## (parties of kind "dead" with src = the barrow). The director picks where the wave strikes, decides when it gathers
## and when it attacks, and when the armies at the walls storm together. world_undead.gd carries it out every hour; the
## armies and raids follow it through their goals (party_goals.gd: muster, assault, raid ahead of the wave).
##
## - Target: a living town or castle, near the wave and weak against it (garrison, lords inside and, through the threat
##   map, living armies around it), worth more with living villages around it for the raids. The wave keeps its target
##   until it falls, is lost or a clearly better one turns up while gathering (UNDEAD_RETARGET_HOURS, UNDEAD_SWITCH_MARGIN).
## - Gather: the armies meet at a rally point short of the target and attack once they are clearly stronger than the
##   walls, or after waiting long enough; the dead never retreat for good.
## - Storm: the armies at the walls storm together once most of the wave is there, or after UNDEAD_STORM_WAIT hours.
##
## The evaluator only reads what comes in through its fields and arguments and spends no RNG, so it runs on synthetic
## data. Numbers are UNDEAD_* in core/campaign/config.gd.
const Config = preload("res://core/campaign/config.gd")

var strength: Callable  # (party) -> float
var defence: Callable   # (settlement) -> float: what a storm must beat (garrison and lords inside, times the walls)
var field: Callable = Callable()    # (x, y, faction) -> strength of that faction's armies around (threat map), optional
var passable: Callable = Callable() # (Vector2) -> bool, for rally points, optional
var width := 5200.0
var height := 3400.0

static func _dist(a, b) -> float:
	return Vector2(float(a.x) - float(b.x), float(a.y) - float(b.y)).length()

func _strength(p: Dictionary) -> float:
	return float(strength.call(p)) if strength.is_valid() else 0.0

## Total strength of armies.
func total(armies: Array) -> float:
	var s := 0.0
	for p in armies:
		s += _strength(p)
	return s

## Where the wave stands: the centre of its armies, else its barrow.
static func centre(armies: Array, barrow: Dictionary) -> Vector2:
	if armies.is_empty():
		return Vector2(float(barrow.get("x", 0.0)), float(barrow.get("y", 0.0)))
	var c := Vector2.ZERO
	for p in armies:
		c += Vector2(float(p.x), float(p.y))
	return c / armies.size()

## Settlements of the living the dead strike at: towns and castles not held by the dead.
static func is_target(s: Dictionary) -> bool:
	return Config.UNDEAD_TARGET_WORTH.has(String(s.get("kind", ""))) and String(s.get("fac", "")) != Config.UNDEAD_FACTION

## Strength a storm of `s` has to beat.
func storm_defence(s: Dictionary) -> float:
	return float(defence.call(s)) if defence.is_valid() else 0.0

## Storm defence plus a share of the living armies around the target.
func full_defence(s: Dictionary) -> float:
	var d := storm_defence(s)
	if field.is_valid():
		d += Config.UNDEAD_FIELD_SHARE * float(field.call(float(s.x), float(s.y), String(s.fac)))
	return d

## Score of a target for a wave of strength `power` standing at `from` (higher is better, 0 = never).
func score(s: Dictionary, from: Vector2, power: float, settles: Array) -> float:
	if not is_target(s):
		return 0.0
	var d := from.distance_to(Vector2(float(s.x), float(s.y)))
	var near := 1.0 - Config.UNDEAD_DISTANCE_FALLOFF * clampf(d / Config.UNDEAD_TARGET_RANGE, 0.0, 1.0)
	var k := full_defence(s) / maxf(1.0, power)
	var x := clampf((k - Config.UNDEAD_WEAK_RATIO.x) / (Config.UNDEAD_WEAK_RATIO.y - Config.UNDEAD_WEAK_RATIO.x), 0.0, 1.0)
	var weak := lerpf(1.0, Config.UNDEAD_WEAK_FLOOR, x)
	var villages := 0
	for v in settles:
		if v.get("kind") != Config.SETTLEMENT_VILLAGE or String(v.get("fac", "")) == Config.UNDEAD_FACTION or int(v.get("burnt", 0)) > 0:
			continue
		if _dist(v, s) < Config.UNDEAD_VILLAGE_RADIUS:
			villages += 1
	var prey := 1.0 + minf(Config.UNDEAD_VILLAGE_BONUS_MAX, villages * Config.UNDEAD_VILLAGE_BONUS)
	return float(Config.UNDEAD_TARGET_WORTH[String(s.kind)]) * near * weak * prey

## Best target for a wave: {s, score} or {} when the living hold no town or castle. `banned`: ids the wave cannot
## reach. Equal scores go to the lower id.
func best_target(from: Vector2, power: float, settles: Array, banned: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 0.0
	for s in settles:
		if int(s.id) in banned:
			continue
		var v := score(s, from, power, settles)
		if v > best_score or (v == best_score and v > 0.0 and not best.is_empty() and int(s.id) < int(best.s.id)):
			best = {"s": s, "score": v}
			best_score = v
	return best

## Whether a gathering wave takes `cand` instead of its current target: the current one is no target any more, or the
## candidate scores UNDEAD_SWITCH_MARGIN better.
static func switch(current: Dictionary, current_score: float, cand: Dictionary) -> bool:
	if cand.is_empty():
		return false
	if current.is_empty() or not is_target(current):
		return true
	if int(cand.s.id) == int(current.id):
		return false
	return float(cand.score) > current_score * (1.0 + Config.UNDEAD_SWITCH_MARGIN)

## Rally point short of the target `t`, on the side of `from`, on passable ground when `passable` is given.
func rally_point(from: Vector2, t: Dictionary) -> Vector2:
	var at := Vector2(float(t.x), float(t.y))
	var dir := from - at
	if dir.length() < 1.0:
		dir = Vector2(0.0, 1.0)
	dir = dir.normalized()
	var margin := Config.GOAL_MAP_MARGIN
	var first := Vector2.INF
	for k in [1.0, 0.75, 1.25, 0.5, 1.5]:
		var r: Vector2 = at + dir * Config.UNDEAD_RALLY_DISTANCE * float(k)
		r = Vector2(clampf(r.x, margin, width - margin), clampf(r.y, margin, height - margin))
		if first == Vector2.INF:
			first = r
		if not passable.is_valid() or bool(passable.call(r)):
			return r
	return first

## Armies of the wave that have gathered: by the rally point or already by the target's walls.
static func gathered(armies: Array, rally: Vector2, t: Dictionary) -> Array:
	var out: Array = []
	for p in armies:
		if Vector2(float(p.x), float(p.y)).distance_to(rally) <= Config.UNDEAD_RALLY_RADIUS:
			out.append(p)
		elif not t.is_empty() and _dist(p, t) <= Config.UNDEAD_STORM_RADIUS:
			out.append(p)
	return out

## Gather or attack: never before UNDEAD_MIN_GATHER_HOURS of gathering (the living hear where the dead go and shut
## themselves in); then "attack" when the gathered armies clearly outmatch the walls, or all gathered and waited
## UNDEAD_GATHER_HOURS with at least UNDEAD_ATTACK_MIN of the defence, or waited twice that long; an attacking wave
## worn below UNDEAD_FALLBACK_SHARE gathers again. `waited`: hours since the wave began to gather.
func mode(current: String, armies: Array, rally: Vector2, t: Dictionary, waited: float) -> String:
	if armies.is_empty() or t.is_empty():
		return "gather"
	var need := storm_defence(t)
	if current == "attack":
		return "gather" if total(armies) < need * Config.UNDEAD_FALLBACK_SHARE else "attack"
	if waited < Config.UNDEAD_MIN_GATHER_HOURS:
		return "gather"
	var here := gathered(armies, rally, t)
	var power := total(here)
	if power >= need * Config.UNDEAD_ATTACK_MARGIN:
		return "attack"
	var all_in := here.size() == armies.size()
	if all_in and waited >= Config.UNDEAD_GATHER_HOURS and power >= need * Config.UNDEAD_ATTACK_MIN:
		return "attack"
	if all_in and waited >= Config.UNDEAD_GATHER_HOURS * 2:
		return "attack"
	return "gather"

## Armies by the walls of `t`.
static func at_walls(armies: Array, t: Dictionary) -> Array:
	return armies.filter(func(p): return _dist(p, t) <= Config.UNDEAD_STORM_RADIUS)

## Whether the armies at the walls storm now: most of the attacking strength is there, or they waited long enough.
func storm_ready(armies: Array, t: Dictionary, waited: float) -> bool:
	var here := at_walls(armies, t)
	if here.is_empty():
		return false
	return total(here) >= total(armies) * Config.UNDEAD_STORM_SHARE or waited >= Config.UNDEAD_STORM_WAIT
