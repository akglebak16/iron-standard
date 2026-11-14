extends SceneTree
const Aftermath = preload("res://campaign/rules/battle_aftermath.gd")
const Rewards = preload("res://campaign/data/encounter_rewards.gd")
const Troops = preload("res://troops/data/catalog.gd")

func _initialize() -> void:
	var troops := Troops.new()
	assert(troops.load_data())
	var party := {"troops": [{"type": "n1", "n": 8}], "hero": {"hp": 1.0, "int": 3, "xp": 170}, "gold": 102}
	var result := {"win": true, "dead": {"n1": 3}, "wounded": {"n1": 2}, "heroHp": 0.0, "enemyDead": 4, "heroKills": 2, "xp": 80}
	party.comps = [{"id": "anselm", "hp": 1.0}, {"id": "vikenty", "hp": 0.2}]
	result.comps = {"anselm": {"down": true, "hp": 0.0}}
	var enemy := Rewards.from_opponent({"fac": "undead", "kind": "camp", "troops": [{"type": "s1", "n": 4}], "gold": 10})
	var rng := RandomNumberGenerator.new()
	var reference := RandomNumberGenerator.new()
	rng.seed = 24
	reference.seed = 24
	var expected_gold := roundi((4 * 15 * reference.randf_range(0.7, 1.1) * 0.2 + 130) * 1.1)
	var expected_grain := ceili(reference.randi_range(0, 8) / 6.0)
	var victory := Aftermath.resolve(party, result, enemy, {"loot": 0.1, "xp": 0.05}, troops, rng)
	assert(victory.party.gold == 102 + expected_gold)
	assert(victory.party.inv.get("grain", 0) == expected_grain and rng.state == reference.state)
	assert(victory.party.troops == [{"type": "n1", "n": 5}])
	assert(victory.party.hero.hp == 0.22 and victory.party.hero.lvl == 2 and victory.party.hero.xp == 101)
	assert(victory.party.hero.pts == 2 and victory.party.hero.pp == 1)
	assert(victory.party.stats == {"wins": 1, "kills": 4})
	assert(victory.party.comps[0].hp == 0.1 and victory.party.comps[1].hp == 0.2 and party.comps[0].hp == 1.0)
	assert(victory.summary.wounded == 2 and victory.summary.lost == 3 and victory.summary.levels_gained == 1)
	assert(party.gold == 102 and party.troops[0].n == 8 and party.hero.hp == 1.0 and not party.has("inv"))
	result.win = false
	var rng_before_defeat := rng.state
	var defeat := Aftermath.resolve(party, result, enemy, {}, troops, rng)
	assert(defeat.party.gold == 76 and defeat.summary.lost_gold == 26)
	assert(defeat.summary.loot == 0 and defeat.summary.xp == 42 and defeat.party.inv.is_empty())
	assert(rng.state == rng_before_defeat)
	print("Campaign aftermath tests passed")
	quit(0)
