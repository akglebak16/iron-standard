extends RefCounted
## Detached heroEq()/heroWield()/heroShield()/heroArmor()/heroGear() projection.
const GearCatalog = preload("res://core/equipment/data/gear_catalog.gd")
const SLOTS := ["head", "body", "hands", "legs", "melee", "ranged", "shield", "horse"]
const ARMOR_SLOTS := ["head", "body", "hands", "legs"]
const LEGACY_WEAPONS := ["sword_old", "sword_knight", "sword_master", "sword_damask"]
const LEGACY_ARMOR := ["body_padded", "body_mail", "body_scale", "body_plate"]
const LEGACY_SHIELDS := ["shield_plank", "shield_banded", "shield_heraldic"]
const LEGACY_HORSES := ["", "horse_riding", "horse_war"]
const DEFAULT_HEAD := "head_cap"
const DEFAULT_MELEE := "sword_old"
const MELEE := "melee"
const RANGED := "ranged"
const FIST := {"id": "fist", "name": "Кулаки", "slot": "melee", "wt": "fist", "dt": "blunt", "dmg": 8.0, "spd": 0.9, "reach": -3.0, "hands": 1, "arc": 1.0, "cleave": 3, "fall": 0.7, "parry": 0.1, "look": null}

static func resolve(profile: Dictionary, catalog: GearCatalog) -> Dictionary:
	if catalog == null:
		return {}
	var slots: Dictionary = {}
	var selection := "melee"
	if profile.has("eq"):
		if not profile.eq is Dictionary:
			return {}
		for slot in SLOTS:
			slots[slot] = str(profile.eq.get(slot, "")) if profile.eq.get(slot) != null else ""
		selection = str(profile.get("sel", "melee"))
	else:
		slots = {"head": DEFAULT_HEAD, "body": _legacy_id(LEGACY_ARMOR, profile.get("armor", -1)), "hands": "", "legs": "", "melee": _legacy_id(LEGACY_WEAPONS, profile.get("weapon", -1), DEFAULT_MELEE), "ranged": "", "shield": _legacy_id(LEGACY_SHIELDS, profile.get("shield", -1)), "horse": _legacy_id(LEGACY_HORSES, profile.get("horse", -1))}
	var melee := _item(catalog, slots, MELEE)
	if melee.is_empty():
		melee = FIST.duplicate(true)
	var ranged := _item(catalog, slots, RANGED)
	var weapon := ranged if selection == RANGED and not ranged.is_empty() else melee
	var shield := _item(catalog, slots, "shield") if int(weapon.get("hands", 1)) < 2 else {}
	var horse := _item(catalog, slots, "horse")
	var armor := 0.0
	for slot in ARMOR_SLOTS:
		armor += float(_item(catalog, slots, slot).get("v", 0.0))
	var look := {
		"helm": _item(catalog, slots, "head").get("look", "none"),
		"armor": _item(catalog, slots, "body").get("look", "tunic"),
		"weapon": weapon.get("look"),
		"shield": shield.get("look", "none"),
		"horse": horse.get("look"),
	}
	# heroLook in src/02_art.js: the hero's own face comes from his seed, beard chance (1 unless set) and hair.
	if profile.get("seed") is int or profile.get("seed") is float:
		look.seed = int(profile.seed)
		look.beard = profile.get("beard", 1) if profile.get("beard") != null else 1
		if profile.get("hair") is String:
			look.hair = profile.hair
	return {"slots": slots, "selection": selection, "weapon": weapon, "shield": shield, "horse": horse, "mounted": not horse.is_empty(), "armor": armor, "block": float(shield.get("v", weapon.get("parry", 0.0))), "look": look,
		"weapon_names": {MELEE: melee.name, RANGED: ranged.get("name", "")}}

static func _item(catalog: GearCatalog, slots: Dictionary, slot: String) -> Dictionary:
	var item: Dictionary = catalog.get_item(str(slots.get(slot, "")))
	return item if item.get("slot", "") == slot else {}

static func _legacy_id(ids: Array, index: Variant, fallback: String = "") -> String:
	if not index is int and not index is float or not is_finite(float(index)) or index != int(index) or index < 0 or index >= ids.size():
		return fallback
	return str(ids[int(index)])
