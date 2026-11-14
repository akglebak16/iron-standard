extends RefCounted
## Validated definitions; callers receive copies, never shared mutable records.
const Config = preload("res://troops/config.gd")
const DATA_PATH := "res://troops/data/troops.json"
const REQUIRED_NUMBERS := ["tier", "grp", "hp", "arm", "dmg", "spd", "cd", "block"]
const OPTIONAL_NUMBERS := ["range", "reach", "acc", "pierce", "shb", "pw"]
var _troops: Dictionary = {}

func load_data() -> bool:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null or not replace_data(JSON.parse_string(file.get_as_text())):
		push_error("Invalid or missing troop catalog: " + DATA_PATH)
		return false
	return true

func replace_data(data: Variant) -> bool:
	# Validate before replacing: a rejected reload leaves the working catalog intact.
	if not data is Dictionary or data.is_empty():
		return false
	for id in data:
		var troop: Variant = data[id]
		if not id is String or not troop is Dictionary or troop.get("id") != id:
			return false
		for field in ["name", "fac"]:
			if not troop.get(field) is String or troop[field].is_empty():
				return false
		if not troop.get("mounted") is bool:
			return false
		for field in REQUIRED_NUMBERS:
			if not _valid_number(troop.get(field)):
				return false
		for field in OPTIONAL_NUMBERS:
			if troop.has(field) and not _valid_number(troop[field]):
				return false
		if troop.grp != int(troop.grp) or troop.grp < Config.GROUP_INFANTRY or troop.grp > Config.GROUP_CAVALRY:
			return false
		if troop.hp <= 0 or troop.spd <= 0 or troop.cd <= 0 or troop.block > 1 or troop.get("shb", 0) > 1:
			return false
		if troop.has("look") and not troop.look is Dictionary:
			return false
	_troops = data.duplicate(true)
	return true

func size() -> int:
	return _troops.size()

func get_troop(id: String) -> Dictionary:
	return _troops.get(id, {}).duplicate(true)

static func _valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= 0
