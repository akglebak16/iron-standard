extends SceneTree
## Strategist of a faction (faction_strategist.gd, DESIGN.md §5.4, stage 2d): the evaluator on synthetic day summaries of
## made-up states "aa" and "bb", then world_wars.gd in a live world: weariness from lost lords and settlements, the gain
## of a war, truces, the opening wars, and saving: the new state survives a save, continues the same way after loading,
## and a save made before stage 2d loads with nobody weary.
const Strategist = preload("res://core/campaign/world/faction_strategist.gd")
const WorldWars = preload("res://core/campaign/world/world_wars.gd")
const Config = preload("res://core/campaign/config.gd")
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const WorldState = preload("res://core/campaign/world/world_state.gd")
const WorldSave = preload("res://core/campaign/world/world_save.gd")
const EuropeData = preload("res://core/campaign/data/europe_data.gd")
const Checkpoint = preload("res://core/campaign/world/world_checkpoint.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")

func _initialize() -> void:
	_check_prize()
	_check_war_will()
	_check_peace()
	_check_opening()
	var data := EuropeData.new()
	assert(ContentLoader.populate(data))
	var w := WorldState.create(9, data, "emp", ContentLoader.registry())
	w.player.away = true
	_check_losses(w)
	_check_day(w)
	_check_save(w, data)
	w.dispose()
	print("World strategist tests passed")
	quit(0)

static func _state(power: float, wars := 0, weary := 0.0, core: Array = [], strain := 0.0) -> Dictionary:
	return {"power": power, "wars": wars, "weary": weary, "strain": strain, "war_k": 1.0, "peace_k": 1.0, "core": core}

static func _town(x: float, y: float, kind := "town") -> Dictionary:
	return {"x": x, "y": y, "kind": kind}

func _check_prize() -> void:
	var mine := [_town(0, 0), _town(3000, 0, "castle")]
	var theirs := [_town(500, 0), _town(0, 700, "castle"), _town(1500, 1500)]
	assert(is_equal_approx(Strategist.prize(mine, theirs), 1.7), "a town and a castle within reach, the far town is not")
	assert(Strategist.prize(mine, []) == 0.0 and Strategist.prize([], theirs) == 0.0)

func _check_war_will() -> void:
	var core_a := [_town(0, 0)]
	var core_b := [_town(400, 0), _town(0, 400), _town(300, 300, "castle")]
	var gain := Strategist.prize(core_a, core_b)
	var strong := _state(2000.0, 0, 0.0, core_a)
	var weak := _state(1000.0, 0, 0.0, core_b)
	var will := Strategist.war_will(strong, weak, gain)
	assert(will > 0.9, "a fresh state at peace with a weak neighbour and towns within reach wants war: %f" % will)
	assert(Strategist.war_will(weak, strong, Strategist.prize(core_b, core_a)) == 0.0, "nobody attacks a much stronger neighbour")
	assert(Strategist.war_will(strong, weak, 0.0) == 0.0, "nothing to take, no war")
	var busy := strong.duplicate()
	busy.wars = 1
	assert(is_equal_approx(Strategist.war_will(busy, weak, gain), will * Config.STRAT_SECOND_FRONT), "a second front is wanted much less")
	busy.wars = Config.STRAT_MAX_WARS
	assert(Strategist.war_will(busy, weak, gain) == 0.0, "never a third front")
	var tired := strong.duplicate()
	tired.weary = Config.STRAT_WEARY_WAR * 0.5
	assert(is_equal_approx(Strategist.war_will(tired, weak, gain), will * 0.5), "weariness damps the will to war")
	tired.weary = Config.STRAT_WEARY_WAR
	assert(Strategist.war_will(tired, weak, gain) == 0.0, "a worn-out state starts no war")
	var warlike := strong.duplicate()
	warlike.war_k = 1.6
	assert(is_equal_approx(Strategist.war_will(warlike, weak, gain), will * 1.6), "the ruler's trait multiplies")
	var foe_busy := weak.duplicate()
	foe_busy.wars = Config.STRAT_FOE_MAX_WARS
	assert(Strategist.war_will(strong, foe_busy, gain) == 0.0, "a neighbour in many wars is left alone")
	var d := Strategist.declaration(weak, strong)
	assert(d.by == 1 and is_equal_approx(d.chance, Config.STRAT_WAR_RATE * will), "the stronger will declares: %s" % [d])

