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
# Gates (sdDraw layer 0 and paintRubble in src/03c_siegedef.js, src/03_battle.js).
const GATE_SHADOW := Color(0, 0, 0, 0.3)
const GATE_WOOD := Color("#5b3d22")
const GATE_EDGE := Color("#21160b")
const GATE_PLANK := Color(20 / 255.0, 12 / 255.0, 4 / 255.0, 0.7)
const GATE_IRON := Color("#3a3a3e")
const GATE_SEAM := Color("#14100c")
const GATE_CRACK := Color(15 / 255.0, 8 / 255.0, 2 / 255.0, 0.8)
const GATE_FLASH := Color("#ffd9a0")
const GATE_BAR_BACK := Color(0, 0, 0, 0.6)
const GATE_BAR_OK := Color("#d9a441")
const GATE_BAR_LOW := Color("#c4452f")
const RUBBLE_COLORS := [Color("#7a6f5e"), Color("#968a74")]
const RUBBLE_EDGE := Color("#2a2219")
const RUBBLE_STONES := 26

static func draw_under(canvas: CanvasItem, data: Dictionary, clock: float) -> void:
	if data.is_empty():
		return
	var wall_x: float = data.wall_x
	for gate in data.get("gates", []):
		_draw_gate(canvas, gate, wall_x, float(data.get("half_width", 22.0)))
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

## A shut gate: planks, two iron bands, cracks as it weakens, a flash on each blow and a strength bar. An opened
## gate shows its two leaves pushed back; a fallen one leaves rubble.
static func _draw_gate(canvas: CanvasItem, gate: Dictionary, wall_x: float, half_width: float) -> void:
	var gap: Vector2 = gate.gap
	var x0 := wall_x - half_width
	var width := half_width * 2.0
	var y0 := gap.x
	var y1 := gap.y
	if gate.dead:
		draw_rubble(canvas, Rect2(x0, y0, width, y1 - y0), int(y0))
		return
	if gate.open:
		var half := (y1 - y0) * 0.5
		var center := (y0 + y1) * 0.5
		for side in [-1.0, 1.0]:
			var leaf := Rect2(x0 - 4.0, center + side * half - (0.0 if side > 0.0 else 7.0), 12.0, 7.0)
			canvas.draw_rect(leaf, GATE_WOOD)
			canvas.draw_rect(leaf, GATE_EDGE, false, 2.0)
		return
	var damage := 1.0 - float(gate.hp) / maxf(1.0, float(gate.max))
	canvas.draw_rect(Rect2(x0 - 10.0, y0 + 8.0, width + 8.0, y1 - y0), GATE_SHADOW)
	canvas.draw_rect(Rect2(x0, y0, width, y1 - y0), GATE_WOOD)
	canvas.draw_rect(Rect2(x0, y0, width, y1 - y0), GATE_EDGE, false, 3.0)
	var plank := y0 + 12.0
	while plank < y1:
		canvas.draw_line(Vector2(x0, plank), Vector2(x0 + width, plank), GATE_PLANK, 1.4)
		plank += 12.0
	for band in [0.22, 0.78]:
		canvas.draw_rect(Rect2(x0 + width * band - 3.0, y0, 6.0, y1 - y0), GATE_IRON)
	canvas.draw_line(Vector2(x0, (y0 + y1) * 0.5), Vector2(x0 + width, (y0 + y1) * 0.5), GATE_SEAM, 2.0)
	for i in floori(damage * 8.0):
		var cy := y0 + 10.0 + float((i * 53) % maxi(1, int(y1 - y0 - 20.0)))
		var cx := x0 + 5.0 + float((i * 17) % maxi(1, int(width - 10.0)))
		canvas.draw_polyline(PackedVector2Array([Vector2(cx, cy), Vector2(cx + 9.0, cy + 12.0), Vector2(cx + 3.0, cy + 22.0)]), GATE_CRACK, 2.0)
	if float(gate.hit) > 0.0:
		var flash := GATE_FLASH
		flash.a = 0.3 * float(gate.hit) / 0.3
		canvas.draw_rect(Rect2(x0, y0, width, y1 - y0), flash)
	if damage > 0.02:
		var bar := minf(70.0, y1 - y0)
		var bar_x := wall_x - bar * 0.5
		var bar_y := y0 - 16.0
		canvas.draw_rect(Rect2(bar_x - 1.0, bar_y - 1.0, bar + 2.0, 7.0), GATE_BAR_BACK)
		canvas.draw_rect(Rect2(bar_x, bar_y, bar * (1.0 - damage), 5.0), GATE_BAR_LOW if damage > 0.66 else GATE_BAR_OK)

## Rubble in a breach or where a gate stood (paintRubble): 26 stones, the same for the same opening.
static func draw_rubble(canvas: CanvasItem, opening: Rect2, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in RUBBLE_STONES:
		var y := opening.position.y + 18.0 + rng.randf() * (opening.size.y - 36.0)
		var x := opening.position.x - 6.0 + rng.randf() * (opening.size.x + 12.0)
		var r := 3.0 + rng.randf() * 6.0
		_ellipse(canvas, Vector2(x, y), Vector2(r, r * 0.75), RUBBLE_COLORS[0] if rng.randf() < 0.5 else RUBBLE_COLORS[1])
		_ellipse_outline(canvas, Vector2(x, y), Vector2(r, r * 0.75), RUBBLE_EDGE, 1.0)

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
