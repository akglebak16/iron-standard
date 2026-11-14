extends RefCounted
## Draws src/03c_siegedef.js sdDraw(): cauldrons and burning oil under the figures, falling stones above them.
const CAULDRON_SHADOW := Color(0, 0, 0, 0.3)
const CAULDRON_FULL := Color("#2b2824")
const CAULDRON_EMPTY := Color("#4a4640")
const CAULDRON_EDGE := Color("#14100c")
const OIL_HOT := Color("#d9822b")
const OIL_COLD := Color("#6d6252")
const EMBER := Color("#ffd26a")
const BURN := Color("#c4551a")
const POUR := Color("#e08a2c")
const FLAME := Color("#ff9a2e")
const STONE := Color("#7c7364")
const STONE_EDGE := Color("#2a2219")
const LANDING_RING := Color("#e2503c")
const SHADOW := Color(0, 0, 0, 0.3)
const CAULDRON_OFFSET := Vector2(6, -12)
const FLAMES := 14
const STONE_ARC_HEIGHT := 110.0
const STONE_RADIUS := 8.0
const LANDING_RADIUS := 52.0
const SEGMENTS := 20

static func draw_under(canvas: CanvasItem, data: Dictionary, clock: float) -> void:
	if data.is_empty():
		return
	var wall_x: float = data.wall_x
	for cauldron in data.cauldrons:
		var at := Vector2(wall_x, cauldron.gap.x) + CAULDRON_OFFSET
		_ellipse(canvas, at + Vector2(3, 8), Vector2(15, 7), CAULDRON_SHADOW)
		_ellipse(canvas, at, Vector2(13, 11), CAULDRON_FULL if cauldron.charged else CAULDRON_EMPTY)
		_ellipse_outline(canvas, at, Vector2(13, 11), CAULDRON_EDGE, 2.0)
		_ellipse(canvas, at + Vector2(0, -3), Vector2(9, 5), OIL_HOT if cauldron.charged else OIL_COLD)
		if cauldron.charged:
			var glow := EMBER
			glow.a = 0.6 + 0.3 * sin(clock * 8.0 + at.y)
			_ellipse(canvas, at + Vector2(0, 10), Vector2(5, 3), glow)
	for fire in data.fires:
		var life := clampf((fire.duration - fire.time) / 2.0, 0.0, 1.0)
		var pour := clampf(1.0 - fire.time / 0.9, 0.0, 1.0)
		var burn := BURN
		burn.a = life * 0.45
		_ellipse(canvas, fire.center, fire.half_size, burn)
		if pour > 0.0:
			var stream := POUR
			stream.a = pour
			canvas.draw_line(fire.pour_from, fire.center + Vector2(10, -fire.half_size.y * 0.4), stream, 5.0, true)
		for i in FLAMES:
			var base: Vector2 = fire.center + Vector2(sin(i * 7.1) * fire.half_size.x * 0.8, cos(i * 3.3) * fire.half_size.y * 0.8)
			var height := 15.0 + 8.0 * sin(clock * 9.0 + i * 1.7)
			var color := FLAME if i % 3 else EMBER
			color.a = life * 0.85
			var tip := base + Vector2(sin(clock * 7.0 + i) * 3.0, -height)
			canvas.draw_colored_polygon(PackedVector2Array([base + Vector2(-6, 0), base + Vector2(-3, -height * 0.6), tip, base + Vector2(3, -height * 0.5), base + Vector2(6, 0)]), color)

static func draw_over(canvas: CanvasItem, data: Dictionary) -> void:
	if data.is_empty():
		return
	for stone in data.stones:
		var p: float = stone.progress
		var ground: Vector2 = stone.origin.lerp(stone.impact, p)
		var air := ground - Vector2(0, sin(p * PI) * STONE_ARC_HEIGHT)
		var ring := LANDING_RING
		ring.a = 0.35 + 0.3 * p
		var radius := LANDING_RADIUS * (0.5 + 0.5 * p)
		_ellipse_outline(canvas, stone.impact, Vector2(radius, radius * 0.45), ring, 2.0)
		_ellipse(canvas, ground + Vector2(0, 4), Vector2(8, 4), SHADOW)
		canvas.draw_circle(air, STONE_RADIUS, STONE, true, -1.0, true)
		canvas.draw_circle(air, STONE_RADIUS, STONE_EDGE, false, 1.6, true)

static func _ellipse(canvas: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	canvas.draw_colored_polygon(_points(center, radii), color)

static func _ellipse_outline(canvas: CanvasItem, center: Vector2, radii: Vector2, color: Color, width: float) -> void:
	var points := _points(center, radii)
	points.append(points[0])
	canvas.draw_polyline(points, color, width, true)

static func _points(center: Vector2, radii: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in SEGMENTS:
		points.append(center + Vector2.from_angle(TAU * i / SEGMENTS) * radii)
	return points