func _check_peace() -> void:
	var a := _state(1000.0, 1)
	var b := _state(1000.0, 1)
	var at := Config.STRAT_PEACE_AT
	assert(Strategist.peace_chance(a, b, "aa", "bb", {}, 40) == 0.0, "fresh equal states fight on")
	var ta := _state(1000.0, 1, at)
	var tb := _state(1000.0, 1, at)
	var ripe := Strategist.peace_chance(ta, tb, "aa", "bb", {}, 40)
	assert(is_equal_approx(ripe, Config.STRAT_PEACE_CHANCE.x), "both weary enough: the first chance of peace %f" % ripe)
	var worn := _state(1000.0, 1, at + Config.STRAT_PEACE_SPAN)
	assert(is_equal_approx(Strategist.peace_chance(worn, worn, "aa", "bb", {}, 40), Config.STRAT_PEACE_CHANCE.y), "worn out: the best chance")
	assert(Strategist.peace_chance(worn, worn, "aa", "bb", {}, Config.STRAT_MIN_WAR_DAYS - 1) == 0.0, "no peace in the first days")
	assert(Strategist.peace_chance(worn, b, "aa", "bb", {}, 40) == 0.0, "peace needs both sides")
	# bb took what it wanted, aa is losing
	var aim := Config.STRAT_WAR_AIM
	assert(is_equal_approx(Strategist.peace_will(b, a, aim, 0.0), Config.STRAT_CONTENT), "a winner who took its share wants peace")
	assert(is_equal_approx(Strategist.peace_will(b, a, aim / 2.0, 0.0), Config.STRAT_CONTENT / 2.0), "half the aim, half the content")
	assert(Strategist.peace_will(a, b, 0.0, aim) > 0.0, "the losing side wants peace")
	var rest := at - Config.STRAT_CONTENT
	var wb := _state(1000.0, 1, rest)
	var wa := _state(1000.0, 1, at)
	assert(Strategist.peace_chance(wa, wb, "aa", "bb", {"bb": aim}, 40) > 0.0, "the winner took its share, the loser gives in")
	assert(Strategist.peace_chance(wa, wb, "aa", "bb", {"bb": aim / 2.0}, 40) == 0.0, "a winner short of its aim fights on")
	var weak := _state(400.0, 1)
	assert(Strategist.peace_will(weak, _state(1000.0, 1), 0.0, 0.0) > Strategist.peace_will(a, b, 0.0, 0.0), "the weaker side wants peace more")
	var fronts := _state(1000.0, 3)
	assert(is_equal_approx(Strategist.peace_will(fronts, b, 0.0, 0.0), 2 * Config.STRAT_FRONTS), "more fronts, more will to peace")
	var thin := _state(1000.0, 1, 0.0, [], 0.8)
	assert(is_equal_approx(Strategist.peace_will(thin, b, 0.0, 0.0), 0.8 * Config.STRAT_STRAIN), "thin armies pull to peace")
	var peaceful := ta.duplicate()
	peaceful.peace_k = 1.6
	assert(is_equal_approx(Strategist.peace_will(peaceful, b, 0.0, 0.0), at * 1.6), "the ruler's trait multiplies")

func _check_opening() -> void:
	var all := WorldWars.opening_wars(0)
	assert(all.size() == 10, "the whole table: %d" % all.size())
	for cap in [1, 2]:
		var some := WorldWars.opening_wars(cap)
		var count := {}
		for k in some:
			assert(k in all, "only wars of the table")
			for f in String(k).split("|"):
				count[f] = int(count.get(f, 0)) + 1
		for f in count:
			assert(int(count[f]) <= cap, "%s starts with %d wars, cap %d" % [f, count[f], cap])
		assert(some.size() < all.size())

func _war_of(w: RefCounted) -> PackedStringArray:
	for k in w.wars.wars:
		var parts: PackedStringArray = String(k).split("|")
		if w.wars.alive(parts[0]) and w.wars.alive(parts[1]):
			return parts
	return PackedStringArray()

func _check_losses(w: RefCounted) -> void:
	var war := _war_of(w)
	assert(war.size() == 2, "the world starts at war")
	var f: String = war[0]
	var e: String = war[1]
	var before := float(w.wars.weary.get(f, 0.0))
	var lord: Dictionary = w.roster.parties.filter(func(q): return q.kind == "lord" and q.fac == f)[0]
	var n: int = w.roster.parties.size()
	w.roster.remove(lord)
	assert(w.roster.parties.size() == n - 1)
	assert(is_equal_approx(float(w.wars.weary[f]), before + Config.STRAT_WEARY_LORD), "a lord lost at war tires the state")
	w.roster.remove(lord)
	assert(is_equal_approx(float(w.wars.weary[f]), before + Config.STRAT_WEARY_LORD), "removing a gone party twice counts once")
	w.wars._war_capture(f, e, "town")
	var k := Rules.war_key(f, e)
	assert(is_equal_approx(float(w.wars.wars[k].gain[e]), 1.0), "the taker counts the town as its gain")
	assert(is_equal_approx(float(w.wars.weary[f]), before + Config.STRAT_WEARY_LORD + Config.STRAT_WEARY_LOSS.town), "the loser grows wearier")
	var peaceful: String = ""
	for g in Rules.REAL_FACTIONS:
		if w.wars.wars_of(g) == 0:
			peaceful = g
	if peaceful != "":
		var other: Dictionary = w.roster.parties.filter(func(q): return q.kind == "lord" and q.fac == peaceful)[0]
		w.roster.remove(other)
		assert(float(w.wars.weary.get(peaceful, 0.0)) == 0.0, "a state at peace does not count war losses")

