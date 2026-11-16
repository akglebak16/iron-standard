extends SceneTree
## Operations of a faction (campaign_ops.gd, DESIGN.md §5.3, stage 2b) on synthetic data: made-up factions "aa" and
## "bb", parties with a plain strength field, a threat function instead of the threat map.
const CampaignOps = preload("res://core/campaign/world/campaign_ops.gd")
const Config = preload("res://core/campaign/config.gd")

func _initialize() -> void:
	_check_marshal()
	_check_alerts()
	_check_keep()
	_check_split()
	_check_relief()
	_check_retreat()
	_check_empty()
	print("Campaign ops tests passed")
	quit(0)

func _ops() -> CampaignOps:
	var o := CampaignOps.new()
	o.strength = func(p: Dictionary) -> float: return float(p.s)
	return o

static func _lord(id: int, s: float, x := 0.0, y := 0.0, kind := "lord") -> Dictionary:
	return {"id": id, "kind": kind, "fac": "aa", "s": s, "x": x, "y": y}

static func _place(id: int, kind: String, fac: String, x: float, y: float, siege: Variant = null) -> Dictionary:
	return {"id": id, "kind": kind, "fac": fac, "x": x, "y": y, "siege": siege}

func _check_marshal() -> void:
	var o := _ops()
	var host := [_lord(3, 200.0), _lord(1, 500.0), _lord(2, 500.0), _lord(9, 900.0, 0, 0, "vassal")]
	var m := o.marshal_of(host)
	assert(m.id == 1, "the strongest lord leads, an equal one with a lower id wins, a vassal never leads lords: %s" % [m])
	assert(o.marshal_of([_lord(9, 900.0, 0, 0, "vassal"), _lord(8, 100.0, 0, 0, "vassal")]).id == 9, "a host of vassals has a vassal marshal")
	assert(o.marshal_of([]).is_empty())
	assert(is_equal_approx(o.total(host), 2100.0))

func _check_alerts() -> void:
	var o := _ops()
	var settles := [
		_place(1, "town", "aa", 0, 0, {"f": "bb", "t0": 0}),   # besieged
		_place(2, "castle", "aa", 1000, 0),                    # enemies around it
		_place(3, "town", "aa", 2000, 0),                      # quiet
		_place(4, "village", "aa", 1000, 50),                  # villages need no defender
		_place(5, "town", "bb", 1000, 10),                     # not ours
		_place(6, "camp", "aa", 1000, 20),
	]
	var threat := func(x: float, _y: float, _f: String) -> float: return 300.0 if x >= 900.0 and x <= 1100.0 else 10.0
	var a := o.alerts("aa", settles, threat)
	assert(a.size() == 2 and a[0].s.id == 1 and a[0].besieged and a[1].s.id == 2 and not a[1].besieged, "besieged first, then threatened: %s" % [a])
	assert(o.alerts("aa", settles, Callable()).size() == 1, "without a threat map only sieges call for defenders")
	assert(o.alerts("cc", settles, threat).is_empty(), "a faction without lands has nothing to defend")

func _check_keep() -> void:
	assert(CampaignOps.keep_count(0, 0) == 0 and CampaignOps.keep_count(1, 3) == 0, "a lone lord always goes")
	assert(CampaignOps.keep_count(2, 0) == 0, "two lords of a quiet faction both go")
	assert(CampaignOps.keep_count(2, 1) == 1, "one stays by a threatened town")
	assert(CampaignOps.keep_count(Config.OP_KEEP_MIN_LORDS, 0) == Config.OP_KEEP_BASE, "a faction at war keeps a lord home")
	assert(CampaignOps.keep_count(6, 5) == 3, "never more than half stays home")
	assert(CampaignOps.keep_count(7, 2) == 3)

