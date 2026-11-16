extends RefCounted

const Art = preload("res://apps/godot/presentation/battle/unit_art.gd")
const Event = preload("res://core/battle/combat_event.gd")
enum Part { HEAD, ARM, BONE, FRAGMENT }

const MAX_ACTIVE := 70
const MAX_SETTLED := 600
const GRAVITY := 560.0
const BOUNCE := 0.32
const DRAG := 0.55
const SPIN_DRAG := 0.5
const REST_SPEED := 35.0
const SPLASH_SPEED := 60.0
const SPIN := Vector2(-14.0, 14.0)
const FALLBACK_HORIZONTAL := Vector2(-40.0, 40.0)
const BONE_COLOR := Color("#e2dac4")
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.25)
const SHADOW_RADIUS := 3.0
const BONY_WIDTH := 1.6
const JOINT_RADIUS := 1.2
const ARM_HALF_LENGTH := 8.0
const ARM_SLEEVE := Rect2(-8, -2.4, 9, 4.8)
const ARM_SKIN := Rect2(1, -2, 6, 4)
const HAND_RADIUS := 2.6
const ARM_HEIGHT := 15.0
const PROFILES := {
	Part.HEAD: {"lift": Vector2(140, 240), "speed": Vector2(60, 150), "size": Vector2.ZERO, "spread": 0.0},
	Part.ARM: {"lift": Vector2(100, 180), "speed": Vector2(50, 120), "size": Vector2.ZERO, "spread": 0.0},
	Part.BONE: {"lift": Vector2(80, 180), "speed": Vector2(40, 120), "size": Vector2(4, 7), "spread": 1.0},
	Part.FRAGMENT: {"lift": Vector2(60, 160), "speed": Vector2(40, 110), "size": Vector2(2.5, 4), "spread": 0.8},
}

var native_enabled := true
var _native: RefCounted
var _rng: RandomNumberGenerator
var _art := Art.new()
var _active: Array[Dictionary] = []
var _settled: Array[Dictionary] = []
var _next := 0

func _init(rng: RandomNumberGenerator) -> void:
	if ClassDB.class_exists("IronBattleEffects"):
		_native = ClassDB.instantiate("IronBattleEffects")
		_native.configure_parts({"bone_color": BONE_COLOR, "bone_width": BONY_WIDTH, "joint_radius": JOINT_RADIUS,
			"shadow_radius": SHADOW_RADIUS, "shadow_color": SHADOW_COLOR, "arm_half": ARM_HALF_LENGTH,
			"arm_sleeve": ARM_SLEEVE, "arm_skin": ARM_SKIN, "hand_radius": HAND_RADIUS,
			"scale": Art.SPRITE_SCALE, "anchor": Art.HEAD_CENTER})
	_rng = rng

func clear() -> void:
	_active.clear()
	_settled.clear()
	_next = 0

func has_active() -> bool:
	return not _active.is_empty()

static func head_offset(unit: Dictionary) -> Vector2:
	var direction := -1.0 if cos(float(unit.facing)) < 0.0 else 1.0
	var geometry := Art.OriginalArt.layers_for(unit)
	if geometry.has("head_center"):
		var offset: Vector2 = geometry.head_center - geometry.anchor
		offset.x *= direction
		return offset * float(geometry.scale)
	var offset := Art.HEAD_CENTER - Art.ANCHOR
	offset.x *= direction
	if unit.mounted:
		offset.y -= Art.MOUNT_RIDER_RISE
	return offset * Art.SPRITE_SCALE

func emit(kind: Part, event: Dictionary, angle: float, color: Color, count: int = 1) -> void:
	var unit: Dictionary = event.target_visual
	var offset := Vector2(0, -ARM_HEIGHT) if kind == Part.ARM else head_offset(unit)
	var floor_point: Vector2 = event.position + Vector2(offset.x, 0)
	var profile: Dictionary = PROFILES[kind]
	for i in count:
		if _active.size() == MAX_ACTIVE:
			_settle(_active.pop_front())
		var heading := angle + _rng.randf_range(-profile.spread, profile.spread)
		var velocity := Vector2.from_angle(heading) * _sample(profile.speed)
		var part := {"kind": kind, "position": floor_point, "height": -offset.y,
			"vertical_speed": _sample(profile.lift), "velocity": velocity, "angle": 0.0,
			"spin": _sample(SPIN), "size": _sample(profile.size), "color": color}
		match kind:
			Part.HEAD:
				part.texture = _art.detached_head(unit)
				var geometry := _art.layers(unit)
				part.anchor = geometry.get("head_center", Art.HEAD_CENTER)
				part.scale = geometry.get("scale", Art.SPRITE_SCALE)
				part.mirrored = cos(float(unit.facing)) < 0.0
			Part.ARM:
				part.bony = event.impact_style == Event.ImpactStyle.DUST
				part.sleeve = Art.sleeve_color(unit)
				part.skin = Art.skin_color(unit)
			Part.BONE:
				part.velocity.y = _sample(FALLBACK_HORIZONTAL)
		_active.append(part)

