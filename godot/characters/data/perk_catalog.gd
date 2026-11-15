extends RefCounted
## Validated definitions from src/01c_perks.js; callers receive detached values.
const Config = preload("res://characters/config.gd")
const DATA_PATH := "res://characters/data/perks.json"
var _perks: Dictionary = {}
var _zero: Dictionary = {}

func load_data() -> bool:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null or not replace_data(JSON.parse_string(file.get_as_text())):
		push_error("Invalid or missing perk catalog: " + DATA_PATH)
		return false
	return true

func replace_data(data: Variant) -> bool:
	if not data is Dictionary or not data.get("perks") is Array or not data.get("zero") is Dictionary:
		return false
	var zero: Dictionary = data.zero
	if zero.is_empty():
		return false
	for key in zero:
		if not key is String or not _valid_number(zero[key]) or zero[key] != 0:
			return false
	var perks := {}
	for entry in data.perks:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() or perks.has(entry.id):
			return false
		if not entry.get("n") is String or entry.n.is_empty() or entry.get("a") not in Config.ATTRIBUTES:
			return false
		if not entry.get("req") is Array or entry.req.size() != Config.PERK_MAX_RANK or not entry.get("fx") is Dictionary or entry.fx.is_empty():
			return false
		for requirement in entry.req:
			if not _valid_number(requirement) or requirement != int(requirement):
				return false
		for effect in entry.fx:
			if not zero.has(effect) or not entry.fx[effect] is Array or entry.fx[effect].size() != Config.PERK_MAX_RANK:
				return false
			for value in entry.fx[effect]:
				if not _valid_number(value):
					return false
		perks[entry.id] = entry
	if perks.is_empty():
		return false
	_perks = perks.duplicate(true)
	_zero = zero.duplicate(true)
	return true

func size() -> int:
	return _perks.size()

func get_perk(id: String) -> Dictionary:
	return _perks.get(id, {}).duplicate(true)

func zero_effects() -> Dictionary:
	return _zero.duplicate(true)

static func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0.0

## Every perk in the order of the browser's panel.
func list() -> Array[Dictionary]:
	var perks: Array[Dictionary] = []
	for perk in _perks.values():
		perks.append(perk.duplicate(true))
	return perks
