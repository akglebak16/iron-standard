extends RefCounted
## Versioned, detached values only. No scene, file, object serialization or live references.
const World = preload("res://core/campaign/world/world_state.gd")
const Europe = preload("res://core/campaign/data/europe_data.gd")
const FIELDS := {
	"world": {"culture": TYPE_STRING, "seed_value": TYPE_INT, "home_id": TYPE_INT, "hours_passed": TYPE_INT, "journal": TYPE_ARRAY, "_hostile": TYPE_DICTIONARY},
	"clock": {"day": TYPE_INT, "hour": TYPE_INT, "speed": TYPE_INT, "paused": TYPE_BOOL, "_acc": TYPE_FLOAT, "_hour_acc": TYPE_FLOAT},
	"player": {"name": TYPE_STRING, "x": TYPE_FLOAT, "y": TYPE_FLOAT, "fx": TYPE_FLOAT, "path": TYPE_ARRAY, "pi": TYPE_INT,
		"troops": TYPE_ARRAY, "culture": TYPE_STRING, "gold": TYPE_INT, "enter_id": TYPE_INT, "tid": TYPE_INT, "rp": TYPE_FLOAT,
		"food": TYPE_INT, "inv": TYPE_DICTIONARY, "comps": TYPE_ARRAY, "quests": TYPE_ARRAY, "stats": TYPE_DICTIONARY,
		"hero": TYPE_DICTIONARY, "rel": TYPE_DICTIONARY, "busy": TYPE_STRING, "inside": TYPE_BOOL, "away": TYPE_BOOL,
		"liege": TYPE_STRING, "oath_day": TYPE_INT, "strikes": TYPE_INT, "summons": -1, "lure_day": TYPE_INT, "vass": TYPE_ARRAY},
	"map": {"settles": TYPE_ARRAY, "next_id": TYPE_INT},
	"roster": {"parties": TYPE_ARRAY, "_next_party_id": TYPE_INT, "clans_on": TYPE_BOOL},
	"wars": {"wars": TYPE_DICTIONARY, "campaigns": TYPE_DICTIONARY, "day": TYPE_INT, "hour": TYPE_INT, "_tally": TYPE_INT,
		"weary": TYPE_DICTIONARY, "truce": TYPE_DICTIONARY},
	"undead": {"crisis": TYPE_DICTIONARY, "day": TYPE_INT},
	"quests": {"next_id": TYPE_INT},
	"clans": {"clans": TYPE_ARRAY, "switched": TYPE_DICTIONARY, "rulers": TYPE_DICTIONARY, "next_id": TYPE_INT},
	"skirmish": {"fights": TYPE_ARRAY, "next_id": TYPE_INT, "hour_now": TYPE_INT},
	"companions": {"pos": TYPE_DICTIONARY, "saved": TYPE_DICTIONARY},
}
## Fields added to FIELDS after checkpoints were already made (ADR-002): an older checkpoint lacks them and loads with
## these values. Stage 2d of the AI: war weariness and truces of world_wars.gd.
const ADDED := {"wars": {"weary": {}, "truce": {}}}

static func capture(state: RefCounted) -> Dictionary:
	var data := {}
	for component in FIELDS:
		var source: RefCounted = state if component == "world" else state.get(component)
		if source == null: return {}
		var values := {}
		for field in FIELDS[component]: values[field] = source.get(field)
		data[component] = values
	data.rng = {"roster": {"seed": state.roster.rng.seed, "state": state.roster.rng.state},
		"market": {"seed": state.market.rng.seed, "state": state.market.rng.state}}
	return data.duplicate(true)

static func valid(data: Variant) -> bool:
	if not data is Dictionary or not _plain(data): return false
	if data.size() != FIELDS.size() + 1: return false
	for component in FIELDS:
		if not data.get(component) is Dictionary: return false
		var values: Dictionary = data[component]
		for field in values:
			if not FIELDS[component].has(field): return false
		for field in FIELDS[component]:
			if not values.has(field):
				if ADDED.get(component, {}).has(field): continue
				return false
			var expected: int = FIELDS[component][field]
			if expected >= 0 and typeof(values[field]) != expected: return false
			if expected < 0 and values[field] != null and not values[field] is Dictionary: return false
	if not data.get("rng") is Dictionary: return false
	for name in ["roster", "market"]:
		if not data.rng.get(name) is Dictionary: return false
		if not data.rng[name].get("seed") is int or not data.rng[name].get("state") is int: return false
	if not World.START_TROOPS.has(data.world.culture) or not World.START_TROOPS.has(data.player.culture): return false
	if data.clock.day < 1 or data.clock.hour < 0 or data.clock.hour >= 24 or data.clock.speed not in [1, 2, 4]: return false
	if data.clock._acc < 0.0 or data.clock._hour_acc < 0.0 or data.clock._hour_acc >= 1.0: return false
	if not _route(data.player.path, data.player.pi) or not _stacks(data.player.troops): return false
	var ids := {}
	var largest_id := -1
	for party in data.roster.parties:
		if not party is Dictionary or not party.get("id") is int or ids.has(party.id): return false
		ids[party.id] = true
		largest_id = maxi(largest_id, party.id)
		for key in ["kind", "fac", "name", "state"]:
			if not party.get(key) is String: return false
		for key in ["x", "y", "wait", "hold", "cd", "ai", "rp", "fx", "gold"]:
			if not _number(party.get(key)): return false
		if not party.get("hide") is bool or not _route(party.get("path"), party.get("pi")) or not _stacks(party.get("troops")): return false
		if not _goal(party): return false
	if data.roster._next_party_id <= largest_id: return false
	for campaign in data.wars.campaigns.values():
		if not _campaign(campaign): return false
	if not _diplomacy(data.wars): return false
	if data.undead.crisis.has("waves") and not _waves(data.undead.crisis.waves): return false
	ids.clear()
	largest_id = -1
	for settlement in data.map.settles:
		if not settlement is Dictionary or not settlement.get("id") is int or ids.has(settlement.id): return false
		ids[settlement.id] = true
		largest_id = maxi(largest_id, settlement.id)
		for key in ["name", "fac", "kind"]:
			if not settlement.get(key) is String: return false
		for key in ["x", "y", "rt", "respawn", "hv", "pros"]:
			if not _number(settlement.get(key)): return false
		if not _stacks(settlement.get("recruits")): return false
	if data.map.next_id <= largest_id or not ids.has(data.world.home_id): return false
	return true

