extends SceneTree
const Effects = preload("res://apps/godot/presentation/battle/impact_effects.gd")
const Event = preload("res://core/battle/combat_event.gd")
const Parts = preload("res://apps/godot/presentation/battle/detached_parts.gd")
const Art = preload("res://apps/godot/presentation/battle/unit_art.gd")
const Heraldic = preload("res://apps/godot/visuals/dominion_heraldic_art.gd")
const OriginalArt = preload("res://apps/godot/visuals/original_art.gd")
const STEP := 1.0 / 60.0

func _initialize() -> void:
	_check_cut()
	_check_blunt()
	_check_eligibility()
	_check_variety_and_rate()
	_check_heraldic_identity()
	print("Detached parts tests passed")
	quit(0)

func _check_heraldic_identity() -> void:
	for variant in 4:
		var source := Art.new()
		var ids := {}
		var variants := {}
		for i in Heraldic.IDS.size():
			ids[100 + i] = Heraldic.IDS[i]
			variants[100 + i] = variant
		source.configure_identities(ids, variants)
		var parts := Parts.new(RandomNumberGenerator.new())
		parts.use_unit_art(source)
		for id in ids:
			var event := _down(Event.MeleeImpact.CUT)
			event.target_id = id
			var unit: Dictionary = event.target_visual
			unit.id = id
			unit.faction = "dom"
			unit.look = Art.OriginalArt.MANIFEST.troops[ids[id] + "|dom"].look.duplicate(true)
			var live := source.layers(unit)
			assert(live.neck_center == Vector2(76, 78), "every new head has a centred neck attachment")
			assert(live.head_center.x == live.neck_center.x)
			var region := live.head.get_image().get_used_rect() as Rect2i
			assert(region.size.x < 95 and region.end.y < 95, "detached heads contain no shoulders or torso")
			for facing in [0.0, PI]:
				parts.clear()
				unit.facing = facing
				parts.emit(Parts.Part.HEAD, event, 0.0, Color("#773333"))
				var head: Dictionary = parts._active[0]
				assert(head.texture == live.head, "the severed head keeps the exact live appearance variant")
				assert(head.anchor == live.head_center and head.scale == live.scale, "detach without resizing or changing the spin pivot")
				assert(head.mirrored == (facing == PI))
				assert(is_equal_approx(head.height, -Parts.head_offset(unit, live).y))
				assert(parts.neck_offset(unit).is_equal_approx(Vector2(0, -80) * live.scale), "neck effects originate at the cut")
		var effects := Effects.new()
		effects.use_unit_art(source)
		var event := _down(Event.MeleeImpact.CUT)
		event.target_id = 100
		event.target_visual.id = 100
		event.target_visual.faction = "dom"
		event.target_visual.look = Art.OriginalArt.MANIFEST.troops["d1|dom"].look.duplicate(true)
		_seed_for(effects, Parts.Part.HEAD)
		effects.advance(0, [event])
		assert(effects.headless_units().has(100))
		assert(effects._parts._active[0].texture == source.layers(event.target_visual).head)

