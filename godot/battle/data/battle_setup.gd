extends Resource
## Authoring data only. A factory creates new mutable runtime objects for each battle.
const Config = preload("res://battle/config.gd")
# Browser compatibility default for armies without an explicit scenario budget.
const FACTION_UNIT_CAPS := {"undead": 600}
const DEFAULT_UNIT_CAP_OVERRIDE := 0
@export var seed: int = 0
@export_enum("grass", "snow", "steppe", "arid") var biome: String = Config.DEFAULT_BIOME
@export var siege: bool = false
@export var player_faction: String = ""
@export var enemy_faction: String = ""
@export var player_unit_cap: int = DEFAULT_UNIT_CAP_OVERRIDE
@export var enemy_unit_cap: int = DEFAULT_UNIT_CAP_OVERRIDE
@export var enemy_leader_name: String = "" # Empty means no named leader.
@export var player_army: Array[Dictionary] = []
@export var enemy_army: Array[Dictionary] = []
@export var hero_troop: String = ""
@export var hero_profile: Dictionary = {} # Empty keeps the existing troop-based preview hero.
@export var companion_profiles: Array[Dictionary] = [] # All hired companions, including injured ones.
@export var hero_position : Vector2 = Vector2.ZERO

func unit_cap(faction: String, override: int) -> int:
	return int(FACTION_UNIT_CAPS.get(faction, Config.SOLO_UNIT_CAP)) if override == DEFAULT_UNIT_CAP_OVERRIDE else override
