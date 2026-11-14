extends RefCounted
## Port of src/03_battle.js finishBattle() for the single-player side.
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")

static func build(battle: State, hero: Unit, rng: RandomNumberGenerator, elapsed: float, won: bool) -> Dictionary:
	var survival: float = float(hero.perk_effects.get("surv", 0.0))
	var result := {"win": won, "dead": {}, "wounded": {}, "left": {}, "comps": {}, "enemyDead": 0.0, "enemyTotal": 0.0, "xp": 0.0, "heroDown": hero.dead, "heroHp": clampf(hero.hp / hero.max_hp, 0.0, 1.0), "heroKills": hero.kills, "time": elapsed, "enemyLeft": {}}
	for unit: Unit in battle.units:
		if unit.side == 1:
			result.enemyTotal += unit.weight
			if unit.dead:
				result.xp += (unit.tier * Config.XP_PER_ENEMY_TIER + (Config.XP_MOUNTED_ENEMY_BONUS if unit.mounted else 0.0)) * unit.weight * unit.xp_multiplier
		if unit.hero and unit.side == 0:
			continue
		if unit.companion:
			if unit.side == 0:
				result.comps[unit.companion_id] = {"hp": 0.0 if unit.dead else clampf(unit.hp / unit.max_hp, 0.0, 1.0), "down": unit.dead, "kills": unit.kills}
			continue
		if unit.side == 0:
			var field: String = "left"
			if unit.dead and not unit.gone:
				field = "wounded" if rng.randf() < Config.BASE_WOUNDED_CHANCE + survival else "dead"
			result[field][unit.troop_id] = float(result[field].get(unit.troop_id, 0.0)) + unit.weight
		elif unit.dead and not unit.gone:
			result.enemyDead += unit.weight
		else:
			result.enemyLeft[unit.troop_id] = float(result.enemyLeft.get(unit.troop_id, 0.0)) + unit.weight
	for field in ["dead", "wounded", "left", "enemyLeft"]:
		var counts: Dictionary = result[field]
		for troop_id in counts.keys():
			counts[troop_id] = roundi(counts[troop_id])
			if counts[troop_id] == 0:
				counts.erase(troop_id)
	result.enemyDead = roundi(result.enemyDead)
	result.enemyTotal = roundi(result.enemyTotal)
	result.xp = roundi(result.xp)
	return result
