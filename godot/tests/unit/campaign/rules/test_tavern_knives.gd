extends SceneTree
## «Метание ножей» rules (core/campaign/rules/tavern_knives.gd, #215): rings, stakes, payouts, the daily limit per
## tavern and its reset, the purse, agility and the seeded regular.
const Knives = preload("res://core/campaign/rules/tavern_knives.gd")

class Purse:
	var gold := 0

## A bot over many games: it waits until the aim (as seen, or as it will be when the knife lands with `lead`) comes
## within 0.08 of the bull, reacts after 0.17 s, and the knife lands Knives.FLIGHT later.
func _bot_throw(rng: RandomNumberGenerator, lead: bool, amp: float, phase: float) -> Vector2:
	var t := rng.randf_range(0.0, 5.0)
	var react := 0.0 if lead else 0.17
	for i in 600:
		var now := t + i * 0.01
		var seen := Knives.aim(now + (Knives.FLIGHT if lead else 0.0), amp, phase)
		if seen.length() < 0.08:
			return Knives.player_throw(rng, Knives.aim(now + react + Knives.FLIGHT, amp, phase))
	return Knives.player_throw(rng, Knives.aim(t + 6.0 + Knives.FLIGHT, amp, phase))

func _win_rate(lead: bool, agility: int, level: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2210 + int(lead)
	var wins := 0
	var games := 1200
	for g in games:
		var phase := Knives.aim_phase(rng)
		var mine: Array = []
		var theirs: Array = []
		for k in Knives.THROWS:
			mine.append(_bot_throw(rng, lead, Knives.sway(agility), phase))
			theirs.append(Knives.regular_throw(rng, level))
		if Knives.total(mine) > Knives.total(theirs):
			wins += 1
	return float(wins) / games

func _initialize() -> void:
	# rings: bull 10, then 7, 5, 3, 1, past the rim 0
	assert(Knives.score(Vector2.ZERO) == 10 and Knives.score(Vector2(0.1, 0.1)) == 10)
	assert(Knives.score(Vector2(0.3, 0)) == 7 and Knives.score(Vector2(0, -0.5)) == 5)
	assert(Knives.score(Vector2(0.7, 0)) == 3 and Knives.score(Vector2(0.99, 0)) == 1 and Knives.score(Vector2(1.01, 0)) == 0)
	assert(Knives.total([Vector2.ZERO, Vector2(0.3, 0), Vector2(2, 2)]) == 17)
	# a game takes the stake and counts; wins pay double, ties return, losses keep it
	var p := Purse.new()
	p.gold = 30
	var s := {"id": 4}
	assert(Knives.why_not(p.gold, s, 10, 7) != "", "only the house stakes")
	assert(Knives.start(p, s, 10, 25) and p.gold == 5 and Knives.played(s, 10) == 1)
	assert(Knives.settle(p, 25, 18, 12) == 25 and p.gold == 55, "a win returns the stake twice")
	assert(Knives.start(p, s, 10, 10) and Knives.settle(p, 10, 9, 9) == 0 and p.gold == 55, "a tie returns the stake")
	assert(Knives.start(p, s, 10, 5) and Knives.settle(p, 5, 3, 20) == -5 and p.gold == 50, "a loss keeps it")
	# three games a day in one tavern, a new day resets; never more than the purse
	assert(Knives.games_left(s, 10) == 0 and not Knives.start(p, s, 10, 5) and p.gold == 50)
	assert(Knives.why_not(p.gold, s, 10, 5).contains("Приходи завтра"))
	assert(Knives.games_left(s, 11) == 3 and Knives.games_left({"id": 9}, 10) == 3, "a new day or another tavern")
	p.gold = 4
	assert(Knives.why_not(p.gold, s, 11, 5).contains("Не хватает") and not Knives.start(p, s, 11, 5) and p.gold == 4)
	# the most a day can bring from one tavern stays small
	assert(Knives.STAKES.max() * Knives.GAMES_PER_DAY <= 75)
	# agility steadies the hand but never fully
	assert(Knives.sway(1) > Knives.sway(5) and Knives.sway(5) > Knives.sway(9) and Knives.sway(30) >= 0.3)
	for t in [0.0, 0.7, 3.3, 10.0]:
		assert(Knives.aim(t, 0.3, 1.2).length() <= 0.3 * sqrt(2.0) + 0.001)
	assert(Knives.aim(1.0, 0.4, 0.0) != Knives.aim(1.0, 0.4, 2.0), "each game sways its own way")
	# the regular: level 1..3 per town, the same throws for the same town, day and game
	for id in range(20):
		assert(Knives.regular_level({"id": id}) in [1, 2, 3])
	var a := Knives.rng_for(7, s, 3, 1)
	var b := Knives.rng_for(7, s, 3, 1)
	assert(Knives.regular_throw(a, 2) == Knives.regular_throw(b, 2))
	# a better regular lands closer on average
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var sums := [0, 0, 0]
	for level in [1, 2, 3]:
		for i in 400:
			sums[level - 1] += Knives.score(Knives.regular_throw(rng, level))
	assert(sums[0] < sums[1] and sums[1] < sums[2], "skill shows: %s" % [sums])
	assert(sums[2] / 400.0 * Knives.THROWS > 20.0, "the best regular scores over 20 in three throws: %s" % [sums[2] / 400.0 * Knives.THROWS])
	# #221: clicking when the aim crosses the bull no longer wins by itself; leading the knife does more often than not
	var naive := _win_rate(false, 5, 2)
	var lead := _win_rate(true, 5, 2)
	assert(naive < 0.5, "a click on the bull loses more often than not: %s" % naive)
	assert(lead > 0.5 and lead < 0.95, "a well-led throw wins more often but not always: %s" % lead)
	print("Tavern knives tests passed")
	quit()
