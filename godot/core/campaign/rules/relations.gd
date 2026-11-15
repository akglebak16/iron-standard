extends RefCounted
const Config = preload("res://core/campaign/config.gd")

static func reward(party: Dictionary, faction: String, amount: int) -> void:
	if faction.is_empty():
		return
	var values: Dictionary = party.get("rel", {})
	values[faction] = clampi(int(values.get(faction, 0)) + amount, Config.RELATION_MIN, Config.RELATION_MAX)
	party.rel = values

static func refresh(party: Dictionary, factions: Array) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	var values: Dictionary = party.get("rel", {})
	var known: bool = party.has("hostF")
	var hostility: Dictionary = party.get("hostF", {})
	for faction in factions:
		if not values.has(faction):
			values[faction] = 0
		var hostile: bool = values[faction] < Config.HOSTILE_BELOW
		if known and hostile != bool(hostility.get(faction, false)):
			changes.append({"faction": faction, "hostile": hostile})
		hostility[faction] = hostile
	party.rel = values
	party.hostF = hostility
	return changes
