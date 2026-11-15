extends "res://core/content/api/definition_catalog.gd"
const Config = preload("res://characters/config.gd")
const CONTENT_KEY := "companions"
var _definitions: Dictionary = {}

func replace_data(data: Variant) -> bool:
	if _sealed: return false
	if not data is Array or data.is_empty():
		return false
	var definitions := {}
	for entry in data:
		if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() or definitions.has(entry.id):
			return false
		if not entry.get("name") is String or entry.name.is_empty() or not entry.get("eq") is Dictionary or not entry.get("perks") is Array:
			return false
		if entry.get("sel") not in ["melee", "ranged"]:
			return false
		if not entry.get("a") is Array or entry.a.size() != Config.ATTRIBUTES.size():
			return false
		for stat in entry.a:
			if not _valid_number(stat):
				return false
		if not entry.get("grow") is Array or entry.grow.is_empty():
			return false
		for attribute in entry.grow:
			if attribute not in Config.ATTRIBUTES:
				return false
		if not entry.get("sk") is Dictionary or entry.sk.is_empty():
			return false
		for effect in entry.sk:
			var ranks: Variant = entry.sk[effect]
			if not effect is String or effect.is_empty() or not ranks is Array or ranks.size() != Config.PERK_MAX_RANK:
				return false
			for value in ranks:
				if not _valid_number(value):
					return false
		var voice: Variant = entry.get("voice", {})
		if not voice is Dictionary:
			return false
		for lines in voice.values():
			if not lines is Array:
				return false
			for line in lines:
				if not line is String or line.strip_edges().is_empty():
					return false
		definitions[entry.id] = entry
	_definitions = definitions.duplicate(true)
	_valid = true
	return true

func ids() -> Array:
	return _definitions.keys()

func size() -> int:
	return _definitions.size()

func get_companion(id: String) -> Dictionary:
	return _definitions.get(id, {}).duplicate(true)

static func _valid_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0.0
