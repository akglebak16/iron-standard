extends RefCounted
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Catalog = preload("res://battle/data/catalog.gd")

static func spawn(battle: State, side: int, stacks: Array, faction: String, catalog: Catalog, rng: RandomNumberGenerator) -> bool:
	if side < 0 or side > 1 or battle.groups.size() != 2:
		return false
	var total := 0
	for stack in stacks:
		if not _valid_stack(stack) or catalog.get_troop(stack.type).is_empty():
			return false
		total += int(stack.n)
	var cap := Config.unit_cap(faction)
	var scale := minf(1.0, float(cap) / total) if total > 0 else 1.0
	for stack in stacks:
		var troop: Dictionary = catalog.get_troop(str(stack.type))
		var count := maxi(1, roundi(int(stack.n) * scale)) if scale < 1.0 else int(stack.n)
		var weight := float(stack.n) / count
		for i in count:
			var kind: int = troop.grp
			var center: Vector2 = battle.groups[side][kind].center
			var jitter := Vector2(rng.randf_range(-Config.SPAWN_JITTER, Config.SPAWN_JITTER), rng.randf_range(-Config.SPAWN_JITTER, Config.SPAWN_JITTER))
			var unit := Unit.new(battle.units.size(), side, center + jitter, float(troop.hp) * weight, float(troop.arm), int(troop.tier))
			unit.troop_id = str(stack.type)
			unit.faction = faction
			unit.weight = weight
			unit.damage = float(troop.dmg) * weight
			unit.speed = float(troop.spd) * rng.randf_range(Config.SPEED_RANDOM_MIN, Config.SPEED_RANDOM_MAX)
			unit.target_timer = rng.randf_range(0.0, Config.RETARGET_INITIAL_MAX_SECONDS)
			unit.attack_range = float(troop.get("range", 0))
			unit.mounted = bool(troop.mounted)
			unit.attack_interval = float(troop.cd)
			unit.melee_reach = Config.DEFAULT_MELEE_REACH + float(troop.get("reach", 0))
			unit.block_chance = float(troop.get("block", 0))
			unit.shield_block = float(troop.get("shb", 0))
			unit.accuracy = float(troop.get("acc", 0))
			unit.pierce = float(troop.get("pierce", 0))
			unit.anti_cavalry = bool(troop.get("anticav", false))
			var look: Dictionary = troop.get("look", {})
			unit.weapon_kind = str(look.get("weapon", ""))
			unit.undead_kind = str(look.get("undead", ""))
			unit.collision_radius = Config.HORSE_COLLISION_RADIUS if unit.mounted else Config.FOOT_COLLISION_RADIUS
			unit.mass = Config.HORSE_MASS if unit.mounted else Config.FOOT_MASS
			battle.add_grouped_unit(unit, kind)
	return true

static func _valid_stack(stack: Variant) -> bool:
	if not stack is Dictionary or not stack.get("type") is String:
		return false
	var count: Variant = stack.get("n")
	return (count is int or count is float) and is_finite(float(count)) and count >= 1 and count == int(count)
