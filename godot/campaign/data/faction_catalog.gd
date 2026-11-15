extends RefCounted
## Faction looks and names exported from FACTIONS in src/01_core.js (campaign/tools/export_world.cjs).
const PATH := "res://campaign/data/factions.json"

var factions: Dictionary = {}

func load_data() -> bool:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	factions = parsed
	return true

func get_faction(id: String) -> Dictionary:
	return factions.get(id, factions.get("bandit", {}))