func _check_cut() -> void:
	var effects := Effects.new()
	var event := _down(Event.MeleeImpact.CUT)
	_seed_for(effects, Parts.Part.HEAD)
	var labels := effects.advance(0.0, [event])
	assert(labels == [{"position": event.position, "text": Effects.CUT_DOWN_LABEL}])
	assert(effects.headless_units().has(event.target_id) and effects.has_particles())
	assert(effects._parts._active.size() == 1 and effects._parts._active[0].kind == Parts.Part.HEAD)
	var texture: Texture2D = effects._parts._active[0].texture
	assert(texture.get_image().get_used_rect().has_area())
	var art := Art.new()
	var images := art.layers(event.target_visual, true)
	assert(images.body.get_image().get_data() != images.headless.get_image().get_data())
	assert(art.layers(event.target_visual, true).headless == images.headless)
	assert(effects._fountains.size() == 1 and effects._pools[0].limit >= Effects.POOL_MAX_RADIUS.x + Effects.HEADLESS_POOL_BONUS)
	var particles := effects._particles.size()
	effects.advance(STEP, [])
	assert(effects._particles.size() > particles)
	for tick in 180:
		effects.advance(STEP, [])
	assert(effects._fountains.is_empty() and not effects._parts.has_active())
	assert(effects._parts._settled.size() == 1)
	effects.blood_enabled = false
	assert(effects.headless_units().is_empty() and effects._parts._settled.is_empty())
	effects.blood_enabled = true
	# No arms or legs any more (#205): a heavy cut takes the head or cuts the figure in half.
	assert(not Effects.CUT_PARTS.has(Parts.Part.ARM) and not Effects.HEAVY_CUT_PARTS.has(Parts.Part.LEG))
	_seed_for(effects, Parts.Part.TORSO)
	effects.advance(0.0, [event])
	assert(effects._parts._active[0].kind == Parts.Part.TORSO and effects.headless_units().is_empty())
	# A shield-bearer cut in half drops his shield beside him; the halves carry no shield.
	var shielded := _down(Event.MeleeImpact.CUT)
	shielded.target_id = 18
	shielded.target_visual.look = OriginalArt.MANIFEST.troops["e2|emp"].look
	shielded.target_visual.id = 18
	var cutter := Effects.new()
	_seed_for(cutter, Parts.Part.TORSO)
	cutter.advance(0.0, [shielded])
	var kinds: Array = cutter._parts._active.map(func(part): return part.kind)
	assert(kinds == [Parts.Part.TORSO, Parts.Part.SHIELD], "the shield falls off on its own")
	var dropped: Dictionary = cutter._parts._active[1]
	assert(dropped.texture != null and dropped.height > 0.0 and dropped.height < 30.0, "it falls from where it hung")
	# The halves are cut from the figure without its shield: where the shield hung, the lower
	# half shows the body underneath.
	var halves := Art.new().split_torso(shielded.target_visual)
	var guard := OriginalArt.guard_layers(shielded.target_visual)
	var bare: Image = (guard.layers[0][0] as Texture2D).get_image()
	var at := Vector2i(guard.shield_center)
	var lower: Image = halves.lower.get_image()
	if lower.get_pixelv(at).a > 0.0:
		assert(lower.get_pixelv(at).is_equal_approx(bare.get_pixelv(at)), "no shield left on the lower half")

func _check_blunt() -> void:
	var effects := Effects.new()
	var event := _down(Event.MeleeImpact.BLUNT)
	event.impact_style = Event.ImpactStyle.DUST
	_seed_for(effects, -1)
	effects.advance(0.0, [event])
	assert(effects.headless_units().has(event.target_id))
	assert(effects._parts._active.size() == Effects.SKELETON_SHATTER_BONE_COUNT)
	assert(effects._parts._active.all(func(part): return part.kind == Parts.Part.BONE))
	assert(effects._pools.is_empty() and effects._fountains.is_empty())
	assert(effects._particles.all(func(particle): return particle.kind == Effects.Particle.DUST))
	effects.blood_enabled = false
	assert(effects._parts._active.is_empty() and effects.headless_units().is_empty())

func _check_eligibility() -> void:
	for variant in ["hero", "companion", "pierce", "projectile", "disabled"]:
		var effects := Effects.new()
		var event := _down(Event.MeleeImpact.CUT)
		match variant:
			"hero": event.target_hero = true
			"companion": event.target_companion = true
			"pierce": event.melee_impact = Event.MeleeImpact.PIERCE
			"projectile": event.attack = Event.Attack.PROJECTILE
			"disabled": effects.blood_enabled = false
		_seed_for(effects, Parts.Part.HEAD)
		effects.advance(0.0, [event])
		assert(not effects._parts.has_active() and effects._fountains.is_empty() and effects.headless_units().is_empty())

func _down(melee_impact: Event.MeleeImpact) -> Dictionary:
	return {"kind": Event.Kind.DOWN, "position": Vector2.ZERO, "target_id": 17,
		"impact_style": Event.ImpactStyle.BLOOD, "attack": Event.Attack.MELEE,
		"melee_impact": melee_impact, "damage_fraction": 0.31, "impact_direction": Vector2.RIGHT,
		"source_hero": true, "target_hero": false, "target_companion": false,
		"target_visual": {"side": 1, "faction": "emp", "look": {"helm": "kettle"},
			"mounted": false, "facing": 0.0, "hero": false, "companion": false}}

