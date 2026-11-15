extends RefCounted
## "Calculate the battle": resolves an encounter without playing it (autoResult in src/05c_logic.js, without companions yet).
const Rules = preload("res://campaign/world/party_rules.gd")

## Returns the same result shape a played battle produces: win, dead, wounded, left, enemyLeft, heroHp, xp...
static func resolve(player_troops: Array, hero: Dictionary, enemy_troops: Array, info: Dictionary, rng: RandomNumberGenerator, survival := 0.0, enemy_mult := 1.0) -> Dictionary:
	var sa := Rules.strength(player_troops, info) + 10.0
	var sb := Rules.strength(enemy_troops, info) * enemy_mult
	var me := sa * rng.randf_range(0.8, 1.25)
	var foe := sb * rng.randf_range(0.8, 1.25)
	var win := me >= foe
	var r := minf(me, foe) / maxf(me, foe)
	var res := {"win": win, "dead": {}, "wounded": {}, "left": {}, "enemyDead": 0, "enemyTotal": Rules.troop_count(enemy_troops),
		"xp": roundi(sb * 0.25), "heroDown": false, "heroKills": 0, "enemyLeft": {}, "auto": true, "time": 0,
		"heroHp": clampf(float(hero.get("hp", 1.0)) - (r * 0.35 if win else 0.55), 0.25, 1.0)}
	var kill_p := r * 0.75 if win else 0.9
	for s in player_troops:
		var d := 0
		var w := 0
		for i in int(s.n):
			if rng.randf() < kill_p:
				if rng.randf() < 0.35 + survival:
					w += 1
				else:
					d += 1
		if d > 0:
			res.dead[s.type] = d
		if w > 0:
			res.wounded[s.type] = w
		res.left[s.type] = int(s.n) - d
	if win:
		res.enemyDead = res.enemyTotal
	else:
		for s in enemy_troops:
			var left := maxi(1, int(s.n) - floori(s.n * r * 0.6))
			res.enemyLeft[s.type] = left
			res.enemyDead += int(s.n) - left
	return res

## Chance to break away from a hunting party (encFlee).
static func flee_chance(player_speed: float, enemy_speed: float, is_camp: bool, perk_flee := 0.0) -> float:
	return clampf(0.45 + (player_speed - enemy_speed) * 0.06 - (0.3 if is_camp else 0.0) + perk_flee, 0.12, 0.9)

## Relative strength label shown in the meeting dialog (relativePowerOf).
static func relative_power(player_troops: Array, enemy_troops: Array, info: Dictionary) -> Array:
	var r := (Rules.strength(player_troops, info) + 8.0) / maxf(1.0, Rules.strength(enemy_troops, info))
	if r > 2.0:
		return ["Мы сильнее", Color("#7ad07a")]
	if r > 1.15:
		return ["Мы чуть сильнее", Color("#7ad07a")]
	if r > 0.8:
		return ["Силы равны", Color("#e0c060")]
	if r > 0.45:
		return ["Они сильнее", Color("#e07050")]
	return ["Они намного сильнее", Color("#e05040")]
