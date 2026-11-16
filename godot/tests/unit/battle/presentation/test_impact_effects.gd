extends SceneTree
const Event = preload("res://core/battle/combat_event.gd")
const Effects = preload("res://apps/godot/presentation/battle/impact_effects.gd")
const CombatStep = preload("res://core/battle/rules/combat_step.gd")
const State = preload("res://core/battle/model/state.gd")

func _initialize() -> void:
	_check_native_particles()
	var effects := Effects.new()
	var hit := {"kind": Event.Kind.HIT, "position": Vector2(20, 30), "impact_style": Event.ImpactStyle.BLOOD}
	var dust := {"kind": Event.Kind.HIT, "position": Vector2(30, 30), "impact_style": Event.ImpactStyle.DUST}
	var dark := {"kind": Event.Kind.DOWN, "position": Vector2(40, 30), "impact_style": Event.ImpactStyle.DARK_BLOOD}
	var block := {"kind": Event.Kind.BLOCK, "position": Vector2(50, 30), "contact_offset": Vector2.LEFT}
	var charge := {"kind": Event.Kind.CHARGE, "position": Vector2(60, 30)}
	var battle := State.new()
	var rng := RandomNumberGenerator.new()
	var rng_before := rng.state
	battle.projectiles.append({"side": 0, "time": 0.0, "duration": 0.1, "impact": Vector2(100, 100), "origin": Vector2(0, 10), "throwing": true})
	CombatStep.resolve_projectiles(battle, 0.1, rng)
	assert(battle.projectiles.is_empty() and rng.state == rng_before)
	var events := battle.take_events()
	assert(events == [{"kind": Event.Kind.PROJECTILE_MISSED, "position": Vector2(100, 100), "trajectory": Vector2(100, 90), "throwing": true}])
	events.append_array([hit, dust, dark, block, charge])
	effects.advance(0.0, events)
	assert(effects._particles.size() == 46 and effects._ground_marks.size() == 1)
	assert(effects._particles[4].kind == Effects.Particle.DUST)
	assert(effects._particles[10].color == Color("#3b4a22"))
	assert(effects._particles[34].position == Vector2(49, 16))
	effects.advance(1.0, [])
	assert(effects._particles.is_empty() and effects._ground_marks.size() == 29)
	assert(effects.has_particles() and effects._pools[0].radius > Effects.POOL_INITIAL_RADIUS)
	effects.advance(Effects.POOL_LIFETIME, [])
	assert(not effects.has_particles() and effects._ground_marks[-1].pool)
	var burst: Array[Dictionary] = []
	for i in 1000:
		burst.append(hit)
	effects.advance(0.0, burst)
	assert(effects._particles.size() == Effects.MAX_PARTICLES)
	for i in 2:
		effects.advance(1.0, [])
		effects.advance(0.0, burst)
	assert(effects._ground_marks.size() == Effects.MAX_GROUND_MARKS)
	_check_blood_setting()
	_check_death_effects()
	print("Impact effects tests passed")
	quit(0)

func _check_blood_setting() -> void:
	var effects := Effects.new()
	var heavy := {"kind": Event.Kind.HIT, "position": Vector2.ZERO, "impact_style": Event.ImpactStyle.BLOOD,
		"damage_fraction": 0.18, "amount": 18, "impact_direction": Vector2.RIGHT}
	effects.advance(0.0, [heavy, {"kind": Event.Kind.PROJECTILE_MISSED, "position": Vector2.ZERO, "trajectory": Vector2.RIGHT, "throwing": false}])
	assert(effects._particles.size() == 13)
	assert(float(effects._particles[-1].velocity.x) > 0.0)
	effects.advance(1.0, [heavy])
	assert(effects._ground_marks.size() == 14)
	effects.blood_enabled = false
	assert(effects._particles.is_empty())
	assert(effects._ground_marks.size() == 1 and effects._ground_marks[0].has("trajectory"))
	effects.advance(0.0, [heavy])
	assert(effects._particles.size() == 6 and effects._particles[0].kind == Effects.Particle.DUST)

func _check_death_effects() -> void:
	var effects := Effects.new()
	var down := {"kind": Event.Kind.DOWN, "position": Vector2.ZERO, "impact_style": Event.ImpactStyle.BLOOD,
		"attack": Event.Attack.PROJECTILE, "impact_direction": Vector2.RIGHT, "target_hero": false, "target_companion": false}
	effects.advance(0.0, [down])
	assert(effects._particles.size() == 18 and effects._pools.size() == 1)
	down.target_companion = true
	effects.advance(0.0, [down])
	assert(effects._particles.size() == 30 and effects._pools.size() == 1)
	down.target_companion = false
	down.impact_style = Event.ImpactStyle.DUST
	effects.advance(0.0, [down])
	assert(effects._particles.size() == 36 and effects._particles[-1].kind == Effects.Particle.DUST)
	effects.blood_enabled = false
	assert(effects._pools.is_empty() and effects._particles.size() == 6)
	effects.advance(0.0, [down])
	assert(effects._particles.size() == 6)

func _check_native_particles() -> void:
	var a := Effects.new()
	var b := Effects.new()
	a.native_enabled = false
	assert(b._native != null)
	a._rng.seed = 82
	b._rng.seed = 82
	var marks_a: Array = []
	var marks_b: Array = []
	a.on_mark = func(mark): marks_a.append(mark)
	b.on_mark = func(mark): marks_b.append(mark)
	for index in 500:
		var particle := {"kind": index % 3, "position": Vector2(index * 1.13, index * 2.31),
			"velocity": Vector2(index * 0.31, -index * 0.93), "color": Color(0.4, 0.2, 0.1),
			"remaining": 0.01 + index % 17 * 0.05, "lifetime": 1.0, "radius": 2.7}
		a._particles.append(particle)
		b._particles.append(particle.duplicate())
	for tick in 100:
		a.advance(1.0 / 60.0, [])
		b.advance(1.0 / 60.0, [])
		assert(a._particles == b._particles and marks_a == marks_b, "Visual particle physics/order must stay exact")
		assert(a._rng.state == b._rng.state)
