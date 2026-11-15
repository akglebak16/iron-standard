extends RefCounted
## commandDraw in src/06h_polish.js: for each selected group told to hold, a faint ring where it should stand, a line
## showing its facing and, while the soldiers are still on their way, a dashed line from them to that spot.
const Config = preload("res://core/battle/config.gd")
const COLOR := Color(237 / 255.0, 207 / 255.0, 123 / 255.0, 0.3)
const RING := Vector2(22, 9)
const FACING_LENGTH := 28.0
const WIDTH := 1.5
const DASH := 6.0
const GAP := 9.0
const ON_SPOT := 40.0
const SEGMENTS := 24

## Groups that get a ghost: the selected ones (or all with ALL_GROUPS) holding, not backing off.
static func ghosts(groups: Array, selection: int) -> Array:
	return groups.filter(func(g): return (selection == Config.ALL_GROUPS or int(g.kind) == selection) and g.order == Config.ORDER_HOLD and not g.backing)

static func draw(canvas: CanvasItem, groups: Array, selection: int) -> void:
	for group in ghosts(groups, selection):
		var target: Vector2 = group.center
		var centroid: Vector2 = group.centroid
		if centroid.is_finite() and centroid.distance_to(target) > ON_SPOT:
			var along := centroid.direction_to(target)
			var length := centroid.distance_to(target)
			var at := 0.0
			while at < length:
				canvas.draw_line(centroid + along * at, centroid + along * minf(at + DASH, length), COLOR, WIDTH, true)
				at += DASH + GAP
		var ring := PackedVector2Array()
		for i in SEGMENTS + 1:
			ring.append(target + Vector2(cos(TAU * i / SEGMENTS) * RING.x, sin(TAU * i / SEGMENTS) * RING.y))
		canvas.draw_polyline(ring, COLOR, WIDTH, true)
		canvas.draw_line(target, target + Vector2.from_angle(float(group.direction)) * FACING_LENGTH, COLOR, WIDTH, true)
