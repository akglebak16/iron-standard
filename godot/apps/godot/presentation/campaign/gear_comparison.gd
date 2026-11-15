extends RefCounted
## "Что изменится, если надеть" for the inventory (gearComparison in src/06h_polish.js). Pure: copies the profile,
## applies the equip rules to the copy and compares the two HeroStats previews. UI text lives here (presentation).
const HeroGear = preload("res://core/equipment/rules/hero_gear.gd")
const HeroEquip = preload("res://core/equipment/rules/hero_equip.gd")
const PerkEffects = preload("res://core/characters/rules/perk_effects.gd")

## [key in HeroStats.preview, label, scale, lower_is_better]
const ROWS := [["damage", "Урон", 1.0, false], ["armor", "Броня", 1.0, false], ["speed", "Скорость", 1.0, false],
	["attack_interval_seconds", "Удар / перезарядка, с", 1.0, true], ["block", "Блок, %", 100.0, false]]

## {title, note, rows:[{name, old, next, delta, trend}]}; trend is 1 better, -1 worse, 0 same. `note` explains refusals.
## `preview` is HeroStats.preview(profile, gear, effects), handed in by composition (presentation may not import core/battle).
static func compare(profile: Dictionary, item: Dictionary, catalog, perks, preview: Callable) -> Dictionary:
	if item.is_empty() or not item.has("slot") or not preview.is_valid():
		return {}
	var before := profile.duplicate(true)
	var eq: Dictionary = HeroEquip.ensure(before)
	var current: Dictionary = catalog.get_item(String(eq.get(item.slot, ""))) if eq.get(item.slot) != null else {}
	var title := "%s · вместо: %s" % [profile.get("name", ""), current.get("name", "пустого слота")]
	var after := before.duplicate(true)
	var inventory := {String(item.id): 1}
	var result := HeroEquip.equip(inventory, after, String(item.id), catalog)
	if not result.ok:
		return {"title": title, "note": result.note, "rows": []}
	if item.slot == "melee" or item.slot == "ranged":
		before.sel = item.slot
		after.sel = item.slot
	var effects: Dictionary = PerkEffects.own(profile, perks)
	var then: Dictionary = preview.call(before, HeroGear.resolve(before, catalog), effects)
	var now: Dictionary = preview.call(after, HeroGear.resolve(after, catalog), effects)
	var rows: Array = []
	for def in ROWS:
		var old := snappedf(float(then[def[0]]) * float(def[2]), 0.1)
		var next := snappedf(float(now[def[0]]) * float(def[2]), 0.1)
		var delta := snappedf(next - old, 0.1)
		var trend := 0 if is_zero_approx(delta) else (1 if (delta < 0.0) == bool(def[3]) else -1)
		rows.append({"name": def[1], "old": old, "next": next, "delta": delta, "trend": trend})
	var note := "Щит уйдёт в рюкзак." if result.note != "" else ""
	return {"title": title, "note": note, "rows": rows}

static func fmt(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")

static func line(r: Dictionary) -> String:
	var d := float(r.delta)
	return "%s: %s → %s (%s%s)" % [r.name, fmt(r.old), fmt(r.next), "+" if d > 0.0 else "", fmt(d)]

## Plain text for tooltips.
static func text(cmp: Dictionary) -> String:
	if cmp.is_empty():
		return ""
	var out: Array = [cmp.title]
	for r in cmp.rows:
		out.append(line(r))
	if cmp.note != "":
		out.append(cmp.note)
	return "\n".join(out)
