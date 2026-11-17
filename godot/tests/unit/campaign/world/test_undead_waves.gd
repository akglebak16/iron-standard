extends SceneTree
## The undead invasion in a live world (world_undead.gd + undead_director.gd, DESIGN.md §5.5, stage 2c): every barrow
## sends a wave with a reachable target and a rally point, its armies gather there through their goals, storm together,
## the wave rolls on to the next target; the living defend doomed towns and retake their ruins with a campaign; the
## waves survive a save. One world is built for the checks (5 s), the save check builds two more.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldSave = preload("res://core/campaign/world/world_save.gd")
const WorldCheckpoint = preload("res://core/campaign/world/world_checkpoint.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const Director = preload("res://core/campaign/world/undead_director.gd")
const Config = preload("res://core/campaign/config.gd")

var data := EuropeData.new()

func _initialize() -> void:
	assert(ContentLoader.populate(data))
	var s := _crisis_world(5)
	_check_waves(s)
	_check_goals(s)
	_check_storm(s)
	_check_ruin_campaign(s)
	s.dispose()
	_check_save()
	print("Undead waves tests passed")
	quit(0)

## A world with the crisis just begun: two barrows, six armies, four raids.
func _crisis_world(seed_value: int) -> RefCounted:
	var s = WorldState.create(seed_value, data, "emp", ContentLoader.registry())
	s.undead.day = int(s.undead.crisis.day)
	s.undead.day_tick()
	assert(s.undead.crisis.on and s.undead.crisis.src.size() == 2)
	s._threat_step += 1
	return s

static func _armies(s, key: String) -> Array:
	return s.roster.parties.filter(func(p): return p.kind == "dead" and str(int(p.src)) == key)

## Every barrow gets a wave: a living town or castle it can reach, a rally point short of it; nothing changes an hour
## later; the doomed towns are known to the living.
func _check_waves(s) -> void:
	var u = s.undead
	var events: Array = []
	u.wave.connect(func(e): events.append(e))
	u.wave_tick()
	assert(u.crisis.waves.size() == 2, "one wave per barrow: %s" % [u.crisis.waves])
	for key in u.crisis.waves:
		var w: Dictionary = u.crisis.waves[key]
		var t: Dictionary = s.map.settlement_by_id(w.tid)
		assert(Director.is_target(t), "a living town or castle: %s" % [t])
		assert(w.mode == "gather" and w.tid is int and w.t0 is int and w.rx is float, "typed for the checkpoint: %s" % [w])
		var rally := Vector2(w.rx, w.ry)
		assert(absf(rally.distance_to(Vector2(t.x, t.y)) - Config.UNDEAD_RALLY_DISTANCE) < Config.UNDEAD_RALLY_DISTANCE * 0.6, "rally point short of the target")
		assert(s.map.paths.find_path(float(s.map.settlement_by_id(int(key)).x), float(s.map.settlement_by_id(int(key)).y), t.x, t.y) != null, "the wave can get there")
		assert(u.doomed().get(t.id) == "gather", "a new target is never stormed at once: the living hear of it first")
	assert(events.filter(func(e): return e.what == "target").size() == 2)
	assert(s.journal.filter(func(j): return "Армии мертвецов идут на" in j.text).size() == 2, "the journal tells where the dead go")
	var before: Dictionary = u.crisis.waves.duplicate(true)
	u.wave_tick()
	assert(u.crisis.waves == before, "a wave keeps its target and rally point")
	assert(WorldCheckpoint.valid(WorldCheckpoint.capture(s)), "waves fit the checkpoint")

## Armies muster at the rally point, raids burn villages ahead, lords of the doomed faction defend it from the inside.
func _check_goals(s) -> void:
	var u = s.undead
	s.roster.parties = s.roster.parties.filter(func(p): return p.fac == "undead" or p.get("ruler", false))  # nobody to hunt
	s._threat_step += 1
	var key: String = u.crisis.waves.keys()[0]
	var w: Dictionary = u.crisis.waves[key]
	var army: Dictionary = _armies(s, key)[0]
	w.mode = "gather"
	army.ai = 0.0
	s.ai._fresh()
	s.ai.goals.rebuild_claims()
	s.ai.ai_party(army, 0.2)
	assert(army.goal == "muster" and army.gid == w.tid, "the army gathers with its wave: %s %s" % [army.goal, army.gid])
	assert(army.path.size() > 0 and army.path.back().distance_to(Vector2(w.rx, w.ry)) <= Config.UNDEAD_MUSTER_SPREAD.y + 1.0, "it rides to the rally point")
	w.mode = "attack"
	army.ai = 0.0
	s.ai._fresh()
	s.ai.ai_party(army, 0.2)
	assert(army.goal == "assault" and army.sid == w.tid and army.state == "travel", "once the wave attacks the army marches on the target at once")
	w.mode = "gather"
	var raid: Dictionary = s.roster.parties.filter(func(p): return p.kind == "raid" and str(int(p.src)) == key)[0]
	var t: Dictionary = s.map.settlement_by_id(w.tid)
	raid.x = t.x + 200.0
	raid.y = t.y
	raid.ai = 0.0
	raid.wait = 0.0
	s.ai.ai_party(raid, 0.2)
	if raid.goal == "raid":
		var v: Dictionary = s.map.settlement_by_id(raid.gid)
		assert(v.kind == "village" and Vector2(v.x - t.x, v.y - t.y).length() <= Config.UNDEAD_RAVAGE_RANGE, "it burns a village ahead of the wave")
	else:
		assert(raid.goal in ["hunt", "roam"], "a raid always has something to do: %s" % raid.goal)
	var fac: String = t.fac
	if fac in Rules.REAL_FACTIONS:
		var lord: Dictionary = s.roster.make_party("lord", fac, "Защитник", t.x + 150.0, t.y + 40.0, [{"type": s.roster.gen_troops(fac, 1, 0.5)[0].type, "n": 300}])
		var away := {}
		for p in s.roster.parties:  # the horde is still far: the lord dares to ride in (by it he would not)
			if p.fac == "undead":
				away[p.id] = Vector2(p.x, p.y)
				p.x = 5000.0
				p.y = 3200.0
		s._threat_step += 1
		s.ai._fresh()
		var cands: Array = s.ai.goals.candidates(lord, s.ai._context(lord, {}))
		var inside: Array = cands.filter(func(c): return c.goal == "defend" and c.gid == t.id and c.get("inside", false))
		assert(inside.size() == 1, "the doomed town is defended from the inside: %s" % [cands])
		s.ai._apply(lord, inside[0], {})
		assert(lord.goal == "defend" and lord.state == "travel" and lord.sid == t.id, "the lord rides into the town")
		s.roster.remove(lord)
		for p in s.roster.parties:
			if away.has(p.id):
				p.x = away[p.id].x
				p.y = away[p.id].y
		s._threat_step += 1
		var alerts: Array = s.wars.ops.alerts(fac, s.map.settles, Callable(), s.wars._doomed())
		assert(alerts.any(func(a): return a.s.id == t.id and a.doomed), "the faction keeps a defender home")

## Armies at the walls wait for the wave, then storm together; the wave rolls on to its next target.
func _check_storm(s) -> void:
	var u = s.undead
	var key: String = u.crisis.waves.keys()[0]
	var w: Dictionary = u.crisis.waves[key]
	var t: Dictionary = s.map.settlement_by_id(w.tid)
	var armies := _armies(s, key)
	assert(armies.size() == 3)
	for p in armies:
		p.troops = [{"type": "s3", "n": 900}]
		p.x = w.rx
		p.y = w.ry
		p.path = []
	var events: Array = []
	u.wave.connect(func(e): events.append(e))
	w.t0 = s.wars.now_h() - Config.UNDEAD_MIN_GATHER_HOURS
	u.wave_tick()
	assert(w.mode == "attack", "gathered and far stronger than the walls: attack")
	assert(events.any(func(e): return e.what == "attack" and e.tid == t.id))
	armies[0].x = t.x + 20.0
	armies[0].y = t.y + 20.0
	armies[0].state = "travel"
	armies[0].sid = t.id
	u.arrive(armies[0], t)
	assert(armies[0].wait >= Config.UNDEAD_WALL_WAIT and t.fac != "undead", "the first army waits at the walls")
	assert(w.tw >= 0)
	u.wave_tick()
	assert(t.fac != "undead", "a third of the wave does not storm alone")
	for p in armies:
		p.x = t.x + 10.0
		p.y = t.y + 30.0
	var news: Array = []
	u.announced.connect(func(x): news.append(x))
	u.wave_tick()
	var storm: Array = events.filter(func(e): return e.what == "storm")
	assert(storm.size() == 1 and storm[0].armies == 3 and storm[0].won, "all three storm together: %s" % [storm])
	assert(t.fac == "undead" and t.gar.size() > 0, "the town is a ruin of the dead")
	assert(news.any(func(x): return "пал под натиском мертвецов" in x))
	assert(w.mode == "gather" and w.tid != t.id and Director.is_target(s.map.settlement_by_id(w.tid)), "the wave rolls on to a new target")
	assert(events.back().what == "target")
	var fresh := _armies(s, key)
	assert(not fresh.is_empty() and fresh.all(func(p): return Rules.troop_count(p.troops) < 900), "the storm cost the armies men and a garrison")

## Own ruins are retaken by a campaign: the host storms them together instead of a siege.
func _check_ruin_campaign(s) -> void:
	var w = s.wars
	var ruin: Dictionary = {}
	for t in s.map.settles:
		if t.fac == "undead" and t.get("ruinOf", "") in Rules.REAL_FACTIONS and t.kind != "camp":
			ruin = t
			break
	assert(not ruin.is_empty())
	var fac: String = ruin.ruinOf
	w.wars.clear()  # at peace with everyone: the ruins are the only target
	w.campaigns.clear()
	s.roster.parties = s.roster.parties.filter(func(p): return p.fac != fac or p.get("ruler", false))
	var home: Dictionary = {}
	for t in s.map.settles:
		if t.fac == fac and t.kind == "town":
			home = t
			break
	var type: String = s.roster.gen_troops(fac, 1, 0.9)[0].type
	for i in 3:
		s.roster.make_party("lord", fac, "Лорд %d" % i, home.x + 30.0 * i, home.y + 20.0, [{"type": type, "n": 330}])
	var events: Array = []
	w.operation.connect(func(e): events.append(e))
	w.hour = 6
	w._campaign(fac)
	assert(w.campaigns.has(fac) and w.campaigns[fac].tid == ruin.id, "a campaign to retake the ruins, even in peace")
	assert(events.back().what == "start" and events.back().ruin)
	var c: Dictionary = w.campaigns[fac]
	c.state = "march"
	c.t1 = w.now_h()
	for id in c.army:
		var p: Dictionary = s.roster.party_by_id(id)
		p.x = ruin.x + 20.0
		p.y = ruin.y + 30.0
		p.path = []
		p.troops = [{"type": type, "n": 900}]
	w.hour = 8
	w._campaign(fac)
	var done := events.filter(func(e): return e.what in ["retaken", "repulsed"])
	assert(done.size() == 1 and done[0].what == "retaken" and done[0].host == c.army.size() and c.army.size() >= 2, "the host storms together: %s" % [done])
	assert(ruin.fac == fac and int(ruin.ruin) > 0)
	w.hour = 10
	w._campaign(fac)
	assert(not w.campaigns.has(fac), "the campaign ends once its ruins are back")

## A world in the middle of the invasion saves and loads with its waves and goes on exactly as the saved one; a save
## from before stage 2c (no waves) gets new ones; v1 waves come back typed.
func _check_save() -> void:
	var a := _crisis_world(11)
	a.player.away = true
	a.waiting = true
	for i in 12:
		a.advance(1.0)
	assert(not a.undead.crisis.waves.is_empty())
	var b = WorldSave.from_dict(JSON.parse_string(JSON.stringify(WorldSave.to_dict(a))), data, ContentLoader.registry())
	assert(b != null and b.undead.crisis.waves == a.undead.crisis.waves)
	b.waiting = true
	for i in 12:
		a.advance(1.0)
		b.advance(1.0)
	assert(WorldCheckpoint.capture(a) == WorldCheckpoint.capture(b), "loading reproduces the invasion")
	var legacy := WorldSave.to_v1_dict(a)
	var typed = WorldSave.from_dict(JSON.parse_string(JSON.stringify(legacy)), data, ContentLoader.registry())
	assert(typed != null)
	for w in typed.undead.crisis.waves.values():
		assert(w.tid is int and w.t0 is int and w.tw is int and w.rx is float and w.bad.all(func(x): return x is int), "v1 waves typed: %s" % [w])
	assert(WorldCheckpoint.valid(WorldCheckpoint.capture(typed)))
	var old := legacy.duplicate(true)
	old.crisis.erase("waves")
	assert(WorldSave._valid_v1_header(JSON.parse_string(JSON.stringify(old))), "a save from before stage 2c has no waves")
	typed.undead.crisis.erase("waves")
	assert(WorldCheckpoint.valid(WorldCheckpoint.capture(typed)))
	typed.undead.wave_tick()
	assert(typed.undead.crisis.waves.size() > 0, "a crisis without waves gets them at the next hour")
	typed.dispose()
	var bad := legacy.duplicate(true)
	bad.crisis.waves[bad.crisis.waves.keys()[0]].mode = "dance"
	assert(WorldSave.from_dict(JSON.parse_string(JSON.stringify(bad)), data, ContentLoader.registry()) == null, "a broken wave is refused")
	a.dispose()
	b.dispose()
