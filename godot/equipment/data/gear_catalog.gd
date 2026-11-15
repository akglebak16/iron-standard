extends "res://core/content/api/definition_catalog.gd"
## Validated, detached copy of EQ from src/01b_gear.js.
const Config = preload("res://equipment/config.gd")
const CONTENT_KEY := "gear"
const SLOTS := ["head", "body", "hands", "legs", "melee", "ranged", "shield", "horse"]
const ARMOR_SLOTS := ["head", "body", "hands", "legs"]
const WEAPON_SLOTS := ["melee", "ranged"]
const NUMERIC_FIELDS := ["tier", "price", "w", "v", "dmg", "spd", "reach", "hands", "arc", "cleave", "fall", "parry", "brk", "kb", "cd", "range", "acc", "pb", "bs", "rng", "unique"]
var _items: Dictionary = {}

func replace_data(data: Variant) -> bool:
	if _sealed: return false
	if not data is Dictionary or data.is_empty():
		return false
	for id in data:
		var item: Variant = data[id]
		if not id is String or not item is Dictionary or item.get("id") != id:
			return false
		if not item.get("name") is String or item.name.is_empty() or item.get("slot") not in SLOTS:
			return false
		for field in ["tier", "price", "w"]:
			if not _valid_number(item.get(field)):
				return false
		for field in NUMERIC_FIELDS:
			if item.has(field) and not _valid_number(item[field]):
				return false
		if item.tier != int(item.tier) or item.has("hands") and (item.hands != int(item.hands) or int(item.hands) not in [1, 2]):
			return false
		if item.slot in ARMOR_SLOTS or item.slot in ["shield", "horse"]:
			if not item.has("v"):
				return false
		if item.has("projectile_block_bonus"):
			if item.slot != "shield" or not _valid_number(item.projectile_block_bonus) or item.projectile_block_bonus > 1.0:
				return false
		if item.slot == "shield" and item.v > 1.0:
			return false
		if item.slot in WEAPON_SLOTS:
			if not item.has("dmg") or not item.has("hands") or not item.has("dt") or item.dt not in Config.DAMAGE_TYPE_ARMOR_PIERCE or not item.get("wt") is String:
				return false
		if item.slot == "melee" and (not item.has("spd") or item.spd <= 0.0):
			return false
		if item.slot == "ranged" and (not item.has("cd") or not item.has("range") or not item.has("acc") or item.cd <= 0.0 or item.range <= 0.0):
			return false
		if item.has("f"):
			if not item.f is Array:
				return false
			for faction in item.f:
				if not faction is String or faction.is_empty():
					return false
	_items = data.duplicate(true)
	_valid = true
	return true

func size() -> int:
	return _items.size()

func get_item(id: String) -> Dictionary:
	return _items.get(id, {}).duplicate(true)

func definitions() -> Dictionary:
	return _items.duplicate(true)

static func _valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= 0
