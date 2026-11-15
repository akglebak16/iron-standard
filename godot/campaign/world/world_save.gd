extends RefCounted
## Turns the running world into plain JSON-safe data and back. The map itself is regenerated from the seed;
## only what changes during play is stored (saveGame/loadGame in src/07_main.js).
const WorldState = preload("res://campaign/world/world_state.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const VERSION := 1
const SETTLEMENT_FIELDS := ["fac", "name", "recruits", "rt", "camp", "cleared", "respawn", "hv", "pros", "market", "gar", "cult", "siege", "ruin", "dmg"]
const PARTY_INT_KEYS := ["id", "home", "sid", "tid", "lid"]

static func to_dict(state: RefCounted) -> Dictionary:
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
	return {"version": VERSION, "seed": state.seed_value, "culture": state.culture,
		"clock": {"day": state.clock.day, "hour": state.clock.hour, "speed": state.clock.speed},
		"player": {"x": p.x, "y": p.y, "troops": p.troops, "culture": p.culture, "gold": p.gold, "food": p.food, "inv": p.inv,
			"comps": p.comps, "quests": p.quests, "stats": p.stats, "hero": p.hero, "rel": p.rel},
		"wars": state.wars.wars, "campaigns": state.wars.campaigns, "tally": state.wars._tally, "settles": settles, "parties": parties, "journal": state.journal, "next_party_id": state.roster._next_party_id}

## Rebuilds a world from saved data; returns null for an unknown format.
static func from_dict(data: Dictionary, europe: EuropeData) -> RefCounted:
	if int(data.get("version", 0)) != VERSION:
		return null
	var state := WorldState.create(int(data.seed), europe, String(data.culture))
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
	p.quests = pd.quests
	p.stats = _ints(pd.stats)
	p.hero = _hero(pd.hero)
	p.rel = pd.rel
	for s in state.map.settles:
		var saved: Variant = data.settles.get(str(s.id))
		if saved == null:
			continue
		for k in SETTLEMENT_FIELDS:
			if saved[k] != null or k == "camp":
				s[k] = saved[k]
		s.recruits = _stacks(s.recruits)
		if s.get("gar") is Array:
			s.gar = _stacks(s.gar)
		if s.get("siege") is Dictionary:
			s.siege.t0 = int(s.siege.t0)
			s.siege.g0 = int(s.siege.g0)
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
