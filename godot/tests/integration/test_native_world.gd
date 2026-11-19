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
	_stamp_parity(port)
	_pair_parity(port)
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

## The same seed with and without the native kernel: equal saves and RNG every day, the crisis included.
func _campaign_parity() -> void:
	var ref: RefCounted = Sim.create_world(11)
	var fast: RefCounted = Sim.create_world(11)
	var port: RefCounted = WorldNative.create()
	fast.use_native(port)
	assert(WorldSave.to_dict(ref).sha256 == WorldSave.to_dict(fast).sha256)
	for day in range(1, 16):
		Sim.drive(ref, day * 24, func(): pass, func(): pass)
		Sim.drive(fast, day * 24, func(): pass, func(): pass)
		assert(ref.roster.rng.state == fast.roster.rng.state, "RNG on day %d" % day)
		assert(WorldSave.to_dict(ref).sha256 == WorldSave.to_dict(fast).sha256, "the world on day %d" % day)
	assert(int(port.stamps) > 100 and int(port.pair_calls) > 100 and int(port.failures) == 0, "the native path ran: %d stamps, %d pair calls" % [port.stamps, port.pair_calls])
	ref.dispose()
	fast.dispose()
