extends SceneTree
## «Метание ножей» rules (core/campaign/rules/tavern_knives.gd, #215): rings, stakes, payouts, the daily limit per
## tavern and its reset, the purse, agility and the seeded regular.
const Knives = preload("res://core/campaign/rules/tavern_knives.gd")

class Purse:
	var gold := 0

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
	assert(Knives.sway(1) > Knives.sway(5) and Knives.sway(5) > Knives.sway(9) and Knives.sway(30) >= 0.2)
	for t in [0.0, 0.7, 3.3, 10.0]:
		assert(Knives.aim(t, 0.3).length() <= 0.3 * sqrt(2.0) + 0.001)
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
	print("Tavern knives tests passed")
	quit()
