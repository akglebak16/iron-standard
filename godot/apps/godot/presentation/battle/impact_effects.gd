extends RefCounted
const Event = preload("res://core/battle/combat_event.gd")
const Parts = preload("res://apps/godot/presentation/battle/detached_parts.gd")

enum Particle { BLOOD, SPARK, DUST }

const MAX_PARTICLES := 500
const MAX_GROUND_MARKS := 600
const GRAVITY := 260.0
const BLOOD_OFFSET := Vector2(0, -16)
const DEATH_OFFSET := Vector2(0, -14)
const BLOOD_HIT_COUNT := 4
const BLOOD_DOWN_COUNT := 12
const SPARK_COLOR := Color("#ffe9a8")
const DUST_COLOR := Color("#b8a880")
const BLOOD_COLORS := {
	Event.ImpactStyle.BLOOD: Color("#8f1a12"),
	Event.ImpactStyle.DARK_BLOOD: Color("#3b4a22"),
}
const STONE_SPARK_OFFSET := Vector2(0, -6)
const STONE_DUST_PUFFS := 4
const GATE_DUST_PUFFS := 10
const STONE_PEBBLES := 4
const STONE_CRATER_RADII := Vector2(17, 9)
const STONE_CRATER_COLOR := Color(40 / 255.0, 30 / 255.0, 20 / 255.0, 0.45)
const STONE_PEBBLE_COLOR := Color("#6d6252")
const SHAFT_COLOR := Color("#3a2a18")
const FLETCHING_COLOR := Color("#e6e0cf")
const MISS_TILT := 0.5
const ARROW_LENGTH := 9.0
const JAVELIN_LENGTH := 18.0
const SHAFT_WIDTH := 1.4
const FLETCHING_WIDTH := 2.0
const FLETCHING_NEAR := 7.0
const FLETCHING_FAR := 10.0
const SPLAT_ALPHA := 0.6
const SPLAT_OFFSET := Vector2(0, 14)
const SPLAT_SCALE := Vector2(0.9, 0.45)
const SPLAT_SEGMENTS := 12
const HEAVY_HIT_THRESHOLD := 0.18
const SPRAY_OFFSET := Vector2(0, -20)
const SPRAY_BASE_COUNT := 6
const SPRAY_MAX_EXTRA := 10
const SPRAY_DAMAGE_PER_EXTRA := 6.0
const SPRAY_SPREAD := 0.7
const SPRAY_SPEED := Vector2(45, 150)
const SPRAY_LIFT := Vector2(40, 80)
const SPRAY_VERTICAL_SCALE := 0.5
const SPRAY_LIFE := Vector2(0.3, 0.65)
const SPRAY_RADIUS := Vector2(1.5, 3.4)
const DEATH_SPRAY_OFFSET := Vector2(0, -18)
const DEATH_SPRAY_COUNT := 12
const ARROW_DEATH_SPRAY_COUNT := 6
const DEATH_SPRAY_SPEED := 140.0
const CHARGE_SPRAY_SPEED := 220.0
const DEATH_SPRAY_LIFT := Vector2(45, 90)
const SPRAY_MIN_SPEED_SHARE := 0.3
const BONE_DUST_COLOR := Color("#cfc6ad")
const BONE_DUST_OFFSET := Vector2(0, -10)
const POOL_LIMIT := 90
const POOL_INITIAL_RADIUS := 3.0
const POOL_MAX_RADIUS := Vector2(16, 26)
const POOL_X_JITTER := Vector2(-6, 6)
const POOL_Y_JITTER := Vector2(-2, 5)
const POOL_LIFETIME := 2.6
const POOL_GROWTH_RATE := 0.5
const POOL_ALPHA := 0.55
const POOL_SCALE := Vector2(1.0, 0.5)
const PART_POOL_RADIUS := Vector2(6, 11)
const HEADLESS_POOL_BONUS := 8.0
const DISMEMBER_CHANCE := 0.55
const CUT_PARTS := [Parts.Part.HEAD, Parts.Part.ARM, Parts.Part.LEG]
const HEAVY_CUT_PARTS := [Parts.Part.HEAD, Parts.Part.ARM, Parts.Part.LEG, Parts.Part.TORSO]
const HEAVY_FATAL_THRESHOLD := 0.3
const FOUNTAIN_DURATION := Vector2(0.6, 1.0)
const FOUNTAIN_RATE := 120.0
const FOUNTAIN_LIMIT := Parts.MAX_ACTIVE
const FOUNTAIN_OFFSET := Vector2(0, 3)
const FOUNTAIN_SPEED := Vector2(10, 50)
const FOUNTAIN_LIFT := Vector2(90, 170)
const FOUNTAIN_PARTICLE_LIFE := Vector2(0.3, 0.5)
const FOUNTAIN_RADIUS := Vector2(1.6, 2.8)
const SEVER_SPRAY_SPEED := Vector2(51, 170)
const SEVER_SPRAY_LIFT := Vector2(80, 160)
const SHATTER_SPRAY_SPEED := Vector2(57, 190)
const SHATTER_SPRAY_LIFT := Vector2(60, 120)
const ARM_SPRAY_SPEED := Vector2(45, 150)
const ARM_SPRAY_LIFT := Vector2(55, 110)
const ARM_SPRAY_OFFSET := Vector2(0, -13)
const SEVER_SPRAY_COUNT := 18
const SHATTER_SPRAY_COUNT := 30
const ARM_SPRAY_COUNT := 14
const HEAD_BONE_COUNT := 3
const SKELETON_SHATTER_BONE_COUNT := 6
const SHATTER_FRAGMENT_COUNT := 3
const HEAD_SHATTER_PALE_COUNT := 6
const PALE_FRAGMENT_COLOR := Color("#e8e0cc")
const PALE_FRAGMENT_SPEED := Vector2(36, 120)
const PALE_FRAGMENT_LIFT := Vector2(45, 90)
const BOUNCE_SPRAY_COUNT := 3
const BOUNCE_SPRAY_SPEED := Vector2(12, 40)
const BOUNCE_SPRAY_LIFT := Vector2(10, 20)
const CUT_DOWN_LABEL := "Голова с плеч!"
const BLUNT_DOWN_LABEL := "Всмятку!"
const PROFILES := {
	Particle.BLOOD: {"count": BLOOD_HIT_COUNT, "vx": Vector2(-60, 60), "vy": Vector2(-90, 20), "life": Vector2(0.25, 0.55), "radius": Vector2(1.4, 2.8), "jitter_x": Vector2.ZERO, "jitter_y": Vector2.ZERO},
	Particle.SPARK: {"count": 6, "vx": Vector2(-90, 90), "vy": Vector2(-90, 60), "life": Vector2(0.12, 0.28), "radius": Vector2(1.5, 1.5), "jitter_x": Vector2.ZERO, "jitter_y": Vector2.ZERO},
	Particle.DUST: {"count": 6, "vx": Vector2(-25, 25), "vy": Vector2(-25, -5), "life": Vector2(0.4, 0.8), "radius": Vector2(4, 8), "jitter_x": Vector2(-10, 10), "jitter_y": Vector2(-4, 6)},
}

