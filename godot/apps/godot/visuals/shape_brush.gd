extends RefCounted
## Small drawing helpers shared by the world-map layers: the Godot counterparts of ell/poly/fs in src/02_art.js.
const OUTLINE := Color("#1b130c")

static func ellipse(cx: float, cy: float, rx: float, ry: float, segments := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts

static func poly(coords: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var i := 0
	while i < coords.size():
		pts.append(Vector2(coords[i], coords[i + 1]))
		i += 2
	return pts

## Fill, then outline (line width 0 = no outline), like fs(g, fill, lw).
static func fill_stroke(item: CanvasItem, pts: PackedVector2Array, fill: Color, line_width := 1.5) -> void:
	item.draw_colored_polygon(pts, fill)
	if line_width > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		item.draw_polyline(closed, OUTLINE, line_width, true)

static func fill_rect(item: CanvasItem, x: float, y: float, w: float, h: float, color: Color) -> void:
	item.draw_rect(Rect2(x, y, w, h), color)

static func stroke_rect(item: CanvasItem, x: float, y: float, w: float, h: float, color: Color, line_width: float) -> void:
	item.draw_polyline(poly([x, y, x + w, y, x + w, y + h, x, y + h, x, y]), color, line_width, true)

## Quadratic Bezier flattened to points (canvas quadraticCurveTo).
static func quad(p0: Vector2, c: Vector2, p1: Vector2, steps := 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(p0 * (1 - t) * (1 - t) + c * 2.0 * (1 - t) * t + p1 * t * t)
	return pts

static func soft_shadow_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(0.094, 0.09, 0.047, 0.34), Color(0.094, 0.09, 0.047, 0.19), Color(0.094, 0.09, 0.047, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 64
	return tex
