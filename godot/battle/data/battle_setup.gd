extends RefCounted
## Detached encounter values. File-backed authoring lives in adapters/godot/resources.
const Config = preload("res://battle/config.gd")
# Browser compatibility default for armies without an explicit scenario budget.
const FACTION_UNIT_CAPS := {"undead": 600}
const DEFAULT_UNIT_CAP_OVERRIDE := 0
# Browser fill(): these armies keep figures above the cap in reserve waves instead of merging them.
const FACTION_RESERVE_WAVES := ["undead"]
var seed: int = 0
var biome: String = Config.DEFAULT_BIOME
var siege: bool = false
var quick: bool = false # Quick battle: every army above the cap fights in reserve waves.
var wall_damage: float = 0.0 # Siege only: battered walls widen the gate and cut defender supplies.
var wall_defense: Dictionary = {} # Siege only: {"stones": int, "oil": int}; empty uses the browser default.
var player_faction: String = ""
var enemy_faction: String = ""
var player_unit_cap: int = DEFAULT_UNIT_CAP_OVERRIDE
var enemy_unit_cap: int = DEFAULT_UNIT_CAP_OVERRIDE
var enemy_leader_name: String = "" # Empty means no named leader.
var player_army: Array[Dictionary] = []
var enemy_army: Array[Dictionary] = []
var hero_troop: String = ""
var hero_profile: Dictionary = {} # Empty keeps the existing troop-based preview hero.
var companion_profiles: Array[Dictionary] = [] # All hired companions, including injured ones.
var hero_position : Vector2 = Vector2.ZERO

func unit_cap(faction: String, override: int) -> int:
	return int(FACTION_UNIT_CAPS.get(faction, Config.SOLO_UNIT_CAP)) if override == DEFAULT_UNIT_CAP_OVERRIDE else override

func uses_reserve_waves(faction: String) -> bool:
	return quick or faction in FACTION_RESERVE_WAVES

const FIELDS := ["seed","biome","siege","quick","wall_damage","wall_defense","player_faction","enemy_faction","player_unit_cap","enemy_unit_cap","enemy_leader_name","player_army","enemy_army","hero_troop","hero_profile","companion_profiles","hero_position"]

func duplicate(deep: bool = true) -> RefCounted:
	var values := new()
	for field in FIELDS:
		var value = get(field)
		values.set(field, value.duplicate(deep) if value is Array or value is Dictionary else value)
	return values
