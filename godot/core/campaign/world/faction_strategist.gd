extends RefCounted
## Strategist of a faction (docs/modules/ai/DESIGN.md §5.4, stage 2d): when a state goes to war with a neighbour and
## when it makes peace, by gain and war weariness instead of a bare die roll. world_wars.gd keeps the weariness, the war
## gains and the truces, rolls the small remaining noise and carries the decisions out; this evaluator only reads the
## day summaries passed to it and spends no RNG, so it runs on synthetic data. Numbers are STRAT_* in config.gd.
##
## A day summary of a living state (world_wars.strategy_day): {power, wars (count), weary, strain (missing share of the
## lords' full armies, 0..1), war_k and peace_k (the ruler's trait), core: [{x, y, kind}] own towns and castles}.
##
## - War: a weaker neighbour (power edge), something worth taking within reach (towns and castles near own ones), no
##   second front (a state at war wants another war much less, two wars never), not too weary; the ruler's trait is a
##   multiplier. The daily chance of a declaration is STRAT_WAR_RATE × will.
## - Peace: both sides must want it. Weariness (days of war, lost lords and settlements) and thin armies pull to peace,
##   so does losing this war, being the weaker side, fighting on more fronts, and for the winner having taken what it
##   wanted. The ruler's trait is a multiplier.
const Config = preload("res://core/campaign/config.gd")

## Worth of a town or castle as a prize of war; villages follow their town.
static func worth(kind: String) -> float:
	return float(Config.STRAT_PRIZE_WORTH.get(kind, 0.0))

## What a state could take from a neighbour: worth of the neighbour's towns and castles within STRAT_PRIZE_REACH of
## its own towns and castles.
static func prize(own_core: Array, foe_core: Array) -> float:
	var reach2 := Config.STRAT_PRIZE_REACH * Config.STRAT_PRIZE_REACH
	var total := 0.0
	for t in foe_core:
		for s in own_core:
			var dx := float(s.x) - float(t.x)
			var dy := float(s.y) - float(t.y)
			if dx * dx + dy * dy <= reach2:
				total += worth(String(t.kind))
				break
	return total

static func _ramp(v: float, range_v: Vector2) -> float:
	return clampf((v - range_v.x) / maxf(0.0001, range_v.y - range_v.x), 0.0, 1.0)

## Will of `me` to start a war with neighbour `foe`, 0..(ruler trait); `gain` is prize(me.core, foe.core).
static func war_will(me: Dictionary, foe: Dictionary, gain: float) -> float:
	var wars := int(me.get("wars", 0))
	if wars >= Config.STRAT_MAX_WARS or int(foe.get("wars", 0)) >= Config.STRAT_FOE_MAX_WARS:
		return 0.0
	var edge := _ramp(float(me.power) / maxf(1.0, float(foe.power)), Config.STRAT_POWER_EDGE)
	var loot := clampf(gain / Config.STRAT_PRIZE_FULL, 0.0, 1.0)
	var fresh := clampf(1.0 - float(me.get("weary", 0.0)) / Config.STRAT_WEARY_WAR, 0.0, 1.0)
	var front := 1.0 if wars == 0 else Config.STRAT_SECOND_FRONT
	return edge * loot * fresh * front * float(me.get("war_k", 1.0))

## Daily chance that one of the two neighbours declares war on the other, and who would: {chance, by} with by 0 for
## `a`, 1 for `b`. The side with the stronger will declares; equal will goes to `a`.
static func declaration(a: Dictionary, b: Dictionary) -> Dictionary:
	var wa := war_will(a, b, prize(a.core, b.core))
	var wb := war_will(b, a, prize(b.core, a.core))
	var will := maxf(wa, wb)
	return {"chance": Config.STRAT_WAR_RATE * will, "by": 0 if wa >= wb else 1, "will": will}

## Will of `me` to end its war with `foe`. `took` and `lost` are the worth of towns and castles it took from `foe` and
## lost to it in this war.
static func peace_will(me: Dictionary, foe: Dictionary, took: float, lost: float) -> float:
	var tired := float(me.get("weary", 0.0)) + Config.STRAT_STRAIN * clampf(float(me.get("strain", 0.0)), 0.0, 1.0)
	var losing := clampf((lost - took) * Config.STRAT_LOSING, 0.0, Config.STRAT_LOSING_MAX)
	var content := Config.STRAT_CONTENT * clampf((took - lost) / Config.STRAT_WAR_AIM, 0.0, 1.0)
	var weaker := clampf((float(foe.power) / maxf(1.0, float(me.power)) - Config.STRAT_WEAKER_FROM) * Config.STRAT_WEAKER, 0.0, Config.STRAT_WEAKER)
	var fronts := Config.STRAT_FRONTS * maxf(0.0, float(int(me.get("wars", 1)) - 1))
	return (tired + losing + content + weaker + fronts) * float(me.get("peace_k", 1.0))

## Daily chance that a war of `days` ends in peace: none until both sides want it at least STRAT_PEACE_AT, then from
## STRAT_PEACE_CHANCE.x up to .y as the lesser will rises STRAT_PEACE_SPAN above it. `gain` is the war's {faction: worth
## taken from the other side}. A chance rather than a bare threshold, so wars that grew ripe together end one by one.
static func peace_chance(a: Dictionary, b: Dictionary, fa: String, fb: String, gain: Dictionary, days: int) -> float:
	if days < Config.STRAT_MIN_WAR_DAYS:
		return 0.0
	var ta := float(gain.get(fa, 0.0))
	var tb := float(gain.get(fb, 0.0))
	var will := minf(peace_will(a, b, ta, tb), peace_will(b, a, tb, ta))
	if will < Config.STRAT_PEACE_AT:
		return 0.0
	var ripe := clampf((will - Config.STRAT_PEACE_AT) / Config.STRAT_PEACE_SPAN, 0.0, 1.0)
	return lerpf(Config.STRAT_PEACE_CHANCE.x, Config.STRAT_PEACE_CHANCE.y, ripe)
