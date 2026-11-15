extends RefCounted
## Coats of arms and banners: emblem() and drawBanner() from src/02_art.js. Call with an identity canvas transform.
const Brush = preload("res://apps/godot/visuals/shape_brush.gd")

static func _arc(cx: float, cy: float, r: float, a0: float, a1: float, steps := 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps)
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return pts

static func _bezier(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, steps := 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		pts.append(p0 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + p1 * t * t * t)
	return pts

static func draw_emblem(item: CanvasItem, kind: String, x: float, y: float, s: float, col: Color) -> void:
	item.draw_set_transform(Vector2(x, y), 0.0, Vector2.ONE)
	match kind:
		"star":
			for i in 4:
				var a := i * PI / 4.0
				item.draw_line(Vector2(cos(a), sin(a)) * s, -Vector2(cos(a), sin(a)) * s, col, s * 0.16, true)
			item.draw_colored_polygon(Brush.ellipse(0, 0, s * 0.28, s * 0.28, 12), col)
		"sun":
			item.draw_colored_polygon(Brush.ellipse(0, 0, s * 0.5, s * 0.5, 16), col)
			for i in 8:
				var a := i * TAU / 8.0
				item.draw_line(Vector2(cos(a), sin(a)) * s * 0.68, Vector2(cos(a), sin(a)) * s, col, s * 0.16, true)
		"moon":
			# crescent as a thick arc (a filled crescent polygon does not triangulate reliably)
			item.draw_polyline(_arc(s * 0.1, 0, s * 0.58, 0.7, TAU - 0.7, 20), col, s * 0.5, true)
			item.draw_colored_polygon(Brush.ellipse(s * 0.5, 0, s * 0.2, s * 0.2, 10), col)
		"skull":
			item.draw_colored_polygon(Brush.ellipse(0, -s * 0.15, s * 0.72, s * 0.68, 16), col)
			item.draw_rect(Rect2(-s * 0.4, s * 0.25, s * 0.8, s * 0.55), col)
			var dark := Color("#17110c")
			item.draw_colored_polygon(Brush.ellipse(-s * 0.28, -s * 0.12, s * 0.2, s * 0.22, 10), dark)
			item.draw_colored_polygon(Brush.ellipse(s * 0.28, -s * 0.12, s * 0.2, s * 0.22, 10), dark)
			item.draw_colored_polygon(PackedVector2Array([Vector2(0, s * 0.12), Vector2(-s * 0.1, s * 0.34), Vector2(s * 0.1, s * 0.34)]), dark)
			for i in range(-1, 2):
				item.draw_rect(Rect2(i * s * 0.22 - s * 0.03, s * 0.5, s * 0.06, s * 0.3), dark)
		"lily":
			var petal := _bezier(Vector2(0, -s), Vector2(s * 0.5, -s * 0.45), Vector2(s * 0.34, s * 0.1), Vector2(0, s * 0.18))
			petal.append_array(_bezier(Vector2(0, s * 0.18), Vector2(-s * 0.34, s * 0.1), Vector2(-s * 0.5, -s * 0.45), Vector2(0, -s)))
			item.draw_colored_polygon(petal, col)
			for d in [-1.0, 1.0]:
				var leaf := _bezier(Vector2(d * s * 0.12, s * 0.1), Vector2(d * s * 0.9, -s * 0.35), Vector2(d * s * 1.05, s * 0.35), Vector2(d * s * 0.5, s * 0.5))
				leaf.append_array(_bezier(Vector2(d * s * 0.5, s * 0.5), Vector2(d * s * 0.6, s * 0.2), Vector2(d * s * 0.3, s * 0.12), Vector2(d * s * 0.12, s * 0.1)))
				item.draw_colored_polygon(leaf, col)
			item.draw_rect(Rect2(-s * 0.55, s * 0.3, s * 1.1, s * 0.16), col)
			item.draw_rect(Rect2(-s * 0.14, s * 0.3, s * 0.28, s * 0.55), col)
		"crown":
			item.draw_rect(Rect2(-s * 0.8, s * 0.35, s * 1.6, s * 0.3), col)
			item.draw_colored_polygon(PackedVector2Array([Vector2(-s * 0.8, s * 0.35), Vector2(-s * 0.8, -s * 0.45), Vector2(-s * 0.4, 0), Vector2(0, -s * 0.7), Vector2(s * 0.4, 0), Vector2(s * 0.8, -s * 0.45), Vector2(s * 0.8, s * 0.35)]), col)
		"oak":
			item.draw_rect(Rect2(-s * 0.14, s * 0.1, s * 0.28, s * 0.8), col)
			for q in [[-0.42, -0.1, 0.5], [0.42, -0.1, 0.5], [0.0, -0.5, 0.58], [0.0, 0.08, 0.52]]:
				item.draw_colored_polygon(Brush.ellipse(q[0] * s, q[1] * s, q[2] * s, q[2] * s, 14), col)
		"octa":
			for r in 2:
				var h := s * 0.66
				var pts := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
				var rot := r * PI / 4.0
				var out := PackedVector2Array()
				for p in pts:
					out.append(p.rotated(rot))
				item.draw_colored_polygon(out, col)
		_:
			item.draw_polyline(PackedVector2Array([Vector2(-s * 0.8, s * 0.1), Vector2(0, -s * 0.6), Vector2(s * 0.8, s * 0.1)]), col, s * 0.3, true)
			item.draw_polyline(PackedVector2Array([Vector2(-s * 0.8, s * 0.75), Vector2(0, s * 0.05), Vector2(s * 0.8, s * 0.75)]), col, s * 0.3, true)
	item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Pole from (x, y) upward, flag with the emblem.
static func draw_banner(item: CanvasItem, x: float, y: float, look: Dictionary, s: float, battle_time := -1.0) -> void:
	var top := Vector2(x, y - s * 2.3)
	item.draw_line(Vector2(x, y), top, Brush.OUTLINE, s * 0.2, true)
	item.draw_line(Vector2(x, y), top, Color("#8a6a40"), s * 0.1, true)
	var flutter := sin(battle_time * 3.0 + x * 0.03) * s * 0.08 if battle_time >= 0.0 else 0.0
	var flag := PackedVector2Array([Vector2(x, y - s * 2.25), Vector2(x + s * 1.3, y - s * 2.15 + flutter), Vector2(x + s * 1.05, y - s * 1.65), Vector2(x + s * 1.3, y - s * 1.15 + flutter), Vector2(x, y - s * 1.05)])
	item.draw_colored_polygon(flag, Color(look.c1))
	var closed := flag.duplicate()
	closed.append(flag[0])
	item.draw_polyline(closed, Brush.OUTLINE, maxf(1.0, s * 0.08), true)
	draw_emblem(item, look.emblem, x + s * 0.52, y - s * 1.65, s * 0.3, Color(look.c2))
