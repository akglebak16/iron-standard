extends RefCounted
## Exact presentation formulas from drawUnitSprite, swingPose, battleDraw and fallDraw.
## Positions/weapon offsets are original 2x canvas pixels, before the 0.31 world scale.
const BUMP_DECAY := 4.2
const FALL_SECONDS := 0.34
const CORPSE_ALPHA := 0.9

static func weapon_kind(weapon: Variant) -> int:
	if weapon == "heraldic_xbow": return 4
	if weapon in ["spear", "halberd", "lance"]: return 2
	if weapon in ["bow", "xbow"]: return 3
	return 0 if weapon == null or weapon == "" else 1

## x = angle, y/z = local displacement. Exported JS fixtures test each piecewise boundary.
static func swing_pose(kind: int, bump: float) -> Vector3:
	var p := 1.0 - bump
	var angle := 0.0
	var dx := 0.0
	var dy := 0.0
	if kind == 4:
		# The shot event sets bump to 0.5. Aim settles before it; recoil starts at it.
		if bump > 0.5:
			var aim := (bump - 0.5) * 2.0
			angle = 0.16 * aim * aim
			dy = 5.0 * aim
		else:
			var recoil := bump * 2.0
			dx = -7.0 * recoil * recoil
			dy = 1.5 * recoil
			angle = -0.045 * recoil
	elif kind == 3:
		var q := clampf(1.0 - bump * 2.0, 0.0, 1.0)
		dx = -5.0 * (1.0 - q) * (1.0 - q)
		angle = -0.12 * (1.0 - q)
	elif kind == 2:
		if p < 0.25:
			var q := p / 0.25
			angle = 0.1 * q
			dx = -7.0 * q
			dy = 3.0 * q
		elif p < 0.5:
			var q := (p - 0.25) / 0.25
			var ease := 1.0 - (1.0 - q) * (1.0 - q)
			angle = lerpf(0.1, 0.5, ease)
			dx = lerpf(-7.0, 16.0, ease)
			dy = lerpf(3.0, 2.0, ease)
		else:
			var q := (p - 0.5) / 0.5
			angle = lerpf(0.5, 0.0, q)
			dx = lerpf(16.0, 0.0, q)
			dy = lerpf(2.0, 0.0, q)
	else:
		if p < 0.28:
			angle = -0.55 * sin((p / 0.28) * PI / 2.0)
		elif p < 0.55:
			var q := (p - 0.28) / 0.27
			var ease := 1.0 - pow(1.0 - q, 3.0)
			angle = lerpf(-0.55, 1.25, ease)
		else:
			var q := (p - 0.55) / 0.45
			angle = lerpf(1.25, 0.0, q * q * (3.0 - 2.0 * q))
	return Vector3(angle, dx, dy)

static func body_transform(at: Vector2, time: float, phase: float, speed: float, mounted: bool,
		facing: float, bump: float, sprite_scale := 0.31) -> Transform2D:
	var direction := -1.0 if cos(facing) < 0.0 else 1.0
	var breath := 1.0 + sin(time * 2.1 + phase) * 0.012
	var lean := clampf(speed / 90.0, 0.0, 1.0) * 0.055 if speed > 12.0 else 0.0
	var offset := Vector2.ZERO
	if speed > 12.0:
		offset.y = sin(time * (15.0 if mounted else 11.0) + phase) * (2.0 if mounted else 1.3)
	if bump > 0.0:
		offset += Vector2.from_angle(facing) * sin((1.0 - bump) * PI) * 7.0
	var horse_angle := 0.0
	if mounted and speed > 12.0:
		var horse_phase := time * (7.0 + clampf(speed / 60.0, 0.0, 3.0)) + phase
		offset.y -= absf(sin(horse_phase)) * 2.6
		horse_angle = sin(horse_phase) * 0.018 * direction
	# Canvas order is horse rotation -> nonuniform scale -> lean, not a summed rotation.
	var x_axis := Vector2(direction * sprite_scale * cos(lean), sprite_scale * breath * sin(lean)).rotated(horse_angle)
	var y_axis := Vector2(-direction * sprite_scale * sin(lean), sprite_scale * breath * cos(lean)).rotated(horse_angle)
	return Transform2D(x_axis, y_axis, at + offset)

static func weapon_transform(body: Transform2D, anchor: Vector2, pivot: Vector2, pose: Vector3) -> Transform2D:
	return body * Transform2D(pose.x, pivot - anchor + Vector2(pose.y, pose.z))

static func fall_progress(elapsed: float) -> float:
	return clampf(elapsed / FALL_SECONDS, 0.0, 1.0)

static func fall_transform(at: Vector2, elapsed: float, rotation: float, sprite_scale := 0.31) -> Transform2D:
	var p := fall_progress(elapsed)
	return Transform2D(rotation * p * p, at - Vector2(0, sin(p * PI) * 5.0)).scaled_local(Vector2.ONE * sprite_scale)

static func fall_offset(anchor: Vector2, elapsed: float) -> Vector2:
	var p := fall_progress(elapsed)
	return -anchor + Vector2(0, 60.0 * p * p)

static func fall_alpha(elapsed: float) -> float:
	return CORPSE_ALPHA if fall_progress(elapsed) >= 1.0 else 1.0
