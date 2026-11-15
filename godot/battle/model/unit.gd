extends BattleUnit
## Hot fields (position, velocity, targeting and AI state) live in the native BattleUnit (godot/native/src/battle_unit.h)
## so the battle core reads them directly; everything else is declared here.
const Event = preload("res://battle/combat_event.gd")
var impact_style := Event.ImpactStyle.BLOOD
const Config = preload("res://battle/config.gd")

var armor: float
var morale_immune: bool = false # Skips the periodic morale and rout check.
var xp_multiplier: float = 1.0 # Troop pw from the browser catalog.
var kills: int = 0
var leader_bond: String = "" # Shared by troops affected by the same leader's death.
var leader_loss_chance: float = 0.0
var troop_id: String = ""
var name: String = "" # Optional named leader or companion; empty uses the troop catalog name.
var damage: float = 0.0
var ranged_melee_damage: float = 0.0 # Zero uses the fallback derived from ranged damage.
var wavering: bool = false
var companion_id: String = "": # Stable campaign identity for the result, distinct from a troop type.
	set(value):
		companion_id = value
		is_companion = not value.is_empty()
var companion: bool:
	get:
		return not companion_id.is_empty()
var faction: String = ""
var appearance: Dictionary = {}
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
