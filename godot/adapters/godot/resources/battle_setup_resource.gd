extends Resource
const ValueSetup = preload("res://core/battle/data/battle_setup.gd")
## Authoring data only. A factory creates new mutable runtime objects for each battle.
const Config = preload("res://core/battle/config.gd")
# Browser compatibility default for armies without an explicit scenario budget.
const FACTION_UNIT_CAPS := {"undead": 600}
const DEFAULT_UNIT_CAP_OVERRIDE := 0
# Browser fill(): these armies keep figures above the cap in reserve waves instead of merging them.
const FACTION_RESERVE_WAVES := ["undead"]
@export var seed: int = 0
@export_enum("grass", "snow", "steppe", "arid") var biome: String = Config.DEFAULT_BIOME
@export var siege: bool = false
@export var quick: bool = false # Quick battle: every army above the cap fights in reserve waves.
@export_range(0.0, 1.0) var wall_damage: float = 0.0 # Siege only: battered walls widen the gate and cut defender supplies.
@export var wall_defense: Dictionary = {} # Siege only: {"stones": int, "oil": int}; empty uses the browser default.
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

func uses_reserve_waves(faction: String) -> bool:
	return quick or faction in FACTION_RESERVE_WAVES

func to_setup() -> ValueSetup:
	var values := ValueSetup.new()
	for field in ValueSetup.FIELDS:
		var value = get(field)
		values.set(field, value.duplicate(true) if value is Array or value is Dictionary else value)
	return values
