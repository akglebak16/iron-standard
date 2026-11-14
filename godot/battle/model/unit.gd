extends RefCounted
const Config = preload("res://battle/config.gd")

var id: int
var side: int
var position: Vector2
var hp: float
var max_hp: float
var armor: float
var morale: float
var base_morale: float
var tier: int
var weight: float = 1.0
var dead: bool = false
var gone: bool = false
var kills: int = 0
var leader: bool = false
var hero: bool = false
var group_kind: int = 0
var slot_offset: Vector2 = Vector2.ZERO
var troop_id: String = ""
var damage: float = 0.0
var speed: float = 0.0
var attack_range: float = 0.0
var mounted: bool = false
var velocity: Vector2 = Vector2.ZERO
var facing: float = 0.0
var fleeing: bool = false
var wavering: bool = false
var companion: bool = false
var faction: String = ""
var collision_radius: float = Config.FOOT_COLLISION_RADIUS
var mass: float = Config.FOOT_MASS
var attack_interval: float = 1.0
var attack_cooldown: float = 0.0
var charge_cooldown: float = 0.0
var target_id: int = -1 # Index in State.units; avoids RefCounted cycles between enemies.
var target_timer: float = 0.0
var ai_mode: String = Config.AI_MODE_UNASSIGNED
var melee_reach: float = Config.DEFAULT_MELEE_REACH
var block_chance: float = 0.0
var shield_block: float = 0.0 # Troop shield arrow bonus; hero gear will supply its own value later.
var accuracy: float = 0.0
var pierce: float = 0.0
var anti_cavalry: bool = false
var weapon_kind: String = ""
var undead_kind: String = ""
var stamina: float = Config.HERO_MAX_STAMINA
var blocking: bool = false
var attack_windup: float = 0.0
var swing_facing: float = 0.0

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