func _check_split() -> void:
	var o := _ops()
	var big := _lord(1, 900.0, 0, 0)
	var mid := _lord(2, 500.0, 0, 0)
	var near := _lord(3, 400.0, 980, 0)   # by the threatened castle
	var small := _lord(4, 100.0, 0, 0)
	var castle := _place(10, "castle", "aa", 1000, 0)
	var plan := o.split([big, mid, near, small], [{"s": castle, "threat": 300.0, "besieged": false}])
	assert(plan.marshal == big and big in plan.army, "the marshal goes")
	assert(plan.keep.size() == 2 and near in plan.keep and small in plan.keep, "the nearest lord stays by the castle, the weakest by the rest: %s" % [plan.keep])
	assert(plan.army.size() == 2 and mid in plan.army and not near in plan.army)
	# the marshal goes even when he is the nearest to the threat
	var lone := o.split([_lord(1, 900.0, 990, 0), _lord(2, 100.0, 0, 0)], [{"s": castle, "threat": 300.0, "besieged": false}])
	assert(lone.army.size() == 1 and lone.army[0].id == 1 and lone.keep.size() == 1 and lone.keep[0].id == 2)
	# a quiet faction with three lords keeps one, the weakest
	var quiet := o.split([_lord(1, 300.0), _lord(2, 200.0), _lord(3, 100.0)], [])
	assert(quiet.keep.size() == 1 and quiet.keep[0].id == 3 and quiet.army.size() == 2)

func _check_relief() -> void:
	var o := _ops()
	var town := _place(1, "town", "aa", 0, 0, {"f": "bb"})
	var cands := [_lord(4, 300.0, 800, 0), _lord(2, 300.0, 100, 0), _lord(3, 300.0, 400, 0), _lord(5, 300.0, 600, 0), _lord(6, 300.0, 700, 0)]
	var host := o.relief_host(cands, town, 500.0, 100.0)
	assert(host.size() == 2 and host[0].id == 2 and host[1].id == 3, "nearest first, until they outmatch the besiegers: %s" % [host])
	var all := o.relief_host(cands, town, 1500.0, 0.0)
	assert(all.size() == Config.OP_RELIEF_MAX_LORDS, "at most %d lords relieve" % Config.OP_RELIEF_MAX_LORDS)
	assert(o.relief_host(cands, town, 4000.0, 0.0).is_empty(), "hopeless relief is not sent")
	assert(o.relief_host([], town, 10.0, 1000.0).is_empty(), "no lords, no relief")

func _check_retreat() -> void:
	assert(CampaignOps.weak(1000.0, 1000.0 * Config.OP_RETREAT_SHARE - 1.0) and not CampaignOps.weak(1000.0, 1000.0 * Config.OP_RETREAT_SHARE + 1.0))
	assert(not CampaignOps.weak(0.0, 0.0), "a campaign without a known start is not weak")
	var o := _ops()
	var marshal := _lord(1, 500.0, 0, 0)
	var castle := _place(20, "castle", "bb", 3000, 0)
	var town := _place(21, "town", "bb", 3000, 100)
	var home := _place(10, "town", "aa", 600, 0, {"f": "bb"})
	var far := _place(11, "town", "aa", Config.OP_RECALL_RANGE + 100.0, 0, {"f": "bb"})
	var settles := [home, far, castle, town]
	assert(o.recall("aa", settles, marshal, castle, false) == home, "a besieged own town recalls a campaign against a castle")
	assert(o.recall("aa", settles, marshal, town, false) == home, "an own town is worth more than an enemy town")
	var home_castle := _place(12, "castle", "aa", 100, 0, {"f": "bb"})
	assert(o.recall("aa", [home_castle, town], marshal, town, false).is_empty(), "an own castle does not recall a campaign against a town")
	assert(o.recall("aa", [far, castle], marshal, castle, false).is_empty(), "too far to help")
	assert(o.recall("aa", settles, marshal, castle, true).is_empty(), "one defensive operation at a time")
	assert(CampaignOps.value({"kind": "camp"}) == 0.0)

func _check_empty() -> void:
	var o := _ops()
	var plan := o.split([], [])
	assert(plan.army.is_empty() and plan.keep.is_empty() and plan.marshal.is_empty())
	assert(o.alerts("aa", [], Callable()).is_empty())
	assert(o.recall("aa", [], {}, {}, false).is_empty())
	var bare := CampaignOps.new()
	assert(bare.total([{"id": 1}]) == 0.0, "without a strength function parties weigh nothing")
