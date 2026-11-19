extends SceneTree
## Native campaign world kernel (ADR-025, #240) against the GDScript reference: the threat-map stamp, the contact pairs
## and a whole campaign, compared day by day (save fingerprint and RNG) — both backends must give the same world.
const WorldNative = preload("res://adapters/godot/native/world.gd")
const ThreatMap = preload("res://core/campaign/world/threat_map.gd")
const PartyAI = preload("res://core/campaign/world/party_ai.gd")
const Sim = preload("res://tests/performance/campaign_simulator.gd")
const WorldSave = preload("res://core/campaign/world/world_save.gd")

func _initialize() -> void:
	var port: RefCounted = WorldNative.create()
	assert(port != null, "the native library is loaded (IronWorldKernel)")
	# the engine side refuses columns that disagree
	var kernel = ClassDB.instantiate("IronWorldKernel")
	assert(kernel.stamp(PackedFloat64Array([1.0]), PackedFloat64Array(), PackedFloat64Array([1.0]), PackedInt32Array([0]), 1, 10, 10, 30.0, 90.0).is_empty())
	assert(kernel.stamp(PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedInt32Array(), 0, 0, 10, 30.0, 90.0).is_empty())
	assert(kernel.contact_pairs(PackedFloat64Array([1.0, 2.0]), PackedFloat64Array([1.0]), 15.0).is_empty())
	assert(kernel.box(PackedFloat64Array([1.0, 2.0]), PackedFloat64Array([1.0]), 0.0, 0.0, 5.0).is_empty())
	# the box holds its edges, in index order (#242)
	var bx := PackedFloat64Array([0.0, 10.0, -10.0, 10.0000001, 3.0])
	var by := PackedFloat64Array([0.0, -10.0, 10.0, 0.0, 9.0])
	assert(port.box(bx, by, 0.0, 0.0, 10.0) == PackedInt32Array([0, 1, 2, 4]))
	_stamp_parity(port)
	_pair_parity(port)
	_teleport_parity()
	_campaign_parity()
	print("Native world tests passed")
	quit(0)

## Random sources over the whole map and past its edges, zero and negative strengths, several factions.
func _stamp_parity(port: RefCounted) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 240
	for round in 6:
		var list: Array = []
		for i in 80 + round * 60:
			var s := rng.randf_range(-5.0, 400.0) if i % 9 else (0.0 if i % 2 else -3.0)
			list.append({"fac": ["emp", "nord", "bandit", "undead", "khan"][rng.randi() % 5], "x": rng.randf_range(-200.0, 5400.0), "y": rng.randf_range(-200.0, 3600.0), "strength": s})
		var ref := ThreatMap.new()
		var fast := ThreatMap.new()
		fast.native = port
		ref.rebuild(list, round)
		fast.rebuild(list, round)
		assert(ref.layers.keys() == fast.layers.keys(), "the same factions")
		for f in ref.layers:
			assert(ref.layers[f] == fast.layers[f], "layer %s cell by cell (round %d)" % [f, round])
		assert(ref.stamped_cells == fast.stamped_cells and ref.sources == fast.sources and fast.built_hour == round)
	assert(int(port.stamps) == 6 and int(port.failures) == 0)

## Points packed around the contact reach, many exactly on it after float32 rounding.
func _pair_parity(port: RefCounted) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	for round in 5:
		var xs := PackedFloat64Array()
		var ys := PackedFloat64Array()
		for i in 160:
			var base := Vector2(rng.randf_range(0.0, 400.0), rng.randf_range(0.0, 300.0))
			if i > 0 and i % 3 == 0:
				var a := rng.randf() * TAU
				base = Vector2(xs[i - 1], ys[i - 1]) + Vector2(cos(a), sin(a)) * (PartyAI.CONTACT_REACH + rng.randf_range(-0.001, 0.001))
			xs.append(base.x)
			ys.append(base.y)
		var expect := PackedInt32Array()
		for i in xs.size():
			for j in range(i + 1, xs.size()):
				var dx: float = xs[i] - xs[j]
				if absf(dx) >= PartyAI.CONTACT_REACH or not (Vector2(dx, ys[i] - ys[j]).length() < PartyAI.CONTACT_REACH):
					continue
				expect.append(i)
				expect.append(j)
		assert(expect.size() > 20, "the round has contacts")
		assert(port.contact_pairs(xs, ys, PartyAI.CONTACT_REACH) == expect, "the same pairs in the same order (round %d)" % round)

## A fight settled on the spot that moves a party (a beaten ruler goes home) changes the pairs of the later rows:
## the native phase searches them again, so both phases fight the same pairs in the same order.
class TeleportAI extends PartyAI:
	var log: Array = []
	var spot := Vector2.ZERO
	func auto_fight(a: Dictionary, b: Dictionary) -> void:
		log.append([a.id, b.id])
		if log.size() == 1:
			b.x = spot.x  # stays visible: the reference loop meets it at the new place
			b.y = spot.y

func _teleport_parity() -> void:
	var w: RefCounted = Sim.create_world(3)
	var logs: Array = []
	for use_native in [false, true]:
		var ai := TeleportAI.new(w.roster, w.player)
		ai.skirmish = null
		ai.native = WorldNative.create() if use_native else null
		ai.spot = Vector2(3000.0, 1000.0)
		var list: Array = [
			_party(1, "bandit", 1000.0, 1000.0), _party(2, "lord", 1005.0, 1000.0),  # fight; 2 is sent to the spot
			_party(3, "bandit", 3004.0, 1000.0),  # meets 2 only at its new place
			_party(4, "bandit", 1500.0, 1500.0), _party(5, "lord", 1510.0, 1500.0),
		]
		w.roster.parties.assign(list)
		if use_native:
			ai._contacts_native(list)
		else:
			ai._contacts(list)
		logs.append(ai.log)
	assert(logs[0] == [[1, 2], [2, 3], [4, 5]], "the reference meets the moved party at its new place: %s" % str(logs[0]))
	assert(logs[1] == logs[0], "native: %s" % str(logs[1]))
	w.dispose()

static func _party(id: int, kind: String, x: float, y: float) -> Dictionary:
	return {"id": id, "kind": kind, "fac": "bandit" if kind == "bandit" else "emp", "x": x, "y": y, "hide": false, "troops": [{"type": "b1", "n": 5}], "state": "idle", "path": [], "pi": 0}

## The same seed with and without the native kernel: equal saves and RNG every day, the crisis included.
func _campaign_parity() -> void:
	var ref: RefCounted = Sim.create_world(11)
	var fast: RefCounted = Sim.create_world(11)
	var port: RefCounted = WorldNative.create()
	fast.use_native(port)
	fast.ai.index.verify = true  # every index answer is checked against the full scan (#242)
	assert(WorldSave.to_dict(ref).sha256 == WorldSave.to_dict(fast).sha256)
	for day in range(1, 16):
		Sim.drive(ref, day * 24, func(): pass, func(): pass)
		Sim.drive(fast, day * 24, func(): pass, func(): pass)
		assert(ref.roster.rng.state == fast.roster.rng.state, "RNG on day %d" % day)
		assert(WorldSave.to_dict(ref).sha256 == WorldSave.to_dict(fast).sha256, "the world on day %d" % day)
		if day == 5:
			fast.ai.index.verify = false  # the rest only compares the worlds, at full speed
	assert(int(port.stamps) > 100 and int(port.pair_calls) > 100 and int(port.box_calls) > 10000 and int(port.failures) == 0, "the native path ran: %d stamps, %d pair calls, %d boxes" % [port.stamps, port.pair_calls, port.box_calls])
	ref.dispose()
	fast.dispose()
