extends RefCounted
## Detached world update for the opposing party and post-defeat recovery.
const Config = preload("res://campaign/config.gd")
const EncounterRewards = preload("res://campaign/data/encounter_rewards.gd")

static func apply(world: Dictionary, party: Dictionary, opponent: Dictionary, result: Dictionary, summary: Dictionary) -> Dictionary:
	var updated := world.duplicate(true)
	var parties: Array = updated.get("parties", [])
	var opponent_id: Variant = opponent.get("id")
	var index := _party_index(parties, opponent_id)
	if result.win:
		if index >= 0:
			parties.remove_at(index)
		_clear_camp(updated.get("settlements", []), opponent)
	else:
		if index >= 0:
			_reset_opponent(parties[index], result.get("enemyLeft", {}))
			var reinforcements := EncounterRewards.defeat_reinforcements(parties[index].get("fac", ""))
			if not reinforcements.is_empty():
				summary.enemy_reinforcements = _reinforce(parties[index].troops, summary.lost, reinforcements)
		if party.troops.is_empty() and party.get("position") is Vector2:
			var town := _nearest_town(updated.get("settlements", []), party.position)
			if not town.is_empty():
				party.position = town.position + Config.TOWN_RECOVERY_OFFSET
				summary.recovery_town = town.name
				if party.gold < Config.RECOVERY_GOLD_THRESHOLD:
					party.gold += Config.RECOVERY_GOLD
					summary.recovery_gold = Config.RECOVERY_GOLD
	updated.parties = parties
	return updated

static func _party_index(parties: Array, id: Variant) -> int:
	if id == null:
		return -1
	for i in parties.size():
		if parties[i].get("id") == id:
			return i
	return -1

static func _reset_opponent(opponent: Dictionary, enemy_left: Dictionary) -> void:
	if not enemy_left.is_empty():
		var troops: Array[Dictionary] = []
		for id in enemy_left:
			troops.append({"type": id, "n": int(enemy_left[id])})
		opponent.troops = troops
	opponent.cd = Config.OPPONENT_DEFEAT_COOLDOWN
	opponent.state = Config.PARTY_IDLE
	opponent.path = []
	opponent.lock = null

static func _reinforce(troops: Array, lost: int, policy: Dictionary) -> int:
	var total := 0
	var matching: Dictionary = {}
	for stack in troops:
		total += int(stack.n)
		if stack.type == policy.troop_id:
			matching = stack
	var count := maxi(0, mini(roundi(lost * float(policy.loss_share)), int(policy.army_cap) - total))
	if count == 0:
		return 0
	if matching.is_empty():
		troops.append({"type": policy.troop_id, "n": count})
	else:
		matching.n += count
	return count

static func _clear_camp(settlements: Array, opponent: Dictionary) -> void:
	var camp_id: Variant = opponent.get("camp")
	if opponent.get("kind") != EncounterRewards.CAMP_KIND or camp_id == null:
		return
	for settlement in settlements:
		if settlement.get("id") == camp_id:
			settlement.camp = null
			settlement.cleared = true
			settlement.respawn = Config.CAMP_RESPAWN_HOURS
			return

static func _nearest_town(settlements: Array, position: Vector2) -> Dictionary:
	var nearest := {}
	var best := INF
	for settlement in settlements:
		if settlement.get("kind") != Config.SETTLEMENT_TOWN or not settlement.get("position") is Vector2:
			continue
		var distance := position.distance_squared_to(settlement.position)
		if distance < best:
			best = distance
			nearest = settlement
	return nearest