## A day of diplomacy: weariness grows at war and is shed in peace; a peace starts a truce, and a pair under truce
## starts no war.
func _check_day(w: RefCounted) -> void:
	var war := _war_of(w)
	var f: String = war[0]
	var e: String = war[1]
	var k := Rules.war_key(f, e)
	w.wars.day = int(w.wars.wars[k].since) + 40
	w.wars.weary[f] = 1.0
	w.wars.weary[e] = 1.0
	var at_war := {}
	for g in w.wars.factions_alive():
		at_war[g] = w.wars.wars_of(g) > 0
	var before: Dictionary = w.wars.weary.duplicate()
	w.wars.war_day()
	for g in at_war:
		var was := float(before.get(g, 0.0))
		var now := float(w.wars.weary.get(g, 0.0))
		if at_war[g]:
			assert(now > was or now == Config.STRAT_WEARY_MAX, "%s at war grows wearier" % g)
		else:
			assert(now == maxf(0.0, was - Config.STRAT_WEARY_REST), "%s at peace rests" % g)
	for i in 60:
		if not w.wars.at_war(f, e):
			break
		w.wars.day += 1
		w.wars.weary[f] = 1.0
		w.wars.weary[e] = 1.0
		w.wars.war_day()
	assert(not w.wars.at_war(f, e), "two worn-out states make peace")
	assert(int(w.wars.truce[k]) == w.wars.day + Config.STRAT_TRUCE_DAYS, "a truce follows the peace")
	# no war under a truce, whatever the will
	w.wars.weary.clear()
	for i in 30:
		w.wars.day += 1
		w.wars.war_day()
		assert(not w.wars.at_war(f, e), "no war while the truce holds")

func _check_save(w: RefCounted, data: EuropeData) -> void:
	var war := _war_of(w)
	var k := Rules.war_key(war[0], war[1])
	w.wars.wars[k]["gain"] = {war[0]: 0.7}
	w.wars.weary[war[1]] = 0.25
	var saved := WorldSave.to_dict(w)
	assert(not saved.is_empty())
	var b = WorldSave.from_dict(saved, data, ContentLoader.registry())
	assert(b != null)
	assert(b.wars.weary == w.wars.weary and b.wars.truce == w.wars.truce and b.wars.wars == w.wars.wars, "weariness, truces and gains are saved")
	# the loaded world continues the same way over a day tick
	for x in [w, b]:
		x.waiting = true
		for i in 22:
			x.advance(1.0)
	assert(Checkpoint.capture(b) == Checkpoint.capture(w), "the loaded world goes on exactly like the saved one")
	b.dispose()
	# v1 export keeps them too
	var v1 = WorldSave.from_dict(WorldSave.to_v1_dict(w), data, ContentLoader.registry())
	assert(v1 != null and v1.wars.weary == w.wars.weary and v1.wars.truce == w.wars.truce, "v1 keeps weariness and truces")
	v1.dispose()
	# a save made before stage 2d: no weariness, no truces, wars without gains
	var old := Checkpoint.capture(w)
	old.wars.erase("weary")
	old.wars.erase("truce")
	for key in old.wars.wars:
		old.wars.wars[key] = {"since": int(old.wars.wars[key].since)}
	assert(Checkpoint.valid(old), "a checkpoint without stage 2d fields is valid")
	var payload := Marshalls.raw_to_base64(var_to_bytes(old))
	var c = WorldSave.from_dict({"version": 2, "encoding": "godot-variant-values-v1", "payload": payload, "sha256": payload.sha256_text()}, data, ContentLoader.registry())
	assert(c != null, "an old save loads")
	assert(c.wars.weary.is_empty() and c.wars.truce.is_empty(), "nobody is weary, no truce holds")
	c.wars.day += 1
	c.wars.war_day()
	assert(Checkpoint.valid(Checkpoint.capture(c)), "the old world runs a day of diplomacy and saves again")
	c.dispose()
	var bad := Checkpoint.capture(w)
	bad.wars.weary["nord"] = "x"
	assert(not Checkpoint.valid(bad), "weariness is a number")
	bad = Checkpoint.capture(w)
	bad.wars.truce["a|b"] = 1.5
	assert(not Checkpoint.valid(bad), "a truce ends on a day")
	bad = Checkpoint.capture(w)
	bad.wars.wars[k]["gain"] = {war[0]: "x"}
	assert(not Checkpoint.valid(bad), "a gain is a number")
	bad = Checkpoint.capture(w)
	bad.wars["junk"] = 1
	assert(not Checkpoint.valid(bad), "unknown fields are refused")
