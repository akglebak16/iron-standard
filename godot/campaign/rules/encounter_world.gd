extends RefCounted
## Detached world update for the opposing party and post-defeat recovery.
const Config = preload("res://campaign/config.gd")
const EncounterRewards = preload("res://campaign/data/encounter_rewards.gd")
const Relations = preload("res://campaign/rules/relations.gd")
const Quests = preload("res://campaign/rules/battle_quests.gd")
const Siege = preload("res://campaign/rules/siege_aftermath.gd")
const Catalog = preload("res://troops/data/catalog.gd")

static func apply(world: Dictionary, party: Dictionary, opponent: Dictionary, result: Dictionary, summary: Dictionary, quest_reward_bonus: float = 0.0, troops: Catalog = null, rng: RandomNumberGenerator = null) -> Dictionary:
	var updated := world.duplicate(true)
	var factions: Array = updated.get("factions", EncounterRewards.CAMPAIGN_FACTIONS)
	var parties: Array = updated.get("parties", [])
	var opponent_id: Variant = opponent.get("id")
	var index := _party_index(parties, opponent_id)
	if result.win:
		if index >= 0:
			parties.remove_at(index)
		var policy := EncounterRewards.victory_policy(opponent)
		_reward_factions(party, factions, policy.global_relation)
		if _clear_camp(updated, policy.camp_target):
			summary.barrow_destroyed = true
			_reward_factions(party, factions, Config.BARROW_RELATION_REWARD)
		summary.completed_quests = Quests.apply_victory(party, policy, quest_reward_bonus)
		if policy.culture_reward:
			Relations.reward(party, party.get("culture", ""), Config.CULTURE_VICTORY_REWARD)
	else:
		if index >= 0:
			_reset_opponent(parties[index], result.get("enemyLeft", {}))
			var reinforcements := EncounterRewards.defeat_reinforcements(parties[index].get("fac", ""))
			if not reinforcements.is_empty():
				summary.enemy_reinforcements = _reinforce(parties[index].troops, summary.lost, reinforcements)
		if party.get("position") is Vector2 and party.troops.is_empty():
			var town := _nearest_town(updated.get("settlements", []), party.position)
			if not town.is_empty():
				party.position = town.position + Config.TOWN_RECOVERY_OFFSET
				summary.recovery_town = town.name
				if party.gold < Config.RECOVERY_GOLD_THRESHOLD:
					party.gold += Config.RECOVERY_GOLD
					summary.recovery_gold = Config.RECOVERY_GOLD
	updated.parties = parties
	if opponent.get("kind") == EncounterRewards.SIEGE_KIND:
		assert(troops != null and rng != null, "Siege aftermath requires a troop catalog and RNG")
		Siege.apply(updated, party, opponent, result, summary, troops, rng)
	summary.hostility_changes = Relations.refresh(party, factions)
	return updated

static func _reward_factions(party: Dictionary, factions: Array, amount: int) -> void:
	if amount <= 0:
		return
	for faction in factions:
		Relations.reward(party, faction, amount)

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

static func _clear_camp(world: Dictionary, camp_id: Variant) -> bool:
	if camp_id == null:
		return false
	for settlement in world.get("settlements", []):
		if settlement.get("id") != camp_id:
			continue
		settlement.camp = null
		settlement.cleared = true
		settlement.respawn = Config.CAMP_RESPAWN_HOURS
		if not settlement.get("barrow", false):
			return false
		settlement.barrow = false
		settlement.fac = EncounterRewards.CLEARED_BARROW_FACTION
		settlement.name = settlement.get("name0", settlement.get("name", ""))
		if world.get("crisis") is Dictionary:
			var remaining: Dictionary = world.crisis.get("left", {})
			var key: Variant = str(camp_id) if remaining.has(str(camp_id)) else camp_id
			remaining[key] = 0
			world.crisis.left = remaining
		return true
	return false

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
