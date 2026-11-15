extends RefCounted
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Event = preload("res://core/battle/combat_event.gd")
const IMPACT_BY_APPEARANCE := {"skel": Event.ImpactStyle.DUST, "zombie": Event.ImpactStyle.DARK_BLOOD}

static func spawn(battle: State, side: int, stacks: Array, faction: String, catalog: Catalog, rng: RandomNumberGenerator, cap: int = Config.SOLO_UNIT_CAP, leader_name: String = "", starting_morale_bonus: float = 0.0, reserve_waves: bool = false) -> bool:
	if side < 0 or side > 1 or battle.groups.size() != 2 or cap <= 0:
		return false
	var total := 0
	var definitions: Array[Dictionary] = []
	for stack in stacks:
		if not _valid_stack(stack):
			return false
		var troop := catalog.get_troop(stack.type)
		if troop.is_empty():
			return false
		definitions.append(troop)
		total += int(stack.n)
	if reserve_waves and total > cap:
		var expanded := _draw_reserve(battle, side, stacks, definitions, cap, rng)
		stacks = expanded.stacks
		definitions = expanded.definitions
		total = cap
	var scale := minf(1.0, float(cap) / total) if total > 0 else 1.0
	var leader: Unit = null
	var leader_has_morale_override := false
	for stack_index in stacks.size():
		var stack: Dictionary = stacks[stack_index]
		var troop: Dictionary = definitions[stack_index]
		var count := maxi(1, roundi(int(stack.n) * scale)) if scale < 1.0 else int(stack.n)
		var weight := float(stack.n) / count
		var traits: Dictionary = troop.get("battle_traits", {})
		for i in count:
			var kind: int = troop.grp
			var center: Vector2 = battle.groups[side][kind].center
			var jitter := Vector2(rng.randf_range(-Config.SPAWN_JITTER, Config.SPAWN_JITTER), rng.randf_range(-Config.SPAWN_JITTER, Config.SPAWN_JITTER))
			var unit := create_unit(battle, side, str(stack.type), troop, faction, center + jitter, weight, rng, starting_morale_bonus)
			battle.add_grouped_unit(unit, kind)
			if not leader_name.is_empty() and (leader == null or unit.tier > leader.tier):
				leader = unit
				leader_has_morale_override = traits.has("morale_base")
	if leader != null:
		leader.leader = true
		leader.name = leader_name
		leader.max_hp *= Config.LEADER_HEALTH_MULTIPLIER
		leader.hp = leader.max_hp
		leader.damage *= Config.LEADER_DAMAGE_MULTIPLIER
		if not leader_has_morale_override:
			leader.base_morale = Config.LEADER_BASE_MORALE
			leader.morale = leader.base_morale
	return true

## Shared by the initial spawn and reserve waves (src/03_battle.js mkUnit and the fill/battleWaves callers).
static func create_unit(battle: State, side: int, troop_id: String, troop: Dictionary, faction: String, at: Vector2, weight: float, rng: RandomNumberGenerator, starting_morale_bonus: float = 0.0) -> Unit:
	var kind: int = troop.grp
	var unit := Unit.new(battle.units.size(), side, at, float(troop.hp) * weight, float(troop.arm), int(troop.tier))
	unit.troop_id = troop_id
	unit.name = troop.name
	unit.faction = faction
	unit.weight = weight
	unit.xp_multiplier = float(troop.get("pw", 1.0))
	unit.damage = float(troop.dmg) * weight
	unit.ranged_melee_damage = float(troop.get("mdmg", 0.0))
	unit.speed = float(troop.spd) * rng.randf_range(Config.SPEED_RANDOM_MIN, Config.SPEED_RANDOM_MAX)
	unit.attack_cooldown = rng.randf_range(0.0, Config.AI_INITIAL_ATTACK_COOLDOWN_MAX)
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
	unit.appearance = look.duplicate(true)
	unit.impact_style = IMPACT_BY_APPEARANCE.get(look.get("undead", ""), Event.ImpactStyle.BLOOD)
	unit.weapon_kind = str(look.get("weapon", ""))
	unit.collision_radius = Config.HORSE_COLLISION_RADIUS if unit.mounted else Config.FOOT_COLLISION_RADIUS
	unit.mass = Config.HORSE_MASS if unit.mounted else Config.FOOT_MASS
	unit.base_morale += starting_morale_bonus
	if battle.wall != null and side == 1:
		unit.facing = battle.groups[side][kind].direction
	_apply_traits(unit, troop.get("battle_traits", {}))
	return unit

## Browser fill(): every figure above the cap waits in a shuffled reserve and enters in waves instead of being merged.
static func _draw_reserve(battle: State, side: int, stacks: Array, definitions: Array[Dictionary], cap: int, rng: RandomNumberGenerator) -> Dictionary:
	var figures: Array[int] = []
	for stack_index in stacks.size():
		for i in int(stacks[stack_index].n):
			figures.append(stack_index)
	for i in range(figures.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := figures[i]
		figures[i] = figures[j]
		figures[j] = swap
	var drawn_stacks: Array = []
	var drawn_definitions: Array[Dictionary] = []
	var position_by_stack := {}
	for stack_index in figures.slice(0, cap):
		if not position_by_stack.has(stack_index):
			position_by_stack[stack_index] = drawn_stacks.size()
			drawn_stacks.append({"type": stacks[stack_index].type, "n": 0})
			drawn_definitions.append(definitions[stack_index])
		drawn_stacks[position_by_stack[stack_index]].n += 1
	for stack_index in figures.slice(cap):
		var troop_id := str(stacks[stack_index].type)
		battle.reserve[side].append(troop_id)
		if not battle.reserve_definitions.has(troop_id):
			battle.reserve_definitions[troop_id] = definitions[stack_index].duplicate(true)
	battle.reserve_caps[side] = cap
	return {"stacks": drawn_stacks, "definitions": drawn_definitions}

static func _apply_traits(unit: Unit, traits: Dictionary) -> void:
	unit.base_morale = float(traits.get("morale_base", unit.base_morale))
	unit.morale = unit.base_morale
	unit.morale_immune = bool(traits.get("morale_immune", false))
	unit.leader_bond = str(traits.get("leader_bond", ""))
	unit.leader_loss_chance = float(traits.get("leader_loss_chance", 0.0))
	unit.blunt_melee = bool(traits.get("blunt_melee", false))
	unit.projectile_damage_multiplier = float(traits.get("projectile_damage_multiplier", 1.0))
	unit.blunt_melee_damage_multiplier = float(traits.get("blunt_melee_damage_multiplier", 1.0))

static func _valid_stack(stack: Variant) -> bool:
	if not stack is Dictionary or not stack.get("type") is String:
		return false
	var count: Variant = stack.get("n")
	return (count is int or count is float) and is_finite(float(count)) and count >= 1 and count == int(count)
