extends RefCounted
## Inventory drops from rollLoot in src/05d_trade.js.
const Troops = preload("res://troops/data/catalog.gd")
const Gear = preload("res://equipment/data/gear_catalog.gd")
const Goods = preload("res://campaign/data/goods_catalog.gd")
const Config = preload("res://campaign/config.gd")

static func collect(party: Dictionary, encounter: Dictionary, effects: Dictionary, mounted_hero: bool, troops: Troops, gear: Gear, goods: Goods, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var total := 0
	var tiers := 0
	var had_mounted := false
	for stack in encounter.troops:
		var troop := troops.get_troop(stack.type)
		if troop.is_empty():
			return []
		var count := int(stack.n)
		total += count
		tiers += int(troop.tier) * count
		had_mounted = had_mounted or troop.mounted
	if total <= 0:
		return []
	var trade_goods := goods.definitions()
	var items := gear.definitions()
	var trade_ids := trade_goods.keys()
	if trade_ids.is_empty():
		return []
	var faction: String = encounter.get("faction", "")
	var caravan: bool = encounter.get("trade_goods_only", false)
	var local_goods := trade_ids.filter(func(id): return faction in trade_goods[id].make) if caravan else []
	var top := clampi(roundi(float(tiers) / total), 0, Config.LOOT_MAX_TIER)
	var weights := {}
	var sum_weights := 0.0
	for id in items:
		var item: Dictionary = items[id]
		if item.get("unique", 0) or item.tier > top or (item.slot == "horse" and not had_mounted):
			continue
		var preference := Config.LOOT_FACTION_PREFERENCE if faction in item.get("f", []) else 1.0
		var weight := preference / (1.0 + float(item.tier))
		weights[id] = weight
		sum_weights += weight
	var inventory: Dictionary = party.inv
	var capacity := _capacity(party, effects, mounted_hero)
	var weight := _weight(inventory, items, trade_goods)
	var collected := {}
	var rolls := clampi(roundi(total * Config.LOOT_ROLLS_PER_ENEMY), 1, Config.LOOT_MAX_ROLLS)
	for roll in rolls:
		var id: String
		var count := 1
		var unit_weight: float
		if caravan or rng.randf() < Config.LOOT_GOODS_CHANCE:
			var pool := local_goods if not local_goods.is_empty() else trade_ids
			id = pool[rng.randi_range(0, pool.size() - 1)]
			var item: Dictionary = trade_goods[id]
			var budget := rng.randi_range(Config.LOOT_GOODS_VALUE.x, Config.LOOT_GOODS_VALUE.y)
			count = clampi(roundi(float(budget) / float(item.p)), 1, Config.LOOT_MAX_GOODS)
			unit_weight = item.w
		elif not weights.is_empty():
			id = _weighted_pick(weights, sum_weights, rng)
			unit_weight = items[id].w
		else:
			continue
		while count > 0 and weight + unit_weight * count > capacity + Config.CARGO_WEIGHT_EPSILON:
			count -= 1
		if count == 0:
			continue
		weight += unit_weight * count
		inventory[id] = int(inventory.get(id, 0)) + count
		collected[id] = int(collected.get(id, 0)) + count
	var drops: Array[Dictionary] = []
	for id in collected:
		drops.append({"id": id, "n": collected[id]})
	return drops

static func _weighted_pick(weights: Dictionary, total: float, rng: RandomNumberGenerator) -> String:
	var remaining := rng.randf() * total
	var last := ""
	for id in weights:
		last = id
		remaining -= weights[id]
		if remaining <= 0.0:
			return id
	return last

static func _capacity(party: Dictionary, effects: Dictionary, mounted_hero: bool) -> int:
	var count := 0
	for stack in party.troops:
		count += int(stack.n)
	var base := Config.CARGO_BASE + count * Config.CARGO_PER_TROOP + float(party.hero.get("str", 0)) * Config.CARGO_PER_STRENGTH
	if mounted_hero:
		base += Config.CARGO_HORSE_BONUS
	return roundi(base * (1.0 + float(effects.get("cargo", 0.0))))

static func _weight(inventory: Dictionary, items: Dictionary, goods: Dictionary) -> float:
	var weight := 0.0
	for id in inventory:
		var item: Dictionary = items.get(id, goods.get(id, {}))
		weight += float(item.get("w", 0.0)) * int(inventory[id])
	return roundf(weight * Config.CARGO_WEIGHT_PRECISION) / Config.CARGO_WEIGHT_PRECISION
