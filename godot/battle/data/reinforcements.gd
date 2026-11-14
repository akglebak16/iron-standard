extends RefCounted
## Port of src/03_battle.js battleWaves(): reserve figures enter from the field edge on a morale check.
## Lives in data because it turns stored troop definitions into new runtime units.
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Event = preload("res://battle/combat_event.gd")
const ArmyBuilder = preload("res://battle/data/army_builder.gd")

## `active` holds combat-ready units per side counted before this check's routs, as in the browser.
static func release(battle: State, active: Array, rng: RandomNumberGenerator, factions: Array) -> void:
	for side in 2:
		var waiting: Array = battle.reserve[side]
		if waiting.is_empty():
			continue
		var cap: int = battle.reserve_caps[side]
		var wave := roundi(cap * Config.RESERVE_WAVE_SHARE)
		var room: int = cap - int(active[side])
		if room < wave and active[side] > 0:
			continue
		var count := mini(waiting.size(), mini(room, wave))
		if count <= 0:
			continue
		var edge_x: float = battle.arena_size.x - Config.RESERVE_EDGE_OFFSET if side == 1 else Config.RESERVE_EDGE_OFFSET
		var touched := {}
		var factions_seen := {}
		for troop_id in waiting.slice(0, count):
			var troop: Dictionary = battle.reserve_definitions[troop_id]
			var at := Vector2(edge_x + rng.randf_range(-Config.RESERVE_SPAWN_X_JITTER, Config.RESERVE_SPAWN_X_JITTER),
				battle.arena_size.y / 2.0 + rng.randf_range(-Config.RESERVE_SPAWN_Y_SPREAD, Config.RESERVE_SPAWN_Y_SPREAD))
			var unit: Unit = ArmyBuilder.create_unit(battle, side, troop_id, troop, str(factions[side]), at, 1.0, rng)
			battle.add_grouped_unit(unit, int(troop.grp))
			touched[unit.group_kind] = true
			factions_seen[str(troop.get("fac", ""))] = true
		waiting.assign(waiting.slice(count))
		active[side] += count
		for kind in touched:
			battle.groups[side][kind].layout()
		battle.record_notice(Event.Kind.RESERVE_WAVE, {"side": side, "count": count, "remaining": waiting.size(), "troop_factions": factions_seen.keys()})
