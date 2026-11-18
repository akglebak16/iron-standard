extends RefCounted
## «Метание ножей» in a town tavern (#215): a small bet against a regular, three throws each at a ringed target.
## Pure rules, no nodes: scoring by rings, the stake, payouts, the daily limit per tavern, the regular's skill and
## throws, the sway of the player's aim by agility. Coordinates are in target radii: (0, 0) is the bull, 1 the rim.
const STAKES := [5, 10, 25]
const GAMES_PER_DAY := 3
const THROWS := 3
## [outer radius, points] from the bull outwards; past the last ring the knife misses.
const RINGS := [[0.15, 10], [0.35, 7], [0.55, 5], [0.75, 3], [1.0, 1]]
## Spread of the regular's throws by level 1..3 (σ in radii).
const REGULAR_SPREAD := [0.42, 0.32, 0.24]
const REGULAR_NAMES := ["подвыпивший возчик", "старый наёмник", "местный ловкач"]
## The hand still trembles after the aim: σ in radii.
const HAND_JITTER := 0.05

static func score(at: Vector2) -> int:
	var r := at.length()
	for ring in RINGS:
		if r <= float(ring[0]):
			return int(ring[1])
	return 0

## Games already played today in this tavern (kept on the settlement as `knife` = [day, games]; old saves have none).
static func played(s: Dictionary, day: int) -> int:
	var k: Variant = s.get("knife")
	if k is Array and k.size() == 2 and int(k[0]) == day:
		return int(k[1])
	return 0

static func games_left(s: Dictionary, day: int) -> int:
	return maxi(0, GAMES_PER_DAY - played(s, day))

## "" when a game for `stake` can start, otherwise why not.
static func why_not(gold: int, s: Dictionary, day: int, stake: int) -> String:
	if not stake in STAKES:
		return "Такой ставки здесь не принимают."
	if games_left(s, day) <= 0:
		return "На сегодня хватит: завсегдатаи больше не играют. Приходи завтра."
	if gold < stake:
		return "Не хватает золота на ставку: нужно %d." % stake
	return ""

## Takes the stake and counts the game; returns false (and changes nothing) when it cannot start.
static func start(p, s: Dictionary, day: int, stake: int) -> bool:
	if why_not(int(p.gold), s, day, stake) != "":
		return false
	p.gold -= stake
	s.knife = [day, played(s, day) + 1]
	return true

## Pays out after the throws: a win returns the stake twice, a tie returns it; returns the net result for the player.
static func settle(p, stake: int, mine: int, theirs: int) -> int:
	if mine > theirs:
		p.gold += stake * 2
		return stake
	if mine == theirs:
		p.gold += stake
		return 0
	return -stake

static func total(throws: Array) -> int:
	var sum := 0
	for t in throws:
		sum += score(t)
	return sum

## The regular of this tavern: 1..3, stable for the town.
static func regular_level(s: Dictionary) -> int:
	return 1 + absi(int(s.get("id", 0)) * 7 + 3) % 3

static func regular_name(s: Dictionary) -> String:
	return REGULAR_NAMES[regular_level(s) - 1]

## A seeded generator for one game: the same town, day and game give the same throws.
static func rng_for(world_seed: int, s: Dictionary, day: int, game: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, int(s.get("id", 0)), day, game, "knives"])
	return rng

static func regular_throw(rng: RandomNumberGenerator, level: int) -> Vector2:
	var sigma: float = REGULAR_SPREAD[clampi(level, 1, 3) - 1]
	return Vector2(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma))

## How far the aim sways (radii): less with agility, never steady.
static func sway(agility: int) -> float:
	return clampf(0.62 - 0.05 * float(agility), 0.2, 0.62)

## The aim at time `t` (seconds): a slow Lissajous figure of size `amp`.
static func aim(t: float, amp: float) -> Vector2:
	return Vector2(amp * sin(1.9 * t + 0.6), amp * sin(2.7 * t))

## Where the player's knife lands when thrown at `aim_point`.
static func player_throw(rng: RandomNumberGenerator, aim_point: Vector2) -> Vector2:
	return aim_point + Vector2(rng.randfn(0.0, HAND_JITTER), rng.randfn(0.0, HAND_JITTER))
