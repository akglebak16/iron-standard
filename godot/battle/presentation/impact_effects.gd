extends RefCounted
const Event = preload("res://battle/combat_event.gd")

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
const PROFILES := {
	Particle.BLOOD: {"count": BLOOD_HIT_COUNT, "vx": Vector2(-60, 60), "vy": Vector2(-90, 20), "life": Vector2(0.25, 0.55), "radius": Vector2(1.4, 2.8), "jitter_x": Vector2.ZERO, "jitter_y": Vector2.ZERO},
	Particle.SPARK: {"count": 6, "vx": Vector2(-90, 90), "vy": Vector2(-90, 60), "life": Vector2(0.12, 0.28), "radius": Vector2(1.5, 1.5), "jitter_x": Vector2.ZERO, "jitter_y": Vector2.ZERO},
	Particle.DUST: {"count": 6, "vx": Vector2(-25, 25), "vy": Vector2(-25, -5), "life": Vector2(0.4, 0.8), "radius": Vector2(4, 8), "jitter_x": Vector2(-10, 10), "jitter_y": Vector2(-4, 6)},
}

var _rng := RandomNumberGenerator.new()
var _particles: Array[Dictionary] = []
var _ground_marks: Array[Dictionary] = []
var _next_mark := 0
var blood_enabled := true:
	set(value):
		blood_enabled = value
		if not value:
			_particles = _particles.filter(func(particle): return particle.kind != Particle.BLOOD)
			_remove_blood_marks()

func _init() -> void:
	_rng.randomize()

func advance(dt: float, events: Array[Dictionary]) -> void:
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
	for event in events:
		match event.kind:
			Event.Kind.HIT:
				if not blood_enabled or event.impact_style == Event.ImpactStyle.DUST:
					_emit(Particle.DUST, event.position + DEATH_OFFSET, DUST_COLOR)
				else:
					_emit(Particle.BLOOD, event.position + BLOOD_OFFSET, BLOOD_COLORS[event.impact_style])
					if event.get("damage_fraction", 0.0) >= HEAVY_HIT_THRESHOLD and not event.get("lethal", false):
						_spray(event, BLOOD_COLORS[event.impact_style])
			Event.Kind.DOWN:
				if blood_enabled and BLOOD_COLORS.has(event.impact_style):
					_emit(Particle.BLOOD, event.position + DEATH_OFFSET, BLOOD_COLORS[event.impact_style], BLOOD_DOWN_COUNT)
			Event.Kind.BLOCK:
				_emit(Particle.SPARK, event.position + event.contact_offset + DEATH_OFFSET, SPARK_COLOR)
			Event.Kind.CHARGE:
				_emit(Particle.DUST, event.position, DUST_COLOR)
			Event.Kind.PROJECTILE_MISSED:
				_remember({"position": event.position, "trajectory": event.trajectory, "throwing": event.throwing})

func has_particles() -> bool:
	return not _particles.is_empty()

func draw_ground(canvas: CanvasItem) -> void:
	# The ring's oldest element is the next slot to overwrite.
	for i in _ground_marks.size():
		var mark := _ground_marks[(_next_mark + i) % _ground_marks.size()]
		var point: Vector2 = mark.position
		if mark.has("trajectory"):
			var direction := Vector2.from_angle(mark.trajectory.angle() - MISS_TILT)
			var length := JAVELIN_LENGTH if mark.throwing else ARROW_LENGTH
			canvas.draw_line(point - direction * length, point, SHAFT_COLOR, SHAFT_WIDTH, true)
			canvas.draw_line(point - direction * FLETCHING_FAR, point - direction * FLETCHING_NEAR, FLETCHING_COLOR, FLETCHING_WIDTH, true)
		else:
			var color: Color = mark.color
			color.a = SPLAT_ALPHA
			_draw_splat(canvas, point + SPLAT_OFFSET, mark.radius, color)

func draw_particles(canvas: CanvasItem) -> void:
	for particle in _particles:
		var color: Color = particle.color
		color.a = clampf(particle.remaining / particle.lifetime, 0.0, 1.0)
		canvas.draw_circle(particle.position, particle.radius, color)

static func _draw_splat(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in SPLAT_SEGMENTS:
		points.append(center + Vector2.from_angle(TAU * i / SPLAT_SEGMENTS) * SPLAT_SCALE * radius)
	canvas.draw_colored_polygon(points, color)

func _spray(event: Dictionary, color: Color) -> void:
	var direction: Vector2 = event.impact_direction
	var angle := direction.angle() if direction != Vector2.ZERO else _rng.randf_range(0.0, TAU)
	var count := SPRAY_BASE_COUNT + mini(SPRAY_MAX_EXTRA, floori(event.amount / SPRAY_DAMAGE_PER_EXTRA))
	for i in mini(count, MAX_PARTICLES - _particles.size()):
		var velocity := Vector2.from_angle(angle + _rng.randf_range(-SPRAY_SPREAD, SPRAY_SPREAD)) * _sample(SPRAY_SPEED)
		velocity.y = velocity.y * SPRAY_VERTICAL_SCALE - _sample(SPRAY_LIFT)
		var lifetime := _sample(SPRAY_LIFE)
		_particles.append({"kind": Particle.BLOOD, "position": event.position + SPRAY_OFFSET,
			"velocity": velocity, "color": color, "remaining": lifetime, "lifetime": lifetime, "radius": _sample(SPRAY_RADIUS)})

func _remove_blood_marks() -> void:
	var kept: Array[Dictionary] = []
	for i in _ground_marks.size():
		var mark := _ground_marks[(_next_mark + i) % _ground_marks.size()]
		if mark.has("trajectory"):
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
	if _ground_marks.size() < MAX_GROUND_MARKS:
		_ground_marks.append(mark)
	else:
		_ground_marks[_next_mark] = mark
		_next_mark = (_next_mark + 1) % MAX_GROUND_MARKS
