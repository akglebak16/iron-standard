extends SceneTree
const World = preload("res://core/campaign/rules/encounter_world.gd")

func _initialize() -> void:
	var camp := {"id": 1, "kind": "camp", "fac": "undead", "camp": 2}
	var world := {"parties": [camp], "settlements": [{"id": 2, "barrow": true, "fac": "undead", "name": "Barrow", "name0": "Camp"}], "crisis": {"left": {"2": 3}}}
	var party := {"gold": 10, "culture": "nord", "rel": {"nord": -22, "kin": 99}, "hostF": {"nord": true}, "quests": [
		{"id": "clear", "type": "camp", "sid": 2, "fac": "kin", "reward": 100},
		{"id": "other", "type": "camp", "sid": 3, "fac": "nord", "reward": 100},
		{"id": "purge", "type": "purge", "n": 2, "got": 0, "fac": "nord", "reward": 150},
	]}
	var summary := {}
	var updated := World.apply(world, party, camp, {"win": true}, summary, 0.15)
	assert(updated.settlements[0].name == "Camp" and updated.settlements[0].fac == "bandit")
	assert(not updated.settlements[0].barrow and updated.crisis.left["2"] == 0 and world.crisis.left["2"] == 3)
	assert(party.gold == 125 and party.rel.kin == 100 and party.rel.nord == -16 and party.rel.pact == 5)
	assert(summary.barrow_destroyed and summary.completed_quests == [{"id": "clear", "gold": 115}])
	assert(summary.hostility_changes == [{"faction": "nord", "hostile": false}])
	assert(party.quests.size() == 2 and party.quests[1].got == 0)
	var bandits := {"kind": "bandit", "fac": "bandit"}
	World.apply({}, party, bandits, {"win": false}, {})
	assert(party.quests[1].got == 0)
	summary = {}
	World.apply({}, party, bandits, {"win": true}, summary)
	assert(party.quests[1].got == 1 and summary.completed_quests.is_empty())
	summary = {}
	World.apply({}, party, bandits, {"win": true}, summary)
	assert(party.quests.size() == 1 and party.quests[0].id == "other" and party.gold == 275)
	assert(party.rel.nord == -8 and summary.completed_quests == [{"id": "purge", "gold": 150}])
	World.apply({}, party, {"kind": "dead", "fac": "undead"}, {"win": true}, {})
	assert(party.rel.nord == -5 and party.rel.pact == 8)
	print("Battle quests and relations tests passed")
	quit(0)
