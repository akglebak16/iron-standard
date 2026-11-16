extends RefCounted
const Event = preload("res://core/battle/combat_event.gd")
var impact_style := Event.ImpactStyle.BLOOD
const Config = preload("res://core/battle/config.gd")
const MotionStore = preload("res://core/battle/model/unit_columns.gd")
var _motion: MotionStore
var _detached_position := Vector2.ZERO
var _detached_velocity := Vector2.ZERO

var _detached_id: int = 0
var id: int:
	get: return _detached_id if _motion == null else _motion.integer_fields[MotionStore.I.ID * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_id = value
		else: _motion.integer_fields[MotionStore.I.ID * _motion.capacity + battle_index] = value
var battle_index: int = -1 # Assigned on insertion; independent of ID used for gameplay.
var _detached_unit_handle: int = 0
var unit_handle: int:
	get: return _detached_unit_handle if _motion == null else _motion.integer_fields[MotionStore.I.UNIT_HANDLE * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_unit_handle = value
		else: _motion.integer_fields[MotionStore.I.UNIT_HANDLE * _motion.capacity + battle_index] = value
var _detached_history_index: int = -1
var history_index: int:
	get: return _detached_history_index if _motion == null else _motion.integer_fields[MotionStore.I.HISTORY_INDEX * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_history_index = value
		else: _motion.integer_fields[MotionStore.I.HISTORY_INDEX * _motion.capacity + battle_index] = value
var _detached_retired_tick: int = -1
var retired_tick: int:
	get: return _detached_retired_tick if _motion == null else _motion.integer_fields[MotionStore.I.RETIRED_TICK * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_retired_tick = value
		else: _motion.integer_fields[MotionStore.I.RETIRED_TICK * _motion.capacity + battle_index] = value
var _detached_side: int = 0
var side: int:
	get: return _detached_side if _motion == null else _motion.integer_fields[MotionStore.I.SIDE * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_side = value
		else: _motion.integer_fields[MotionStore.I.SIDE * _motion.capacity + battle_index] = value
var position: Vector2:
	get: return _detached_position if _motion == null else _motion.positions[battle_index]
	set(value):
		if _motion == null: _detached_position = value
		else: _motion.positions[battle_index] = value
var _detached_hp: float = 0
var hp: float:
	get: return _detached_hp if _motion == null else _motion.real_fields[MotionStore.R.HP * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_hp = value
		else: _motion.real_fields[MotionStore.R.HP * _motion.capacity + battle_index] = value
var _detached_max_hp: float = 0
var max_hp: float:
	get: return _detached_max_hp if _motion == null else _motion.real_fields[MotionStore.R.MAX_HP * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_max_hp = value
		else: _motion.real_fields[MotionStore.R.MAX_HP * _motion.capacity + battle_index] = value
var armor: float
var morale: float
var base_morale: float
var morale_immune: bool = false # Skips the periodic morale and rout check.
var tier: int
var _detached_weight: float = 1.0
var weight: float:
	get: return _detached_weight if _motion == null else _motion.real_fields[MotionStore.R.WEIGHT * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_weight = value
		else: _motion.real_fields[MotionStore.R.WEIGHT * _motion.capacity + battle_index] = value
var xp_multiplier: float = 1.0 # Troop pw from the browser catalog.
var _detached_dead: bool = false
var dead: bool:
	get: return _detached_dead if _motion == null else bool(_motion.integer_fields[MotionStore.I.DEAD * _motion.capacity + battle_index])
	set(value):
		if _motion == null: _detached_dead = value
		else: _motion.integer_fields[MotionStore.I.DEAD * _motion.capacity + battle_index] = int(value)
var _detached_gone: bool = false
var gone: bool:
	get: return _detached_gone if _motion == null else bool(_motion.integer_fields[MotionStore.I.GONE * _motion.capacity + battle_index])
	set(value):
		if _motion == null: _detached_gone = value
		else: _motion.integer_fields[MotionStore.I.GONE * _motion.capacity + battle_index] = int(value)
var kills: int = 0
var _detached_leader: bool = false
var leader: bool:
	get: return _detached_leader if _motion == null else bool(_motion.integer_fields[MotionStore.I.LEADER * _motion.capacity + battle_index])
	set(value):
		if _motion == null: _detached_leader = value
		else: _motion.integer_fields[MotionStore.I.LEADER * _motion.capacity + battle_index] = int(value)
var leader_bond: String = "" # Shared by troops affected by the same leader's death.
var leader_loss_chance: float = 0.0
var _detached_hero: bool = false
var hero: bool:
	get: return _detached_hero if _motion == null else bool(_motion.integer_fields[MotionStore.I.HERO * _motion.capacity + battle_index])
	set(value):
		if _motion == null: _detached_hero = value
		else: _motion.integer_fields[MotionStore.I.HERO * _motion.capacity + battle_index] = int(value)
var _detached_group_kind: int = 0
var group_kind: int:
	get: return _detached_group_kind if _motion == null else _motion.integer_fields[MotionStore.I.GROUP_KIND * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_group_kind = value
		else: _motion.integer_fields[MotionStore.I.GROUP_KIND * _motion.capacity + battle_index] = value
var _detached_slot_offset: Vector2 = Vector2.ZERO
var slot_offset: Vector2:
	get: return _detached_slot_offset if _motion == null else _motion.vector_fields[MotionStore.V.SLOT_OFFSET * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_slot_offset = value
		else: _motion.vector_fields[MotionStore.V.SLOT_OFFSET * _motion.capacity + battle_index] = value
var troop_id: String = ""
var name: String = "" # Optional named leader or companion; empty uses the troop catalog name.
## A column: the C++ kernel reads it to judge how many shooters a target needs (stage 1a-archers, DESIGN.md 4.4).
var _detached_damage: float = 0.0
var damage: float:
	get: return _detached_damage if _motion == null else _motion.real_fields[MotionStore.R.DAMAGE * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_damage = value
		else: _motion.real_fields[MotionStore.R.DAMAGE * _motion.capacity + battle_index] = value
var ranged_melee_damage: float = 0.0 # Zero uses the fallback derived from ranged damage.
var _detached_speed: float = 0.0
var speed: float:
	get: return _detached_speed if _motion == null else _motion.real_fields[MotionStore.R.SPEED * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_speed = value
		else: _motion.real_fields[MotionStore.R.SPEED * _motion.capacity + battle_index] = value
var _detached_attack_range: float = 0.0
var attack_range: float:
	get: return _detached_attack_range if _motion == null else _motion.real_fields[MotionStore.R.ATTACK_RANGE * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_attack_range = value
		else: _motion.real_fields[MotionStore.R.ATTACK_RANGE * _motion.capacity + battle_index] = value
var _detached_mounted: bool = false
var mounted: bool:
	get: return _detached_mounted if _motion == null else bool(_motion.integer_fields[MotionStore.I.MOUNTED * _motion.capacity + battle_index])
	set(value):
		if _motion == null: _detached_mounted = value
		else: _motion.integer_fields[MotionStore.I.MOUNTED * _motion.capacity + battle_index] = int(value)
var velocity: Vector2:
	get: return _detached_velocity if _motion == null else _motion.velocities[battle_index]
	set(value):
		if _motion == null: _detached_velocity = value
		else: _motion.velocities[battle_index] = value
var _detached_facing: float = 0.0
var facing: float:
	get: return _detached_facing if _motion == null else _motion.real_fields[MotionStore.R.FACING * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_facing = value
		else: _motion.real_fields[MotionStore.R.FACING * _motion.capacity + battle_index] = value
var _detached_fleeing: bool = false
var fleeing: bool:
	get: return _detached_fleeing if _motion == null else bool(_motion.integer_fields[MotionStore.I.FLEEING * _motion.capacity + battle_index])
	set(value):
		if _motion == null: _detached_fleeing = value
		else: _motion.integer_fields[MotionStore.I.FLEEING * _motion.capacity + battle_index] = int(value)
var wavering: bool = false
var companion_id: String = "" # Stable campaign identity for the result, distinct from a troop type.
var companion: bool:
	get:
		return not companion_id.is_empty()
var faction: String = ""
var appearance: Dictionary = {}
var _detached_collision_radius: float = Config.FOOT_COLLISION_RADIUS
var collision_radius: float:
	get: return _detached_collision_radius if _motion == null else _motion.real_fields[MotionStore.R.COLLISION_RADIUS * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_collision_radius = value
		else: _motion.real_fields[MotionStore.R.COLLISION_RADIUS * _motion.capacity + battle_index] = value
var _detached_mass: float = Config.FOOT_MASS
var mass: float:
	get: return _detached_mass if _motion == null else _motion.real_fields[MotionStore.R.MASS * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_mass = value
		else: _motion.real_fields[MotionStore.R.MASS * _motion.capacity + battle_index] = value
var _detached_attack_interval: float = 1.0
var attack_interval: float:
	get: return _detached_attack_interval if _motion == null else _motion.real_fields[MotionStore.R.ATTACK_INTERVAL * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_attack_interval = value
		else: _motion.real_fields[MotionStore.R.ATTACK_INTERVAL * _motion.capacity + battle_index] = value
var _detached_attack_cooldown: float = 0.0
var attack_cooldown: float:
	get: return _detached_attack_cooldown if _motion == null else _motion.real_fields[MotionStore.R.ATTACK_COOLDOWN * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_attack_cooldown = value
		else: _motion.real_fields[MotionStore.R.ATTACK_COOLDOWN * _motion.capacity + battle_index] = value
var _detached_charge_cooldown: float = 0.0
var charge_cooldown: float:
	get: return _detached_charge_cooldown if _motion == null else _motion.real_fields[MotionStore.R.CHARGE_COOLDOWN * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_charge_cooldown = value
		else: _motion.real_fields[MotionStore.R.CHARGE_COOLDOWN * _motion.capacity + battle_index] = value
var _detached_target_handle: int = 0
var target_handle: int:
	get: return _detached_target_handle if _motion == null else _motion.integer_fields[MotionStore.I.TARGET_HANDLE * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_target_handle = value
		else: _motion.integer_fields[MotionStore.I.TARGET_HANDLE * _motion.capacity + battle_index] = value
var _detached_target_timer: float = 0.0
var target_timer: float:
	get: return _detached_target_timer if _motion == null else _motion.real_fields[MotionStore.R.TARGET_TIMER * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_target_timer = value
		else: _motion.real_fields[MotionStore.R.TARGET_TIMER * _motion.capacity + battle_index] = value
var _detached_mode := 0
var ai_mode: String:
	get: return MotionStore.MODES[_detached_mode if _motion == null else _motion.integer_fields[MotionStore.I.MODE * _motion.capacity + battle_index]]
	set(value):
		var mode := MotionStore.MODES.find(value)
		assert(mode >= 0)
		if _motion == null: _detached_mode = maxi(0, mode)
		else: _motion.integer_fields[MotionStore.I.MODE * _motion.capacity + battle_index] = maxi(0, mode)
var _detached_ai_windup: float = -1.0
var ai_windup: float:
	get: return _detached_ai_windup if _motion == null else _motion.real_fields[MotionStore.R.AI_WINDUP * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_ai_windup = value
		else: _motion.real_fields[MotionStore.R.AI_WINDUP * _motion.capacity + battle_index] = value
var _detached_plan_destination: Vector2 = Vector2.ZERO
var plan_destination: Vector2:
	get: return _detached_plan_destination if _motion == null else _motion.vector_fields[MotionStore.V.PLAN_DESTINATION * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_plan_destination = value
		else: _motion.vector_fields[MotionStore.V.PLAN_DESTINATION * _motion.capacity + battle_index] = value
var _detached_plan_face: float = 0.0
var plan_face: float:
	get: return _detached_plan_face if _motion == null else _motion.real_fields[MotionStore.R.PLAN_FACE * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_plan_face = value
		else: _motion.real_fields[MotionStore.R.PLAN_FACE * _motion.capacity + battle_index] = value
var _detached_plan_speed: float = 1.0
var plan_speed: float:
	get: return _detached_plan_speed if _motion == null else _motion.real_fields[MotionStore.R.PLAN_SPEED * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_plan_speed = value
		else: _motion.real_fields[MotionStore.R.PLAN_SPEED * _motion.capacity + battle_index] = value
var _detached_plan_distance: float = INF
var plan_distance: float:
	get: return _detached_plan_distance if _motion == null else _motion.real_fields[MotionStore.R.PLAN_DISTANCE * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_plan_distance = value
		else: _motion.real_fields[MotionStore.R.PLAN_DISTANCE * _motion.capacity + battle_index] = value
## Stage 1a (DESIGN.md 4.4, 1.4): melee fighters targeting this unit, counted by movement at the start of the tick.
var _detached_attackers: int = 0
var attackers: int:
	get: return _detached_attackers if _motion == null else _motion.integer_fields[MotionStore.I.ATTACKERS * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_attackers = value
		else: _motion.integer_fields[MotionStore.I.ATTACKERS * _motion.capacity + battle_index] = value
## Charge leash state: walking back to the group, and seconds spent waiting beyond the soft leash.
var _detached_leashed: bool = false
var leashed: bool:
	get: return _detached_leashed if _motion == null else bool(_motion.integer_fields[MotionStore.I.LEASHED * _motion.capacity + battle_index])
	set(value):
		if _motion == null: _detached_leashed = value
		else: _motion.integer_fields[MotionStore.I.LEASHED * _motion.capacity + battle_index] = int(value)
## Stage 1a-archers (DESIGN.md 4.4): shooters targeting this unit, counted by movement at the start of the tick.
var _detached_aimers: int = 0
var aimers: int:
	get: return _detached_aimers if _motion == null else _motion.integer_fields[MotionStore.I.AIMERS * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_aimers = value
		else: _motion.integer_fields[MotionStore.I.AIMERS * _motion.capacity + battle_index] = value
var _detached_chase_seconds: float = 0.0
var chase_seconds: float:
	get: return _detached_chase_seconds if _motion == null else _motion.real_fields[MotionStore.R.CHASE_SECONDS * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_chase_seconds = value
		else: _motion.real_fields[MotionStore.R.CHASE_SECONDS * _motion.capacity + battle_index] = value
var _detached_ai_wind_target_handle: int = 0
var ai_wind_target_handle: int:
	get: return _detached_ai_wind_target_handle if _motion == null else _motion.integer_fields[MotionStore.I.AI_WIND_TARGET_HANDLE * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_ai_wind_target_handle = value
		else: _motion.integer_fields[MotionStore.I.AI_WIND_TARGET_HANDLE * _motion.capacity + battle_index] = value
var _detached_melee_reach: float = Config.DEFAULT_MELEE_REACH
var melee_reach: float:
	get: return _detached_melee_reach if _motion == null else _motion.real_fields[MotionStore.R.MELEE_REACH * _motion.capacity + battle_index]
	set(value):
		if _motion == null: _detached_melee_reach = value
		else: _motion.real_fields[MotionStore.R.MELEE_REACH * _motion.capacity + battle_index] = value
var block_chance: float = 0.0
var shield_block: float = 0.0 # Troop shield arrow bonus; hero gear will supply its own value later.
var accuracy: float = 0.0
var pierce: float = 0.0
var damage_type: String = "" # Empty for troop attacks without an equipped weapon.
var anti_cavalry: bool = false
var weapon_kind: String = ""
var blunt_melee: bool = false # Innate attack classification for troops without an equipped weapon.
var projectile_damage_multiplier: float = 1.0
var blunt_melee_damage_multiplier: float = 1.0
var stamina: float = Config.HERO_MAX_STAMINA
var _detached_blocking: bool = false
var blocking: bool:
	get: return _detached_blocking if _motion == null else bool(_motion.integer_fields[MotionStore.I.BLOCKING * _motion.capacity + battle_index])
	set(value):
		if _motion == null: _detached_blocking = value
		else: _motion.integer_fields[MotionStore.I.BLOCKING * _motion.capacity + battle_index] = int(value)
var attack_windup: float = -1.0
var swing_facing: float = 0.0
var swing_timer: float = 0.0
var hero_weapon: Dictionary = {} # Detached equipment data; only the controlled hero reads it.
var perk_effects: Dictionary = {} # Detached character projection, shared by hero combat rules.
var last_stand_used: bool = false

func bind_motion(store: MotionStore) -> void:
	assert(_motion == null and battle_index >= 0)
	store.positions[battle_index] = _detached_position
	store.velocities[battle_index] = _detached_velocity
	store.real_fields[MotionStore.R.HP * store.capacity + battle_index] = _detached_hp
	store.real_fields[MotionStore.R.MAX_HP * store.capacity + battle_index] = _detached_max_hp
	store.real_fields[MotionStore.R.WEIGHT * store.capacity + battle_index] = _detached_weight
	store.real_fields[MotionStore.R.COLLISION_RADIUS * store.capacity + battle_index] = _detached_collision_radius
	store.real_fields[MotionStore.R.MASS * store.capacity + battle_index] = _detached_mass
	store.real_fields[MotionStore.R.SPEED * store.capacity + battle_index] = _detached_speed
	store.real_fields[MotionStore.R.ATTACK_RANGE * store.capacity + battle_index] = _detached_attack_range
	store.real_fields[MotionStore.R.MELEE_REACH * store.capacity + battle_index] = _detached_melee_reach
	store.real_fields[MotionStore.R.ATTACK_INTERVAL * store.capacity + battle_index] = _detached_attack_interval
	store.real_fields[MotionStore.R.ATTACK_COOLDOWN * store.capacity + battle_index] = _detached_attack_cooldown
	store.real_fields[MotionStore.R.CHARGE_COOLDOWN * store.capacity + battle_index] = _detached_charge_cooldown
	store.real_fields[MotionStore.R.TARGET_TIMER * store.capacity + battle_index] = _detached_target_timer
	store.real_fields[MotionStore.R.FACING * store.capacity + battle_index] = _detached_facing
	store.real_fields[MotionStore.R.AI_WINDUP * store.capacity + battle_index] = _detached_ai_windup
	store.real_fields[MotionStore.R.PLAN_FACE * store.capacity + battle_index] = _detached_plan_face
	store.real_fields[MotionStore.R.PLAN_SPEED * store.capacity + battle_index] = _detached_plan_speed
	store.real_fields[MotionStore.R.PLAN_DISTANCE * store.capacity + battle_index] = _detached_plan_distance
	store.real_fields[MotionStore.R.CHASE_SECONDS * store.capacity + battle_index] = _detached_chase_seconds
	store.real_fields[MotionStore.R.DAMAGE * store.capacity + battle_index] = _detached_damage
	store.integer_fields[MotionStore.I.ID * store.capacity + battle_index] = _detached_id
	store.integer_fields[MotionStore.I.SIDE * store.capacity + battle_index] = _detached_side
	store.integer_fields[MotionStore.I.GROUP_KIND * store.capacity + battle_index] = _detached_group_kind
	store.integer_fields[MotionStore.I.TARGET_HANDLE * store.capacity + battle_index] = _detached_target_handle
	store.integer_fields[MotionStore.I.AI_WIND_TARGET_HANDLE * store.capacity + battle_index] = _detached_ai_wind_target_handle
	store.integer_fields[MotionStore.I.UNIT_HANDLE * store.capacity + battle_index] = _detached_unit_handle
	store.integer_fields[MotionStore.I.HISTORY_INDEX * store.capacity + battle_index] = _detached_history_index
	store.integer_fields[MotionStore.I.RETIRED_TICK * store.capacity + battle_index] = _detached_retired_tick
	store.integer_fields[MotionStore.I.DEAD * store.capacity + battle_index] = int(_detached_dead)
	store.integer_fields[MotionStore.I.GONE * store.capacity + battle_index] = int(_detached_gone)
	store.integer_fields[MotionStore.I.HERO * store.capacity + battle_index] = int(_detached_hero)
	store.integer_fields[MotionStore.I.MOUNTED * store.capacity + battle_index] = int(_detached_mounted)
	store.integer_fields[MotionStore.I.FLEEING * store.capacity + battle_index] = int(_detached_fleeing)
	store.integer_fields[MotionStore.I.BLOCKING * store.capacity + battle_index] = int(_detached_blocking)
	store.integer_fields[MotionStore.I.LEADER * store.capacity + battle_index] = int(_detached_leader)
	store.integer_fields[MotionStore.I.ATTACKERS * store.capacity + battle_index] = _detached_attackers
	store.integer_fields[MotionStore.I.AIMERS * store.capacity + battle_index] = _detached_aimers
	store.integer_fields[MotionStore.I.LEASHED * store.capacity + battle_index] = int(_detached_leashed)
	store.vector_fields[MotionStore.V.SLOT_OFFSET * store.capacity + battle_index] = _detached_slot_offset
	store.vector_fields[MotionStore.V.PLAN_DESTINATION * store.capacity + battle_index] = _detached_plan_destination
	store.integer_fields[MotionStore.I.MODE * store.capacity + battle_index] = _detached_mode
	_motion = store

func detach_motion() -> void:
	if _motion == null: return
	_detached_position = _motion.positions[battle_index]
	_detached_velocity = _motion.velocities[battle_index]
	_detached_hp = hp
	_detached_max_hp = max_hp
	_detached_weight = weight
	_detached_collision_radius = collision_radius
	_detached_mass = mass
	_detached_speed = speed
	_detached_attack_range = attack_range
	_detached_melee_reach = melee_reach
	_detached_attack_interval = attack_interval
	_detached_attack_cooldown = attack_cooldown
	_detached_charge_cooldown = charge_cooldown
	_detached_target_timer = target_timer
	_detached_facing = facing
	_detached_ai_windup = ai_windup
	_detached_plan_face = plan_face
	_detached_plan_speed = plan_speed
	_detached_plan_distance = plan_distance
	_detached_chase_seconds = chase_seconds
	_detached_attackers = attackers
	_detached_aimers = aimers
	_detached_damage = damage
	_detached_leashed = leashed
	_detached_id = id
	_detached_side = side
	_detached_group_kind = group_kind
	_detached_target_handle = target_handle
	_detached_ai_wind_target_handle = ai_wind_target_handle
	_detached_unit_handle = unit_handle
	_detached_history_index = history_index
	_detached_retired_tick = retired_tick
	_detached_dead = dead
	_detached_gone = gone
	_detached_hero = hero
	_detached_mounted = mounted
	_detached_fleeing = fleeing
	_detached_blocking = blocking
	_detached_leader = leader
	_detached_slot_offset = slot_offset
	_detached_plan_destination = plan_destination
	_detached_mode = _motion.integer_fields[MotionStore.I.MODE * _motion.capacity + battle_index]
	_motion = null

func _init(unit_id: int, unit_side: int, at: Vector2, health: float, protection: float, unit_tier: int) -> void:
	id = unit_id
	side = unit_side
	position = at
	hp = health
	max_hp = health
	armor = protection
	tier = unit_tier
	base_morale = Config.BASE_MORALE + tier * Config.TIER_MORALE
	morale = base_morale