var native_enabled := true
var _native: RefCounted
var _rng := RandomNumberGenerator.new()
var _parts := Parts.new(_rng)
var _fountains: Array[Dictionary] = []
var _headless: Dictionary = {}
var _split_torsos: Dictionary = {}
var _particles: Array[Dictionary] = []
var _ground_marks: Array[Dictionary] = []
var _pools: Array[Dictionary] = []
var _next_mark := 0
var blood_enabled := true:
	set(value):
		blood_enabled = value
		if not value:
			_particles = _particles.filter(func(particle): return particle.kind != Particle.BLOOD)
			_pools.clear()
			_parts.clear()
			_fountains.clear()
			_headless.clear()
			_split_torsos.clear()
			_remove_blood_marks()

func _init() -> void:
	if ClassDB.class_exists("IronBattleEffects"): _native = ClassDB.instantiate("IronBattleEffects")
	_rng.randomize()

func advance(dt: float, events: Array[Dictionary]) -> Array[Dictionary]:
	_advance_pools(dt)
	if native_enabled and _native != null:
		for particle in _native.advance_particles(_particles, dt, GRAVITY, Particle.DUST):
			if particle.kind == Particle.BLOOD: _remember({"position": particle.position, "radius": particle.radius, "color": particle.color})
	else:
		for i in range(_particles.size() - 1, -1, -1):
			var particle := _particles[i]
			particle.remaining -= dt
			if particle.remaining <= 0.0:
				if particle.kind == Particle.BLOOD:
					_remember({"position": particle.position, "radius": particle.radius, "color": particle.color})
				_particles.remove_at(i)
				continue
			particle.position += particle.velocity * dt
			if particle.kind != Particle.DUST:
				particle.velocity.y += GRAVITY * dt
	var splashes: Array[Dictionary] = []
	for part in _parts.advance(dt, splashes):
		_add_pool(part.position, _sample(PART_POOL_RADIUS), part.color)
	for part in splashes:
		_spray({"position": part.position, "impact_direction": Vector2.RIGHT}, part.color,
			BOUNCE_SPRAY_COUNT, Vector2.ZERO, BOUNCE_SPRAY_SPEED, BOUNCE_SPRAY_LIFT)
	_advance_fountains(dt)
	var labels: Array[Dictionary] = []
	for event in events:
		match event.kind:
			Event.Kind.HIT:
				if not blood_enabled or event.impact_style == Event.ImpactStyle.DUST:
					_emit(Particle.DUST, event.position + DEATH_OFFSET, DUST_COLOR)
				else:
					_emit(Particle.BLOOD, event.position + BLOOD_OFFSET, BLOOD_COLORS[event.impact_style])
					if event.get("damage_fraction", 0.0) >= HEAVY_HIT_THRESHOLD and not event.get("lethal", false):
						var count := SPRAY_BASE_COUNT + mini(SPRAY_MAX_EXTRA, floori(event.amount / SPRAY_DAMAGE_PER_EXTRA))
						_spray(event, BLOOD_COLORS[event.impact_style], count, SPRAY_OFFSET, SPRAY_SPEED, SPRAY_LIFT)
			Event.Kind.DOWN:
				var headless := _on_down(event)
				if headless and event.source_hero:
					var caption := CUT_DOWN_LABEL if event.melee_impact == Event.MeleeImpact.CUT else BLUNT_DOWN_LABEL
					labels.append({"position": event.position, "text": caption})
			Event.Kind.BLOCK:
				_emit(Particle.SPARK, event.position + event.contact_offset + DEATH_OFFSET, SPARK_COLOR)
			Event.Kind.CHARGE:
				_emit(Particle.DUST, event.position, DUST_COLOR)
			Event.Kind.STONE_LANDED:
				_emit(Particle.SPARK, event.position + STONE_SPARK_OFFSET, SPARK_COLOR)
				for i in STONE_DUST_PUFFS:
					_emit(Particle.DUST, event.position + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-12, 12)), DUST_COLOR)
				var pebbles: Array[Dictionary] = []
				for i in STONE_PEBBLES:
					pebbles.append({"offset": Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-7, 7)), "radii": Vector2(_rng.randf_range(2, 4), _rng.randf_range(1.5, 3))})
				_remember({"position": event.position, "rubble": pebbles})
			Event.Kind.PROJECTILE_MISSED:
				_remember({"position": event.position, "trajectory": event.trajectory, "throwing": event.throwing})
			Event.Kind.GATE_BROKEN:
				# gateBreak: ten puffs of dust across the fallen gate.
				var half: float = (event.gap.y - event.gap.x) * 0.5
				for i in GATE_DUST_PUFFS:
					_emit(Particle.DUST, event.position + Vector2(_rng.randf_range(-24, 24), _rng.randf_range(-half, half)), DUST_COLOR)
	return labels

