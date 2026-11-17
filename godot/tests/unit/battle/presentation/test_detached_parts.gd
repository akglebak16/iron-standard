extends SceneTree
const Effects = preload("res://apps/godot/presentation/battle/impact_effects.gd")
const Event = preload("res://core/battle/combat_event.gd")
const Parts = preload("res://apps/godot/presentation/battle/detached_parts.gd")
const Art = preload("res://apps/godot/presentation/battle/unit_art.gd")
const STEP := 1.0 / 60.0

func _initialize() -> void:
	_check_cut()
	_check_blunt()
	_check_eligibility()
	_check_variety_and_rate()
	print("Detached parts tests passed")
	quit(0)

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
	_seed_for(effects, Parts.Part.ARM)
	effects.advance(0.0, [event])
	assert(effects._parts._active[0].kind == Parts.Part.ARM and effects.headless_units().is_empty())

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
		var choice: int = Effects.HEAVY_CUT_PARTS[effects._rng.randi_range(0, 3)]
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
