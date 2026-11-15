extends RefCounted
const Event = preload("res://core/battle/combat_event.gd")
var impact_style := Event.ImpactStyle.BLOOD
const Config = preload("res://core/battle/config.gd")

var id: int
var battle_index: int = -1 # Assigned on insertion; independent of ID used for gameplay.
var side: int
var position: Vector2
var hp: float
var max_hp: float
var armor: float
var morale: float
var base_morale: float
var morale_immune: bool = false # Skips the periodic morale and rout check.
var tier: int
var weight: float = 1.0
var xp_multiplier: float = 1.0 # Troop pw from the browser catalog.
var dead: bool = false
var gone: bool = false
var kills: int = 0
var leader: bool = false
var leader_bond: String = "" # Shared by troops affected by the same leader's death.
var leader_loss_chance: float = 0.0
var hero: bool = false
var group_kind: int = 0
var slot_offset: Vector2 = Vector2.ZERO
var troop_id: String = ""
var name: String = "" # Optional named leader or companion; empty uses the troop catalog name.
var damage: float = 0.0
var ranged_melee_damage: float = 0.0 # Zero uses the fallback derived from ranged damage.
var speed: float = 0.0
var attack_range: float = 0.0
var mounted: bool = false
var velocity: Vector2 = Vector2.ZERO
var facing: float = 0.0
var fleeing: bool = false
var wavering: bool = false
var companion_id: String = "" # Stable campaign identity for the result, distinct from a troop type.
var companion: bool:
	get:
		return not companion_id.is_empty()
var faction: String = ""
var appearance: Dictionary = {}
var collision_radius: float = Config.FOOT_COLLISION_RADIUS
var mass: float = Config.FOOT_MASS
var attack_interval: float = 1.0
var attack_cooldown: float = 0.0
var charge_cooldown: float = 0.0
var target_index: int = -1 # Index in State.units; avoids RefCounted cycles between enemies.
var target_timer: float = 0.0
var ai_mode: String = Config.AI_MODE_UNASSIGNED
var ai_windup: float = -1.0
var plan_destination := Vector2.ZERO # AiDecision.plan_into results for the current tick
var plan_face := 0.0
var plan_speed := 1.0
var plan_distance := INF
var ai_wind_target_index: int = -1
var melee_reach: float = Config.DEFAULT_MELEE_REACH
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
var blocking: bool = false
var attack_windup: float = -1.0
var swing_facing: float = 0.0
var swing_timer: float = 0.0
var hero_weapon: Dictionary = {} # Detached equipment data; only the controlled hero reads it.
var perk_effects: Dictionary = {} # Detached character projection, shared by hero combat rules.
var last_stand_used: bool = false

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