func has_particles() -> bool:
	return not _particles.is_empty() or not _pools.is_empty() or _parts.has_active() or not _fountains.is_empty()

func headless_units() -> Dictionary:
	return _headless

func split_torsos() -> Dictionary:
	return _split_torsos

## Set by the view: marks are painted once into the ground bake instead of every frame.
var on_mark := Callable()

func marks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in _ground_marks.size():
		out.append(_ground_marks[(_next_mark + i) % _ground_marks.size()])
	return out

func draw_ground(canvas: CanvasItem, visible: Rect2) -> void:
	if not on_mark.is_valid():
		# The ring's oldest element is the next slot to overwrite.
		for i in _ground_marks.size():
			draw_mark(canvas, _ground_marks[(_next_mark + i) % _ground_marks.size()])
	if native_enabled and _native != null:
		_native.draw_pools(canvas.get_canvas_item(), _pools, SPLAT_SEGMENTS, POOL_ALPHA, POOL_SCALE)
	else:
		for pool in _pools:
			var color: Color = pool.color
			color.a = POOL_ALPHA
			_draw_ellipse(canvas, pool.position, pool.radius, POOL_SCALE, color)
	_parts.native_enabled = native_enabled
	_parts.draw_ground(canvas, visible)

static func draw_mark(canvas: CanvasItem, mark: Dictionary) -> void:
	var point: Vector2 = mark.position
	if mark.has("rubble"):
		_draw_ellipse_radii(canvas, point, STONE_CRATER_RADII, STONE_CRATER_COLOR)
		for pebble in mark.rubble:
			_draw_ellipse_radii(canvas, point + pebble.offset, pebble.radii, STONE_PEBBLE_COLOR)
	elif mark.has("trajectory"):
		var direction := Vector2.from_angle(mark.trajectory.angle() - MISS_TILT)
		var length := JAVELIN_LENGTH if mark.throwing else ARROW_LENGTH
		canvas.draw_line(point - direction * length, point, SHAFT_COLOR, SHAFT_WIDTH, true)
		canvas.draw_line(point - direction * FLETCHING_FAR, point - direction * FLETCHING_NEAR, FLETCHING_COLOR, FLETCHING_WIDTH, true)
	else:
		var color: Color = mark.color
		var pool: bool = mark.get("pool", false)
		color.a = POOL_ALPHA if pool else SPLAT_ALPHA
		_draw_ellipse(canvas, point if pool else point + SPLAT_OFFSET, mark.radius, POOL_SCALE if pool else SPLAT_SCALE, color)

