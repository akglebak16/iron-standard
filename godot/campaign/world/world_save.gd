extends RefCounted
## Versioned values-only checkpoint envelope; accepts the original JSON v1 format.
## Static terrain is regenerated from the seed; mutable state retains its exact types.
const WorldState = preload("res://campaign/world/world_state.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const Checkpoint = preload("res://campaign/world/world_checkpoint.gd")
const VERSION := 2
const MAX_PAYLOAD_BYTES := 16 * 1024 * 1024
const SETTLEMENT_FIELDS := ["fac", "name", "recruits", "rt", "camp", "cleared", "respawn", "hv", "pros", "market", "gar", "cult", "siege", "ruin", "dmg", "board", "owner", "food", "talkT", "fire", "barrow", "burnt", "ruinOf", "name0", "vass", "blk"]
const PARTY_INT_KEYS := ["id", "home", "sid", "tid", "lid", "src", "clan", "owner", "relief", "fight"]

static func to_dict(state: RefCounted) -> Dictionary:
	var values := Checkpoint.capture(state)
	if not Checkpoint.valid(values): return {}
	var payload := Marshalls.raw_to_base64(var_to_bytes(values))
	return {"version": VERSION, "encoding": "godot-variant-values-v1", "payload": payload, "sha256": payload.sha256_text()}

## Retained only as the v1 migration fixture/export contract.
static func to_v1_dict(state: RefCounted) -> Dictionary:
	var p = state.player
	var settles := {}
	for s in state.map.settles:
		var d := {}
		for k in SETTLEMENT_FIELDS:
			d[k] = s.get(k)
		settles[str(s.id)] = d
	var parties: Array = []
	for q in state.roster.parties:
		var c: Dictionary = q.duplicate(true)
		var path: Array = []
		for v in q.path:
			path.append([v.x, v.y])
		c.path = path
		parties.append(c)
	return {"version": 1, "seed": state.seed_value, "culture": state.culture,
		"clock": {"day": state.clock.day, "hour": state.clock.hour, "speed": state.clock.speed},
		"player": {"x": p.x, "y": p.y, "troops": p.troops, "culture": p.culture, "gold": p.gold, "food": p.food, "inv": p.inv,
			"comps": p.comps, "quests": p.quests, "stats": p.stats, "hero": p.hero, "rel": p.rel,
			"liege": p.liege, "oath_day": p.oath_day, "strikes": p.strikes, "summons": p.summons, "lure_day": p.lure_day, "vass": p.vass},
		"wars": state.wars.wars, "campaigns": state.wars.campaigns, "tally": state.wars._tally, "settles": settles, "parties": parties, "journal": state.journal, "quest_id": state.quests.next_id, "crisis": state.undead.crisis, "clans": state.clans.to_dict(), "skirmish": state.skirmish.to_dict(), "companions": state.companions.to_dict(), "next_party_id": state.roster._next_party_id}

## Rebuilds a world from saved data; returns null for an unknown format.
static func from_dict(data: Dictionary, europe: EuropeData) -> RefCounted:
	if data.get("version") == 1:
		if not _valid_v1_header(data): return null
		return _from_v1(data.duplicate(true), europe)
	if data.get("version") != VERSION or data.get("encoding") != "godot-variant-values-v1": return null
	if not data.get("payload") is String or not data.get("sha256") is String: return null
	if data.payload.length() > MAX_PAYLOAD_BYTES * 4 / 3 + 4 or data.payload.sha256_text() != data.sha256: return null
	var bytes := Marshalls.base64_to_raw(data.payload)
	if bytes.is_empty() or bytes.size() > MAX_PAYLOAD_BYTES or Marshalls.raw_to_base64(bytes) != data.payload: return null
	# This API does not deserialize Objects; never use bytes_to_var_with_objects here.
	var values = bytes_to_var(bytes)
	if not values is Dictionary: return null
	return Checkpoint.restore(values, europe)

static func _valid_v1_header(data: Dictionary) -> bool:
	if not Checkpoint._plain(data) or not Checkpoint._number(data.get("seed")) or not WorldState.START_TROOPS.has(data.get("culture")): return false
	for field in ["clock", "player", "settles"]:
		if not data.get(field) is Dictionary: return false
	for field in ["parties", "journal"]:
		if not data.get(field) is Array: return false
	for field in ["day", "hour", "speed"]:
		if not Checkpoint._number(data.clock.get(field)): return false
	if data.clock.day < 1 or data.clock.hour < 0 or data.clock.hour >= 24 or int(data.clock.speed) not in [1, 2, 4] or data.clock.speed != int(data.clock.speed): return false
	if not Checkpoint._number(data.get("next_party_id")): return false
	for field in ["x", "y", "gold", "food"]:
		if not Checkpoint._number(data.player.get(field)): return false
	if not WorldState.START_TROOPS.has(data.player.get("culture")): return false
	for field in ["inv", "stats", "hero", "rel"]:
		if not data.player.get(field) is Dictionary: return false
	for field in ["troops", "comps", "quests"]:
		if not data.player.get(field) is Array: return false
	if not _v1_stacks(data.player.troops) or not _rows(data.player.comps) or not _rows(data.player.quests): return false
	if not _rows(data.player.get("vass", [])): return false
	for vassal in data.player.get("vass", []):
		if not vassal.get("c") is Dictionary or not Checkpoint._number(vassal.get("sid")): return false
	var summons = data.player.get("summons")
	if summons != null and (not summons is Dictionary or not _numbers(summons, ["tid", "until"])): return false
	var ids := {}
	for party in data.parties:
		if not party is Dictionary or not _numbers(party, ["id", "x", "y", "pi", "wait", "hold", "cd", "ai", "rp", "fx", "gold"]): return false
		if ids.has(int(party.id)) or party.id != int(party.id): return false
		ids[int(party.id)] = true
		if int(data.next_party_id) <= int(party.id): return false
		for field in ["kind", "fac", "name", "state"]:
			if not party.get(field) is String: return false
		if not party.get("hide") is bool or not _v1_stacks(party.get("troops")) or not party.get("path") is Array: return false
		for point in party.path:
			if not point is Array or point.size() != 2 or not Checkpoint._number(point[0]) or not Checkpoint._number(point[1]): return false
	for saved in data.settles.values():
		if not saved is Dictionary: return false
		for field in ["recruits", "gar"]:
			if saved.get(field) != null and not _v1_stacks(saved[field]): return false
		if saved.get("board") != null and not _rows(saved.board): return false
		for field in ["market", "siege", "blk"]:
			if saved.get(field) != null and not saved[field] is Dictionary: return false
		if saved.get("market") != null:
			if not _numbers(saved.market, ["day", "gold"]) or not _number_map(saved.market.get("stock")): return false
		if saved.get("siege") != null:
			if not _numbers(saved.siege, ["t0", "g0"]): return false
			if saved.siege.has("rel") and not _number_array(saved.siege.rel): return false
	for field in ["wars", "campaigns", "clans", "companions", "skirmish", "crisis"]:
		if not data.get(field, {}) is Dictionary: return false
	for war in data.get("wars", {}).values():
		if not war is Dictionary or not _numbers(war, ["since"]): return false
	for campaign in data.get("campaigns", {}).values():
		if not campaign is Dictionary or not _numbers(campaign, ["tid", "gid"]) or not _number_array(campaign.get("army")): return false
	var clans: Dictionary = data.get("clans", {})
	if not _rows(clans.get("clans", [])) or not clans.get("rulers", {}) is Dictionary or not _number_map(clans.get("switched", {})): return false
	for ruler in clans.get("rulers", {}).values():
		if not ruler is Dictionary: return false
	var companions: Dictionary = data.get("companions", {})
	if not _number_map(companions.get("pos", {})) or not companions.get("saved", {}) is Dictionary: return false
	for profile in companions.get("saved", {}).values():
		if not profile is Dictionary: return false
	var fights = data.get("skirmish", {}).get("fights", [])
	if not _rows(fights): return false
	for fight in fights:
		if not _numbers(fight, ["id", "t0", "a0", "b0"]) or not _number_array(fight.get("A")) or not _number_array(fight.get("B")): return false
	var crisis: Dictionary = data.get("crisis", {})
	if not crisis.is_empty() and (not _numbers(crisis, ["day"]) or not _number_array(crisis.get("src")) or not _number_map(crisis.get("left"))): return false
	return true

static func _rows(value: Variant) -> bool:
	if not value is Array: return false
	for row in value:
		if not row is Dictionary: return false
	return true

static func _numbers(value: Dictionary, fields: Array) -> bool:
	for field in fields:
		if not Checkpoint._number(value.get(field)): return false
	return true

static func _number_array(value: Variant) -> bool:
	if not value is Array: return false
	for item in value:
		if not Checkpoint._number(item): return false
	return true

static func _number_map(value: Variant) -> bool:
	return value is Dictionary and _number_array(value.values())

static func _v1_stacks(value: Variant) -> bool:
	if not _rows(value): return false
	for stack in value:
		if not stack.get("type") is String or not Checkpoint._number(stack.get("n")) or stack.n < 0 or stack.n != int(stack.n): return false
	return true

static func _from_v1(data: Dictionary, europe: EuropeData) -> RefCounted:
	var state := WorldState.create(int(data.seed), europe, String(data.culture))
	if state == null: return null
	state.clock.day = int(data.clock.day)
	state.clock.hour = int(data.clock.hour)
	state.clock.speed = int(data.clock.speed)
	var pd: Dictionary = data.player
	var p = state.player
	p.x = float(pd.x)
	p.y = float(pd.y)
	p.stop()
	p.troops = _stacks(pd.troops)
	p.culture = String(pd.culture)
	p.gold = int(pd.gold)
	p.food = int(pd.food)
	p.inv = _ints(pd.inv)
	p.comps = pd.comps
	p.quests = _quests(pd.quests)
	p.stats = _ints(pd.stats)
	p.hero = _hero(pd.hero)
	p.rel = pd.rel
	p.liege = String(pd.get("liege", ""))
	p.oath_day = int(pd.get("oath_day", 0))
	p.strikes = int(pd.get("strikes", 0))
	p.lure_day = int(pd.get("lure_day", -99))
	p.vass = []
	for v in pd.get("vass", []):
		var x: Dictionary = v.duplicate(true)
		x.sid = int(x.sid)
		x.rest = int(x.get("rest", 0))
		if x.get("pid") != null:
			x.pid = int(x.pid)
		for k in ["lvl", "xp", "pts", "pp", "seed", "str", "vit", "agi", "int", "cha"]:
			if x.c.get(k) != null:
				x.c[k] = int(x.c[k])
		p.vass.append(x)
	p.summons = pd.get("summons")
	if p.summons is Dictionary:
		p.summons.tid = int(p.summons.tid)
		p.summons.until = int(p.summons.until)
	for s in state.map.settles:
		var saved: Variant = data.settles.get(str(s.id))
		if saved == null:
			continue
		for k in SETTLEMENT_FIELDS:
			if saved.get(k) != null or k == "camp":
				s[k] = saved.get(k)
		s.recruits = _stacks(s.recruits)
		if s.get("board") is Array:
			s.board = _quests(s.board)
		if s.get("owner") != null:
			s.owner = int(s.owner)
		if s.get("burnt") != null:
			s.burnt = int(s.burnt)
		if s.get("ruin") != null:
			s.ruin = int(s.ruin)
		if s.get("talkT") != null:
			s.talkT = int(s.talkT)
		if s.get("gar") is Array:
			s.gar = _stacks(s.gar)
		if s.get("siege") is Dictionary:
			s.siege.t0 = int(s.siege.t0)
			s.siege.g0 = int(s.siege.g0)
			for key in ["relN", "relAt", "sally"]:
				if s.siege.has(key):
					s.siege[key] = int(s.siege[key])
			if s.siege.has("rel"):
				s.siege.rel = s.siege.rel.map(func(x): return int(x))
		if s.get("blk") is Dictionary:
			for key in ["t0", "g0", "away"]:
				s.blk[key] = int(s.blk.get(key, 0))
		if s.get("fire") != null:
			s.fire = int(s.fire)
		for key in ["rt", "respawn", "hv", "pros"]:
			s[key] = int(s[key])
		if s.camp != null:
			s.camp = int(s.camp)
		if s.get("market") is Dictionary:
			s.market.day = int(s.market.day)
			s.market.gold = int(s.market.gold)
			s.market.stock = _ints(s.market.stock)
		else:
			s.erase("market")
	state.roster.parties.clear()
	for q in data.parties:
		var party: Dictionary = q.duplicate(true)
		for key in PARTY_INT_KEYS:
			if party.get(key) != null:
				party[key] = int(party[key])
		party.troops = _stacks(party.troops)
		var path: Array = []
		for a in party.path:
			path.append(Vector2(a[0], a[1]))
		party.path = path
		party.pi = int(party.pi)
		state.roster.parties.append(party)
	state.roster._next_party_id = int(data.next_party_id)
	state.quests.next_id = int(data.get("quest_id", state.quests.next_id))
	state.companions.from_dict(data.get("companions", {}))
	state.clans.from_dict(data.get("clans", {}))
	state.skirmish.from_dict(data.get("skirmish", {}))
	var crisis: Dictionary = data.get("crisis", {})
	if not crisis.is_empty():
		crisis.day = int(crisis.day)
		var src: Array = []
		for id in crisis.src:
			src.append(int(id))
		crisis.src = src
		for k in crisis.left:
			crisis.left[k] = int(crisis.left[k])
		state.undead.crisis = crisis
	for c in p.comps:
		for k in ["lvl", "xp", "pts", "pp", "seed", "str", "vit", "agi", "int", "cha"]:
			if c.get(k) != null:
				c[k] = int(c[k])
	state.wars.wars.clear()
	for k in data.get("wars", {}):
		state.wars.wars[k] = {"since": int(data.wars[k].since)}
	state.wars.campaigns.clear()
	for f in data.get("campaigns", {}):
		var c: Dictionary = data.campaigns[f]
		c.tid = int(c.tid)
		c.gid = int(c.gid)
		for key in ["t0", "t1", "t2"]:
			if c.has(key):
				c[key] = int(c[key])
		c.army = c.army.map(func(id): return int(id))
		state.wars.campaigns[f] = c
	state.wars._tally = int(data.get("tally", 0))
	state.journal = data.journal
	return state

static func _stacks(list: Array) -> Array:
	var out: Array = []
	for s in list:
		out.append({"type": String(s.type), "n": int(s.n)})
	return out

static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = int(d[k])
	return out

static func _hero(h: Dictionary) -> Dictionary:
	var out := h.duplicate(true)
	for k in ["lvl", "xp", "pts", "pp", "str", "vit", "agi", "int", "cha", "armor", "weapon", "shield", "horse", "seed"]:
		if out.has(k):
			out[k] = int(out[k])
	return out

const QUEST_INT_KEYS := ["id", "from", "sid", "day", "dl", "n", "got", "reward"]

static func _quests(list: Array) -> Array:
	var out: Array = []
	for q in list:
		var c: Dictionary = q.duplicate(true)
		for k in QUEST_INT_KEYS:
			if c.get(k) != null:
				c[k] = int(c[k])
		out.append(c)
	return out
