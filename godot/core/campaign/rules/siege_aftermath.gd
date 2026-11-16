extends RefCounted
const Config = preload("res://core/campaign/config.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Generation = preload("res://core/troops/rules/generation.gd")
const Relations = preload("res://core/campaign/rules/relations.gd")
const Recruits = preload("res://core/campaign/rules/settlement_recruits.gd")
const Rewards = preload("res://core/campaign/data/encounter_rewards.gd")

## Produces the encounter input from the same garrison the result will update.
static func defenders(settlement: Dictionary, parties: Array, catalog: Catalog, rng: RandomNumberGenerator) -> Dictionary:
	var counts := {}
	for stack in _garrison(settlement, catalog, rng):
		counts[stack.type] = int(stack.n)
	var leader: Variant = null
	for lord in parties:
		if not _is_inside_lord(lord, settlement.id) or lord.get("fac") != settlement.fac:
			continue
		if leader == null:
			leader = lord.name
		for stack in lord.troops:
			counts[stack.type] = int(counts.get(stack.type, 0)) + int(stack.n)
	var troops := Generation.stacks(counts)
	troops.sort_custom(func(a, b): return _garrison_precedes(a, b, catalog))
	var gold := Config.SIEGE_TOWN_GOLD if settlement.kind == Config.SETTLEMENT_TOWN else Config.SIEGE_OTHER_GOLD
	return {"id": -int(settlement.id), "kind": Rewards.SIEGE_KIND, "sid": settlement.id, "fac": settlement.fac, "name": settlement.name, "gold": gold, "troops": troops, "lord": leader,
		"wall_damage": clampf(float(settlement.get("dmg", 0.0)), 0.0, 1.0), "wall_defense": supplies(settlement), "castle": settlement.get("kind") == Config.SETTLEMENT_CASTLE}

## Stones and oil the garrison has on the walls (src/05i_siege.js sgDefCfg); the battle scales them by wall damage.
static func supplies(settlement: Dictionary) -> Dictionary:
	return (Config.SIEGE_SUPPLIES_CASTLE if settlement.get("kind") == Config.SETTLEMENT_CASTLE else Config.SIEGE_SUPPLIES_OTHER).duplicate()

## Mutates the world and party copies owned by the encounter resolver.
static func apply(world: Dictionary, party: Dictionary, opponent: Dictionary, result: Dictionary, summary: Dictionary, catalog: Catalog, rng: RandomNumberGenerator) -> void:
	var settlement_id: Variant = opponent.get("sid")
	for settlement in world.get("settlements", []):
		if settlement_id == null or settlement.get("id") != settlement_id:
			continue
		if result.win:
			_capture(world, party, settlement, catalog, rng)
			summary.captured = settlement.name
		else:
			_apply_losses(settlement, result, catalog, rng)
		return

static func _capture(world: Dictionary, party: Dictionary, settlement: Dictionary, catalog: Catalog, rng: RandomNumberGenerator) -> void:
	var former_faction: String = settlement.fac
	var culture: String = settlement.get("cult", former_faction)
	settlement.cult = culture
	settlement.fac = Config.PLAYER_FACTION
	settlement.owner = party.id
	settlement.board = []
	settlement.gar = _generate(catalog, culture, Config.CAPTURE_GARRISON_COUNT, Config.CAPTURE_GARRISON_QUALITY, rng)
	Recruits.refresh(settlement, catalog, rng)
	var parties: Array = world.get("parties", [])
	for i in range(parties.size() - 1, -1, -1):
		var lord: Dictionary = parties[i]
		if _is_inside_lord(lord, settlement.id):
			parties.remove_at(i)
	var factions: Array = world.get("factions", Rewards.CAMPAIGN_FACTIONS)
	if former_faction in factions:
		Relations.reward(party, former_faction, -Config.CAPTURE_RELATION_LOSS)
	if former_faction == Config.UNDEAD_FACTION:
		settlement.ruin = Config.CAPTURE_RUIN_HOURS
		var former_owner: String = settlement.get("ruinOf", "")
		if former_owner in factions:
			Relations.reward(party, former_owner, Config.LIBERATION_RELATION_REWARD)

static func _apply_losses(settlement: Dictionary, result: Dictionary, catalog: Catalog, rng: RandomNumberGenerator) -> void:
	var original := _garrison(settlement, catalog, rng)
	var loss_share := 1.0 - (1.0 - float(result.get("enemyDead", 0)) / float(result.enemyTotal)) if result.get("enemyTotal", 0) > 0 else 0.0
	var remaining: Array[Dictionary] = []
	for stack in original:
		var count := int(stack.n) - roundi(int(stack.n) * loss_share)
		if count > 0:
			remaining.append({"type": stack.type, "n": count})
	settlement.gar = remaining

static func _garrison(settlement: Dictionary, catalog: Catalog, rng: RandomNumberGenerator) -> Array:
	if not settlement.has("gar"):
		settlement.gar = []
		var policy: Dictionary = Config.INITIAL_GARRISONS.get(settlement.kind, {})
		if not policy.is_empty():
			var counts: Vector2i = policy.counts
			settlement.gar = _generate(catalog, settlement.get("cult", settlement.fac), rng.randi_range(counts.x, counts.y), policy.quality, rng)
			settlement.gar.sort_custom(func(a, b): return _garrison_precedes(a, b, catalog))
	return settlement.gar

static func _is_inside_lord(party: Dictionary, settlement_id: Variant) -> bool:
	return party.get("kind") == Config.LORD_KIND and party.get("hide", false) and party.get("home") == settlement_id

static func _generate(catalog: Catalog, culture: String, count: int, quality: float, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var scale := Config.SPECIAL_ARMY_SCALE if culture in [Config.BANDIT_FACTION, Config.UNDEAD_FACTION] else float(Config.SOLO_ARMY_SCALE)
	return Generation.army(catalog, culture, roundi(count * scale), quality, rng)

static func _garrison_precedes(a: Dictionary, b: Dictionary, catalog: Catalog) -> bool:
	var tier_a := int(catalog.get_troop(a.type).tier)
	var tier_b := int(catalog.get_troop(b.type).tier)
	return tier_a > tier_b if tier_a != tier_b else a.type < b.type