func draw_particles(canvas: CanvasItem) -> void:
	if native_enabled and _native != null:
		_native.draw_particles(canvas.get_canvas_item(), _particles)
	else:
		for particle in _particles:
			var color: Color = particle.color
			color.a = clampf(particle.remaining / particle.lifetime, 0.0, 1.0)
			canvas.draw_circle(particle.position, particle.radius, color)
	_parts.native_enabled = native_enabled
	_parts.draw_air(canvas)

static func _draw_ellipse_radii(canvas: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	_draw_ellipse(canvas, center, 1.0, radii, color)

static func _draw_ellipse(canvas: CanvasItem, center: Vector2, radius: float, scale: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in SPLAT_SEGMENTS:
		points.append(center + Vector2.from_angle(TAU * i / SPLAT_SEGMENTS) * scale * radius)
	canvas.draw_colored_polygon(points, color)

func _on_down(event: Dictionary) -> bool:
	if not blood_enabled:
		return false
	var ordinary: bool = not event.get("target_hero", false) and not event.get("target_companion", false)
	var color: Color = BLOOD_COLORS.get(event.impact_style, Color.TRANSPARENT)
	var without_head := _detach_on_down(event, color) if ordinary else false
	if not BLOOD_COLORS.has(event.impact_style):
		if ordinary:
			_emit(Particle.DUST, event.position + BONE_DUST_OFFSET, BONE_DUST_COLOR)
		return without_head
	_emit(Particle.BLOOD, event.position + DEATH_OFFSET, color, BLOOD_DOWN_COUNT)
	if not ordinary:
		return false
	var attack: int = event.get("attack", Event.Attack.NONE)
	var speed := CHARGE_SPRAY_SPEED if attack == Event.Attack.CHARGE else DEATH_SPRAY_SPEED
	var count := ARROW_DEATH_SPRAY_COUNT if attack == Event.Attack.PROJECTILE else DEATH_SPRAY_COUNT
	_spray(event, color, count, DEATH_SPRAY_OFFSET, Vector2(speed * SPRAY_MIN_SPEED_SHARE, speed), DEATH_SPRAY_LIFT)
	var position: Vector2 = event.position + Vector2(_sample(POOL_X_JITTER), _sample(POOL_Y_JITTER))
	var limit := _sample(POOL_MAX_RADIUS) + (HEADLESS_POOL_BONUS if without_head else 0.0)
	_add_pool(position, limit, color)
	return without_head

func _detach_on_down(event: Dictionary, color: Color) -> bool:
	if event.get("attack") != Event.Attack.MELEE or not event.has("target_visual"):
		return false
	var melee_impact: int = event.melee_impact
	if melee_impact not in [Event.MeleeImpact.CUT, Event.MeleeImpact.BLUNT]:
		return false
	# One gate for all eligible fatalities, independent of attacker and damage.
	if _rng.randf() >= DISMEMBER_CHANCE:
		return false
	var choices: Array = HEAVY_CUT_PARTS if event.damage_fraction > HEAVY_FATAL_THRESHOLD else CUT_PARTS
	var kind: int = choices[_rng.randi_range(0, choices.size() - 1)] if melee_impact == Event.MeleeImpact.CUT else Parts.Part.HEAD
	var direction: Vector2 = event.impact_direction
	var angle := direction.angle() if direction != Vector2.ZERO else _rng.randf_range(0.0, TAU)
	var head := Parts.head_offset(event.target_visual)
	var has_blood := color.a > 0.0
	if melee_impact == Event.MeleeImpact.CUT and kind == Parts.Part.HEAD:
		_parts.emit(Parts.Part.HEAD, event, angle, color)
		if has_blood:
			_spray(event, color, SEVER_SPRAY_COUNT, head + FOUNTAIN_OFFSET, SEVER_SPRAY_SPEED, SEVER_SPRAY_LIFT)
			if _fountains.size() == FOUNTAIN_LIMIT:
				_fountains.pop_front()
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			_fountains.append({"position": Vector2(event.position) + head + FOUNTAIN_OFFSET,
				"remaining": _sample(FOUNTAIN_DURATION), "carry": 0.0, "horizontal": cos(angle + side * PI * 0.5), "color": color})
		else:
			_parts.emit(Parts.Part.BONE, event, angle, color, HEAD_BONE_COUNT)
		_headless[event.target_id] = true
	elif melee_impact == Event.MeleeImpact.BLUNT:
		if has_blood:
			_spray(event, color, SHATTER_SPRAY_COUNT, head, SHATTER_SPRAY_SPEED, SHATTER_SPRAY_LIFT)
			_spray(event, PALE_FRAGMENT_COLOR, HEAD_SHATTER_PALE_COUNT, head, PALE_FRAGMENT_SPEED, PALE_FRAGMENT_LIFT)
			_parts.emit(Parts.Part.FRAGMENT, event, angle, color, SHATTER_FRAGMENT_COUNT)
		_parts.emit(Parts.Part.BONE, event, angle, color, HEAD_BONE_COUNT if has_blood else SKELETON_SHATTER_BONE_COUNT)
		_headless[event.target_id] = true
	else:
		_parts.emit(kind, event, angle, color)
		if kind == Parts.Part.TORSO:
			_split_torsos[event.target_id] = true
		if has_blood:
			_spray(event, color, ARM_SPRAY_COUNT, ARM_SPRAY_OFFSET, ARM_SPRAY_SPEED, ARM_SPRAY_LIFT)
	return _headless.has(event.target_id)

func _advance_fountains(dt: float) -> void:
	for i in range(_fountains.size() - 1, -1, -1):
		var fountain := _fountains[i]
		var requested: float = fountain.carry + minf(dt, fountain.remaining) * FOUNTAIN_RATE
		var count := floori(requested)
		fountain.carry = requested - count
		for drop in mini(count, MAX_PARTICLES - _particles.size()):
			var lifetime := _sample(FOUNTAIN_PARTICLE_LIFE)
			_particles.append({"kind": Particle.BLOOD, "position": fountain.position,
				"velocity": Vector2(fountain.horizontal * _sample(FOUNTAIN_SPEED), -_sample(FOUNTAIN_LIFT) * fountain.remaining),
				"color": fountain.color, "remaining": lifetime, "lifetime": lifetime, "radius": _sample(FOUNTAIN_RADIUS)})
		fountain.remaining -= dt
		if fountain.remaining <= 0.0:
			_fountains.remove_at(i)

func _add_pool(position: Vector2, limit: float, color: Color) -> void:
	if _pools.size() == POOL_LIMIT:
		_bake_pool(_pools.pop_front())
	_pools.append({"position": position, "radius": POOL_INITIAL_RADIUS, "limit": limit, "age": 0.0, "color": color})

func _advance_pools(dt: float) -> void:
	for i in range(_pools.size() - 1, -1, -1):
		var pool := _pools[i]
		pool.age += dt
		pool.radius = minf(pool.limit, POOL_INITIAL_RADIUS + pool.age * pool.limit * POOL_GROWTH_RATE)
		if pool.age >= POOL_LIFETIME:
			_bake_pool(pool)
			_pools.remove_at(i)

func _bake_pool(pool: Dictionary) -> void:
	_remember({"position": pool.position, "radius": pool.radius, "color": pool.color, "pool": true})

func _spray(event: Dictionary, color: Color, count: int, offset: Vector2, speed: Vector2, lift: Vector2) -> void:
	var direction: Vector2 = event.get("impact_direction", Vector2.ZERO)
	var angle := direction.angle() if direction != Vector2.ZERO else _rng.randf_range(0.0, TAU)
	for i in mini(count, MAX_PARTICLES - _particles.size()):
		var velocity := Vector2.from_angle(angle + _rng.randf_range(-SPRAY_SPREAD, SPRAY_SPREAD)) * _sample(speed)
		velocity.y = velocity.y * SPRAY_VERTICAL_SCALE - _sample(lift)
		var lifetime := _sample(SPRAY_LIFE)
		_particles.append({"kind": Particle.BLOOD, "position": event.position + offset,
			"velocity": velocity, "color": color, "remaining": lifetime, "lifetime": lifetime, "radius": _sample(SPRAY_RADIUS)})

func _remove_blood_marks() -> void:
	var kept: Array[Dictionary] = []
	for i in _ground_marks.size():
		var mark := _ground_marks[(_next_mark + i) % _ground_marks.size()]
		if mark.has("trajectory") or mark.has("rubble"):
			kept.append(mark)
	_ground_marks = kept
	_next_mark = _ground_marks.size() % MAX_GROUND_MARKS

func _emit(kind: Particle, position: Vector2, color: Color, count_override: int = 0) -> void:
	var profile: Dictionary = PROFILES[kind]
	var count: int = count_override if count_override > 0 else profile.count
	for i in mini(count, MAX_PARTICLES - _particles.size()):
		var lifetime := _sample(profile.life)
		_particles.append({
			"kind": kind, "position": position + Vector2(_sample(profile.jitter_x), _sample(profile.jitter_y)),
			"velocity": Vector2(_sample(profile.vx), _sample(profile.vy)), "color": color,
			"remaining": lifetime, "lifetime": lifetime, "radius": _sample(profile.radius),
		})

func _sample(interval: Vector2) -> float:
	return _rng.randf_range(interval.x, interval.y)

func _remember(mark: Dictionary) -> void:
	if on_mark.is_valid():
		on_mark.call(mark)
	if _ground_marks.size() < MAX_GROUND_MARKS:
		_ground_marks.append(mark)
	else:
		_ground_marks[_next_mark] = mark
		_next_mark = (_next_mark + 1) % MAX_GROUND_MARKS
