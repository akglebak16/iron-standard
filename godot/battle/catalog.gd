extends RefCounted

const DATA_PATH := "res://data/troops.json"
var troops: Dictionary = {}

func load_data() -> bool:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Troop catalog missing: " + DATA_PATH)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Troop catalog must be a JSON object")
		return false
	for id in parsed:
		var troop = parsed[id]
		if not troop is Dictionary or troop.get("id") != id or not troop.has_all(["name", "fac", "tier", "grp", "hp", "arm", "dmg", "spd", "mounted"]):
			push_error("Invalid troop definition: " + str(id))
			return false
		if int(troop.grp) < 0 or int(troop.grp) >= 3 or float(troop.hp) <= 0 or float(troop.spd) <= 0:
			push_error("Invalid troop stats: " + str(id))
			return false
	troops = parsed
	return true

func get_troop(id: String) -> Dictionary:
	return troops.get(id, {})
