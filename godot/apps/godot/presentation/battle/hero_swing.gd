extends RefCounted
## The decorative attack arc in the original battleDraw. Damage remains simulation-owned.
const Config = preload("res://core/battle/config.gd")
const BASE_RADIUS := 34.0
const MOUNT_RADIUS := 8.0
const ARC_LENGTH := 0.7
const WIDTH := 5.0
const OFFSET := Vector2(0, -14)

static func pose(action: Dictionary) -> Dictionary:
	if action.is_empty() or action.dead or action.remaining <= 0: return {}
	var progress: float = 1.0 - action.remaining / Config.HERO_SWING_SECONDS
	var end: float = action.facing - 1.0 + progress * 2.0
	return {"center": Vector2(action.position) + OFFSET,
		"radius": BASE_RADIUS + float(action.reach) + (MOUNT_RADIUS if action.mounted else 0.0),
		"start": end - ARC_LENGTH, "end": end,
		"color": Color(1, 250 / 255.0, 230 / 255.0, 0.85 - progress * 0.7)}

static func draw(canvas: CanvasItem, action: Dictionary) -> void:
	var values := pose(action)
	if values.is_empty(): return
	canvas.draw_arc(values.center, values.radius, values.start, values.end, 24, values.color, WIDTH, true)
	for angle in [values.start, values.end]:
		canvas.draw_circle(values.center + Vector2.from_angle(angle) * values.radius, WIDTH / 2, values.color, true, -1, true)
