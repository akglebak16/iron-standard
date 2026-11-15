extends RefCounted
## Putting gear on and off a hero or a companion from the cargo hold (heroEq, syncLegacy, doEquip, doUnequip, doWield in
## src/01b_gear.js and src/05d_trade.js). `inv` is the party's cargo: item id -> count.
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const HeroGear = preload("res://equipment/rules/hero_gear.gd")

## Turns the old index-based kit into slots once (heroEq).
static func ensure(h: Dictionary) -> Dictionary:
	if h.get("eq") is Dictionary:
		return h.eq
	var pick := func(ids: Array, i: Variant, fallback: Variant) -> Variant:
		var k := int(i) if i != null else -1
		return ids[k] if k >= 0 and k < ids.size() and String(ids[k]) != "" else fallback
	h.eq = {"head": HeroGear.DEFAULT_HEAD, "body": pick.call(HeroGear.LEGACY_ARMOR, h.get("armor"), null), "hands": null, "legs": null,
		"melee": pick.call(HeroGear.LEGACY_WEAPONS, h.get("weapon"), HeroGear.DEFAULT_MELEE), "ranged": null,
		"shield": pick.call(HeroGear.LEGACY_SHIELDS, h.get("shield"), null), "horse": pick.call(HeroGear.LEGACY_HORSES, h.get("horse"), null)}
	h.sel = "melee"
	sync_legacy(h)
	return h.eq

## The map still reads the horse index (party speed, cargo).
static func sync_legacy(h: Dictionary) -> void:
	var horse: Variant = h.eq.get("horse")
	h.horse = (2 if horse == "horse_war" else 1) if horse != null and String(horse) != "" else 0

static func _add(inv: Dictionary, id: String, n: int) -> void:
	inv[id] = int(inv.get(id, 0)) + n
	if inv[id] <= 0:
		inv.erase(id)

## {ok, note}: the item leaves the cargo, whatever was in that slot goes back to it.
static func equip(inv: Dictionary, h: Dictionary, id: String, catalog: GearCatalog) -> Dictionary:
	var it := catalog.get_item(id)
	if it.is_empty() or int(inv.get(id, 0)) < 1:
		return {"ok": false, "note": ""}
	var eq := ensure(h)
	var melee := catalog.get_item(String(eq.melee)) if eq.get("melee") != null else {}
	if it.slot == "shield" and int(melee.get("hands", 1)) == 2:
		return {"ok": false, "note": "Со двуручным оружием щит не носят."}
	var note := ""
	var old: Variant = eq.get(it.slot)
	_add(inv, id, -1)
	if old != null and String(old) != "":
		_add(inv, String(old), 1)
	eq[it.slot] = id
	if it.slot == "melee" and int(it.get("hands", 1)) == 2 and eq.get("shield") != null:
		_add(inv, String(eq.shield), 1)
		eq.shield = null
		note = "Щит убран в обоз: двуручное оружие."
	if it.slot == "horse":
		sync_legacy(h)
	return {"ok": true, "note": note}

static func unequip(inv: Dictionary, h: Dictionary, slot: String) -> bool:
	var eq := ensure(h)
	var id: Variant = eq.get(slot)
	if id == null or String(id) == "":
		return false
	_add(inv, String(id), 1)
	eq[slot] = null
	if slot == "horse":
		sync_legacy(h)
	if slot == "ranged" and h.get("sel") == "ranged":
		h.sel = "melee"
	return true

## Which weapon is in hand when a battle starts.
static func wield(h: Dictionary, sel: String) -> bool:
	var eq := ensure(h)
	if sel == "ranged" and (eq.get("ranged") == null or String(eq.ranged) == ""):
		return false
	h.sel = sel
	return true
