extends RefCounted
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const Event = preload("res://battle/combat_event.gd")
const IMPACT_BY_APPEARANCE := {"skel": Event.ImpactStyle.DUST, "zombie": Event.ImpactStyle.DARK_BLOOD}

static func spawn(battle: State, side: int, stacks: Array, faction: String, catalog: Catalog, rng: RandomNumberGenerator, cap: int = Config.SOLO_UNIT_CAP, leader_name: String = "", starting_morale_bonus: float = 0.0) -> bool:
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
			var unit := Unit.new(battle.units.size(), side, center + jitter, float(troop.hp) * weight, float(troop.arm), int(troop.tier))
			unit.troop_id = str(stack.type)
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
			unit.impact_style = IMPACT_BY_APPEARANCE.get(look.get("undead", ""), Event.ImpactStyle.BLOOD)
			unit.weapon_kind = str(look.get("weapon", ""))
			unit.collision_radius = Config.HORSE_COLLISION_RADIUS if unit.mounted else Config.FOOT_COLLISION_RADIUS
			unit.mass = Config.HORSE_MASS if unit.mounted else Config.FOOT_MASS
			unit.base_morale += starting_morale_bonus
			if battle.wall != null and side == 1:
				unit.facing = battle.groups[side][kind].direction
			_apply_traits(unit, traits)
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
