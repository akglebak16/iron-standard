extends SceneTree
const Event = preload("res://battle/combat_event.gd")
const Effects = preload("res://battle/presentation/impact_effects.gd")
const CombatStep = preload("res://battle/rules/combat_step.gd")
const State = preload("res://battle/model/state.gd")

func _initialize() -> void:
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
	assert(effects._particles.size() == 34 and effects._ground_marks.size() == 1)
	assert(effects._particles[4].kind == Effects.Particle.DUST)
	assert(effects._particles[10].color == Color("#3b4a22"))
	assert(effects._particles[22].position == Vector2(49, 16))
	effects.advance(1.0, [])
	assert(not effects.has_particles() and effects._ground_marks.size() == 17)
	var burst: Array[Dictionary] = []
	for i in 1000:
		burst.append(hit)
	effects.advance(0.0, burst)
	assert(effects._particles.size() == Effects.MAX_PARTICLES)
	for i in 2:
		effects.advance(1.0, [])
		effects.advance(0.0, burst)
	assert(effects._ground_marks.size() == Effects.MAX_GROUND_MARKS)
	print("Impact effects tests passed")
	quit(0)