func _seed_for(effects: Effects, kind: int, accepted: bool = true) -> void:
	for seed_value in 1000:
		effects._rng.seed = seed_value
		var state := effects._rng.state
		var gate := effects._rng.randf() < Effects.DISMEMBER_CHANCE
		var choice: int = Effects.HEAVY_CUT_PARTS[effects._rng.randi_range(0, Effects.HEAVY_CUT_PARTS.size() - 1)]
		if gate == accepted and (kind < 0 or choice == kind):
			effects._rng.state = state
			return
	assert(false, "No seed matched the requested effect")

func _check_variety_and_rate() -> void:
	var effects := Effects.new()
	var event := _down(Event.MeleeImpact.CUT)
	for kind in Effects.HEAVY_CUT_PARTS:
		effects.blood_enabled = false
		effects.blood_enabled = true
		_seed_for(effects, kind)
		effects.advance(0.0, [event])
		assert(effects._parts._active.size() == 1 and effects._parts._active[0].kind == kind)
		assert(effects.split_torsos().has(event.target_id) == (kind == Parts.Part.TORSO))
		for tick in 180: effects.advance(STEP, [])
		assert(effects._parts._settled.size() == 1)
	var art := Art.new()
	for mounted in [false, true]:
		event.target_visual.mounted = mounted
		var split := art.split_torso(event.target_visual)
		assert(art.split_torso(event.target_visual).upper == split.upper)
		assert(split.upper.get_image().get_used_rect().has_area())
		assert(split.lower.get_image().get_used_rect().has_area())
		if mounted:
			assert(split.upper.get_image().get_used_rect().end.x < split.lower.get_image().get_used_rect().end.x,
				"The horse's head must stay with the fallen mount, outside the severed rider")
		assert(art.detached_leg(event.target_visual).get_image().get_used_rect().has_area())
	event.target_visual.mounted = false
	_check_split_identity()
	# Exercise the real death path and its RNG, not a copy of the probability formula.
	for impact in [Event.MeleeImpact.CUT, Event.MeleeImpact.BLUNT]:
		for hero in [false, true]:
			var severed := 0
			effects._rng.seed = 42055
			event.melee_impact = impact
			event.source_hero = hero
			for casualty in 2000:
				effects._parts.clear()
				effects._headless.clear()
				effects._split_torsos.clear()
				effects.advance(0.0, [event])
				if effects._parts.has_active(): severed += 1
			assert(severed > 1000 and severed < 1200, "55% gate must not gain hero/damage bonuses")
	_seed_for(effects, -1, false)
	effects._parts.clear()
	effects._headless.clear()
	effects._split_torsos.clear()
	effects.advance(0.0, [event])
	assert(not effects._parts.has_active() and effects.headless_units().is_empty() and effects.split_torsos().is_empty())
	for casualty in 1000: effects.advance(STEP, [event])
	assert(effects._parts._active.size() <= Parts.MAX_ACTIVE)
	assert(effects._parts._settled.size() <= Parts.MAX_SETTLED)

## Troops on the same sheet share one texture RID: each must still be cut from its own figure.
func _check_split_identity() -> void:
	var art := Art.new()
	art.configure_identities({1: "n1", 2: "e2", 3: "d1", 4: "d2"}, {1: 0, 2: 0, 3: 0, 4: 0})
	var halves := {}
	for id in [1, 2, 3, 4]:
		var troop: String = {1: "n1|nord", 2: "e2|emp", 3: "d1|dom", 4: "d2|dom"}[id]
		var look: Dictionary = OriginalArt.MANIFEST.troops[troop].look
		var unit := {"id": id, "look": look, "faction": troop.get_slice("|", 1), "hero": false, "companion": false, "mounted": false, "side": 0}
		var data: PackedByteArray = art.split_torso(unit).upper.get_image().get_data()
		assert(not halves.values().has(data), "%s is cut from its own figure" % troop)
		halves[id] = data
