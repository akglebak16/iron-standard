extends SceneTree
const World = preload("res://core/campaign/rules/encounter_world.gd")

func _initialize() -> void:
	var enemy := {"id": 1, "fac": "undead", "kind": "camp", "camp": 2, "troops": [{"type": "s1", "n": 77}], "state": "pursuit", "path": [Vector2.ONE], "lock": 99}
	var world := {
		"parties": [enemy, {"id": 3}],
		"settlements": [
			{"id": 2, "kind": "camp", "camp": 1, "position": Vector2.ZERO},
			{"id": 4, "kind": "village", "position": Vector2(1, 0)},
			{"id": 5, "kind": "town", "name": "Near", "position": Vector2(20, 0)},
			{"id": 6, "kind": "town", "name": "Far", "position": Vector2(30, 0)},
		],
	}
	var party := {"position": Vector2.ZERO, "gold": 59, "troops": []}
	var summary := {"lost": 5}
	var after := World.apply(world, party, enemy, {"win": false, "enemyLeft": {"s1": 698, "z1": 1}}, summary)
	var remaining: Dictionary = after.parties[0]
	assert(remaining.troops == [{"type": "s1", "n": 698}, {"type": "z1", "n": 2}])
	assert(remaining.cd == 10 and remaining.state == "idle" and remaining.path.is_empty() and remaining.lock == null)
	assert(summary.enemy_reinforcements == 1)
	assert(party.position == Vector2(30, 34) and party.gold == 139 and summary.recovery_town == "Near")
	assert(world.parties[0].state == "pursuit" and world.parties[0].troops[0].n == 77)
	party = {"position": Vector2.ZERO, "gold": 60, "troops": []}
	summary = {"lost": 0}
	after = World.apply(world, party, enemy, {"win": false, "enemyLeft": {}}, summary)
	assert(after.parties[0].troops == enemy.troops and party.gold == 60)
	party.troops = [{"type": "n1", "n": 1}]
	party.position = Vector2.ZERO
	summary = {"lost": 0}
	World.apply(world, party, enemy, {"win": false}, summary)
	assert(party.position == Vector2.ZERO and not summary.has("recovery_town"))
	after = World.apply(world, party, enemy, {"win": true}, summary)
	assert(after.parties == [{"id": 3}])
	assert(after.settlements[0].cleared and after.settlements[0].camp == null and after.settlements[0].respawn == 216)
	assert(world.parties.size() == 2 and world.settlements[0].camp == 1)
	party.troops.clear()
	var no_map := World.apply({}, party, {}, {"win": false}, {})
	assert(no_map.parties.is_empty() and party.position == Vector2.ZERO)
	print("Encounter world tests passed")
	quit(0)
