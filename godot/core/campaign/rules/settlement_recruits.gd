extends RefCounted
const Catalog = preload("res://core/troops/data/catalog.gd")
const Generation = preload("res://core/troops/rules/generation.gd")
const Config = preload("res://core/campaign/config.gd")
const RECRUIT_COUNTS := {
	"town": Vector2i(5, 9),
	"castle": Vector2i(3, 6),
	"village": Vector2i(3, 7),
}
const RECRUIT_TIERS := {
	"town": Vector2i(1, 2),
	"castle": Vector2i(2, 3),
	"village": Vector2i(1, 1),
}

static func refresh(settlement: Dictionary, catalog: Catalog, rng: RandomNumberGenerator) -> void:
	if settlement.fac == Config.BANDIT_FACTION:
		return
	if settlement.fac == Config.UNDEAD_FACTION or settlement.get("burnt", 0) > 0:
		settlement.recruits = []
		return
	var kind: String = settlement.kind
	var count_range: Vector2i = RECRUIT_COUNTS.get(kind, RECRUIT_COUNTS.village)
	var count := rng.randi_range(count_range.x, count_range.y) * Config.SOLO_ARMY_SCALE
	var tiers: Vector2i = RECRUIT_TIERS.get(kind, RECRUIT_TIERS.village)
	var candidates := catalog.for_faction(settlement.get("cult", settlement.fac))
	var eligible := candidates.filter(func(troop): return troop.tier >= tiers.x and troop.tier <= tiers.y)
	if eligible.is_empty() and kind != Config.SETTLEMENT_VILLAGE:
		eligible = candidates
	var counts := {}
	if not eligible.is_empty():
		for i in count:
			var id: String = eligible[rng.randi_range(0, eligible.size() - 1)].id
			counts[id] = int(counts.get(id, 0)) + 1
	settlement.recruits = Generation.stacks(counts)