static func restore(data: Dictionary, europe: Europe, definitions: Dictionary) -> RefCounted:
	if not valid(data): return null
	data = data.duplicate(true)
	var state := World.create(data.world.seed_value, europe, data.world.culture, definitions)
	if state == null: return null
	# Every component is already validated before any live object is populated.
	for component in FIELDS:
		var target: RefCounted = state if component == "world" else state.get(component)
		for field in FIELDS[component]:
			var value: Variant = data[component][field] if data[component].has(field) else ADDED[component][field].duplicate(true)
			target.set(field, value)
	state.roster.diplomatic_wars = state.wars.wars
	state.roster.rng.seed = data.rng.roster.seed
	state.roster.rng.state = data.rng.roster.state
	state.market.rng.seed = data.rng.market.seed
	state.market.rng.state = data.rng.market.state
	return state

static func _plain(value: Variant, depth: int = 0) -> bool:
	if depth > 32: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_VECTOR2: return value.is_finite()
		TYPE_ARRAY:
			if value.size() > 100000: return false
			for item in value:
				if not _plain(item, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			if value.size() > 100000: return false
			for key in value:
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_INT] or not _plain(value[key], depth + 1): return false
			return true
	return false

## AI goal of a party (party_goals.gd), absent in saves made before stage 2a: such a party has no goal yet.
static func _goal(party: Dictionary) -> bool:
	if party.has("goal") and not party.goal is String: return false
	if party.has("gid") and party.gid != null and not party.gid is int: return false
	for key in ["ga", "gs"]:
		if party.has(key) and not _number(party[key]): return false
	return true

## An offensive campaign of world_wars.gd. Stage 2b added marshal, s0 and keep; older saves lack them and the campaign
## goes on with the strongest lord as marshal and its present strength as the start.
static func _campaign(c: Variant) -> bool:
	if not c is Dictionary or not c.get("tid") is int or not c.get("gid") is int or not c.get("state") is String: return false
	if not c.get("army") is Array: return false
	for id in c.army:
		if not id is int: return false
	if c.get("marshal") != null and not c.marshal is int: return false
	if c.has("s0") and not _number(c.s0): return false
	if c.has("keep"):
		if not c.keep is Array: return false
		for id in c.keep:
			if not id is int: return false
	return true

## Wars, weariness and truces of world_wars.gd. Stage 2d added the gain of a war, `weary` and `truce`; older
## checkpoints lack them: no state is weary, no truce holds and a war has taken nothing yet.
static func _diplomacy(wars: Dictionary) -> bool:
	for k in wars.wars:
		var war: Variant = wars.wars[k]
		if not k is String or not war is Dictionary or not war.get("since") is int: return false
		if war.has("gain") and not _number_map(war.gain): return false
	if wars.has("weary") and not _number_map(wars.weary): return false
	if wars.has("truce"):
		for k in wars.truce:
			if not k is String or not wars.truce[k] is int: return false
	return true

static func _number_map(map: Variant) -> bool:
	if not map is Dictionary: return false
	for k in map:
		if not k is String or not _number(map[k]): return false
	return true

## Waves of the undead invasion (WorldUndead, stage 2c); saves made before it have none and the director picks them anew.
static func _waves(waves: Variant) -> bool:
	if not waves is Dictionary: return false
	for w in waves.values():
		if not w is Dictionary or not w.get("mode") in ["gather", "attack"]: return false
		for key in ["tid", "t0", "tt", "tw"]:
			if not w.get(key) is int: return false
		for key in ["rx", "ry", "sc"]:
			if not _number(w.get(key)): return false
		if not w.get("bad") is Array: return false
		for id in w.bad:
			if not id is int: return false
	return true

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _route(route: Variant, index: Variant) -> bool:
	# Existing AI clears finished routes without resetting pi; pi >= size means idle.
	if not route is Array or not index is int or index < 0: return false
	for point in route:
		if not point is Vector2 or not point.is_finite(): return false
	return true

static func _stacks(stacks: Variant) -> bool:
	if not stacks is Array: return false
	for stack in stacks:
		if not stack is Dictionary or not stack.get("type") is String or not stack.get("n") is int or stack.n < 0: return false
	return true
