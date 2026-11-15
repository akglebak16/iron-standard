extends RefCounted
const Catalog = preload("res://core/troops/data/catalog.gd")
const QUALITY_MIDPOINT := 0.5
const QUALITY_SHIFT := 0.7
const LOW_TIER_THRESHOLD := 0.38
const MID_TIER_THRESHOLD := 0.78
const MOUNTED_REROLL_CHANCE := 0.55
const MOUNTED_SPECIALIST := "khan"

static func army(catalog: Catalog, faction: String, count: int, quality: float, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var candidates := catalog.for_faction(faction)
	if candidates.is_empty():
		return []
	var by_tier := {}
	for troop in candidates:
		var tier := int(troop.tier)
		if not by_tier.has(tier):
			by_tier[tier] = []
		by_tier[tier].append(troop)
	var counts := {}
	for i in count:
		var roll := rng.randf() + (quality - QUALITY_MIDPOINT) * QUALITY_SHIFT
		var tier := 1 if roll < LOW_TIER_THRESHOLD else (2 if roll < MID_TIER_THRESHOLD else 3)
		var pool: Array = by_tier.get(tier, candidates)
		var troop: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if troop.mounted and faction != MOUNTED_SPECIALIST and rng.randf() < MOUNTED_REROLL_CHANCE:
			troop = pool[rng.randi_range(0, pool.size() - 1)]
		counts[troop.id] = int(counts.get(troop.id, 0)) + 1
	return stacks(counts)

static func stacks(counts: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in counts:
		result.append({"type": id, "n": counts[id]})
	return result