func advance(dt: float, splashes: Array[Dictionary]) -> Array[Dictionary]:
	var settled_with_blood: Array[Dictionary] = []
	for i in range(_active.size() - 1, -1, -1):
		var part: Dictionary = _active[i]
		part.vertical_speed -= GRAVITY * dt
		part.height += part.vertical_speed * dt
		part.position += part.velocity * dt
		part.angle += part.spin * dt
		if part.height > 0.0:
			continue
		part.height = 0.0
		if part.color.a > 0.0 and absf(part.vertical_speed) > SPLASH_SPEED:
			splashes.append(part)
		part.vertical_speed *= -BOUNCE
		part.velocity *= DRAG
		part.spin *= SPIN_DRAG
		if part.vertical_speed < REST_SPEED:
			if part.kind in [Part.HEAD, Part.ARM] and part.color.a > 0.0:
				settled_with_blood.append(part)
			_settle(part)
			_active.remove_at(i)
	return settled_with_blood

func draw_ground(canvas: CanvasItem, visible: Rect2) -> void:
	if native_enabled and _native != null:
		_native.draw_parts(canvas.get_canvas_item(), _settled, _next, visible, false)
		return
	for i in _settled.size():
		var part := _settled[(_next + i) % _settled.size()]
		if visible.has_point(part.position):
			_draw(canvas, part)

func draw_air(canvas: CanvasItem) -> void:
	if native_enabled and _native != null:
		_native.draw_parts(canvas.get_canvas_item(), _active, 0, Rect2(), true)
		return
	for part in _active:
		canvas.draw_circle(part.position, SHADOW_RADIUS, SHADOW_COLOR)
		_draw(canvas, part)

func _settle(part: Dictionary) -> void:
	part.height = 0.0
	if _settled.size() < MAX_SETTLED:
		_settled.append(part)
	else:
		_settled[_next] = part
		_next = (_next + 1) % MAX_SETTLED

static func _draw(canvas: CanvasItem, part: Dictionary) -> void:
	var position: Vector2 = part.position - Vector2(0, part.height)
	canvas.draw_set_transform(position, part.angle)
	match part.kind:
		Part.HEAD:
			var direction := -1.0 if part.mirrored else 1.0
			canvas.draw_set_transform(position, part.angle, Vector2(direction, 1.0) * float(part.get("scale", Art.SPRITE_SCALE)))
			if part.texture != null:
				canvas.draw_texture(part.texture, -Vector2(part.get("anchor", Art.HEAD_CENTER)))
		Part.ARM:
			if part.bony:
				_draw_bone(canvas, ARM_HALF_LENGTH)
			else:
				canvas.draw_rect(ARM_SLEEVE, part.sleeve)
				canvas.draw_rect(ARM_SKIN, part.skin)
				canvas.draw_circle(Vector2(ARM_HALF_LENGTH, 0), HAND_RADIUS, part.skin)
		Part.BONE:
			_draw_bone(canvas, part.size * 0.5)
		Part.FRAGMENT:
			canvas.draw_circle(Vector2.ZERO, part.size, part.color)
	canvas.draw_set_transform(Vector2.ZERO)

static func _draw_bone(canvas: CanvasItem, half_length: float) -> void:
	var left := Vector2(-half_length, 0)
	var right := Vector2(half_length, 0)
	canvas.draw_line(left, right, BONE_COLOR, BONY_WIDTH, true)
	canvas.draw_circle(left, JOINT_RADIUS, BONE_COLOR)
	canvas.draw_circle(right, JOINT_RADIUS, BONE_COLOR)

func _sample(interval: Vector2) -> float:
	return _rng.randf_range(interval.x, interval.y)
