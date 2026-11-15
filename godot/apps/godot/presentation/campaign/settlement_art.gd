extends RefCounted
## Houses, towers and whole settlement pictures: house(), tower(), settleSprite() in src/05b_worldart.js.
## All functions draw onto a CanvasItem; the caller sets the transform (identity on the map, scaled in the sheet).
const Brush = preload("res://apps/godot/presentation/campaign/map_brush.gd")

const CULTURE_COLORS := {
	"nord": ["#9b8d78", "#5a3a24"], "emp": ["#cfc2a2", "#a8462f"], "khan": ["#c9b48a", "#2b7568"], "kin": ["#d3c7ac", "#3f5f9f"],
	"emi": ["#e3d2a6", "#b5512a"], "dom": ["#bfb08c", "#4a5a2e"], "pact": ["#d9cfb4", "#8f2b2b"],
}
const DEFAULT_COLORS := ["#c9b48a", "#2b7568"]
const CULTURES := ["nord", "emp", "khan", "kin", "emi", "dom", "pact", "other"]
## Settlement sprite size and the point that stands on the ground.
const SPRITE_SIZE := Vector2(170, 150)
const ANCHOR := Vector2(85, 120)

static func _rect(item: CanvasItem, x: float, y: float, w: float, h: float, fill: Color, line := 0.0) -> void:
	item.draw_rect(Rect2(x, y, w, h), fill)
	if line > 0.0:
		Brush.stroke_rect(item, x, y, w, h, Brush.OUTLINE, line)

static func house(item: CanvasItem, x: float, y: float, w: float, h: float, wall: Color, roof: Color) -> void:
	item.draw_colored_polygon(Brush.ellipse(x + w * 0.55, y + 1, w * 0.6, 3.5, 12), Color(0, 0, 0, 0.2))
	_rect(item, x - w / 2, y - h, w, h, wall)
	_rect(item, x, y - h, w / 2, h, Color(0, 0, 0, 0.2))
	for i in range(1, 4):
		item.draw_line(Vector2(x - w / 2, y - h * i / 4.0), Vector2(x + w / 2, y - h * i / 4.0), Color(0, 0, 0, 0.18), 0.7, true)
	Brush.stroke_rect(item, x - w / 2, y - h, w, h, Brush.OUTLINE, 1.4)
	var ty := y - h - w * 0.62
	Brush.fill_stroke(item, Brush.poly([x - w / 2 - 3, y - h, x, ty, x + w / 2 + 3, y - h]), roof, 1.4)
	item.draw_colored_polygon(PackedVector2Array([Vector2(x, ty), Vector2(x + w / 2 + 3, y - h), Vector2(x + 1, y - h)]), Color(0, 0, 0, 0.28))
	for i in range(1, 3):
		var k := i / 3.0
		var yy := ty + (y - h - ty) * k
		var d := (w / 2 + 3) * k
		item.draw_line(Vector2(x - d, yy), Vector2(x + d, yy), Color(0, 0, 0, 0.3), 0.7, true)
	item.draw_colored_polygon(PackedVector2Array([Vector2(x, ty), Vector2(x - w / 2 - 3, y - h), Vector2(x - w / 2 + 1, y - h), Vector2(x, ty + 2)]), Color(1, 1, 1, 0.18))
	_rect(item, x - 2.5, y - h * 0.55, 5, h * 0.55, Color("#2a1d12"))
	if w > 18:
		_rect(item, x - w * 0.36, y - h * 0.78, 3, 3.4, Color("#f0c868"), 0.8)
		_rect(item, x + w * 0.22, y - h * 0.78, 3, 3.4, Color("#f0c868"), 0.8)
	_rect(item, x + w * 0.22, ty + (y - h - ty) * 0.35, 3.4, 7, Color("#4a4036"), 0.8)

static func tower(item: CanvasItem, x: float, y: float, w: float, h: float, col: Color, cap = null) -> void:
	_rect(item, x - w / 2, y - h, w, h, col, 1.5)
	_rect(item, x, y - h, w / 2, h, Color(0, 0, 0, 0.22))
	var k := 1
	while k < h / 7.0:
		item.draw_line(Vector2(x - w / 2, y - k * 7), Vector2(x + w / 2, y - k * 7), Color(0, 0, 0, 0.2), 0.7, true)
		k += 1
	if h > 30:
		_rect(item, x - 1.2, y - h * 0.6, 2.4, 7, Color("#1a130c"))
	for i in 3:
		_rect(item, x - w / 2 + i * w / 3 - 1, y - h - 4, w / 3 - 1, 4, col, 1.5)
	if cap != null:
		Brush.fill_stroke(item, Brush.poly([x - w / 2 - 2, y - h - 4, x, y - h - 4 - w * 0.9, x + w / 2 + 2, y - h - 4]), cap, 1.4)

static func draw_settlement(item: CanvasItem, kind: String, culture: String, cx: float, cy: float) -> void:
	item.draw_colored_polygon(Brush.ellipse(cx + 4, cy + 4, 70, 18, 20), Color(0, 0, 0, 0.28))
	var palette: Array = CULTURE_COLORS.get(culture, DEFAULT_COLORS)
	var wall := Color(palette[0])
	var roof := Color(palette[1])
	match kind:
		"town":
			Brush.fill_stroke(item, Brush.ellipse(cx, cy - 8, 66, 22, 28), Color("#8f8878"), 2.0)
			Brush.fill_stroke(item, Brush.ellipse(cx, cy - 18, 66, 22, 28), Color("#b3ab99"), 2.0)
			house(item, cx - 36, cy - 14, 26, 18, wall, roof)
			house(item, cx + 34, cy - 12, 28, 20, wall, roof)
			house(item, cx - 8, cy - 6, 30, 22, wall, roof)
			house(item, cx + 6, cy - 30, 26, 22, wall, roof)
			house(item, cx - 28, cy - 34, 22, 16, wall, roof)
			tower(item, cx + 4, cy - 38, 22, 44, Color("#b5ad9a"), roof)
			tower(item, cx - 64, cy - 12, 12, 22, Color("#a39b88"))
			tower(item, cx + 62, cy - 12, 12, 22, Color("#a39b88"))
		"castle":
			tower(item, cx - 40, cy - 4, 22, 44, Color("#8f897b"), roof)
			tower(item, cx + 40, cy - 4, 22, 44, Color("#8f897b"), roof)
			_rect(item, cx - 40, cy - 38, 80, 34, Color("#a49d8c"), 1.6)
			for i in 6:
				_rect(item, cx - 38 + i * 13.5, cy - 43, 8, 6, Color("#a49d8c"), 1.6)
			var gate := Brush.quad(Vector2(cx - 9, cy - 22), Vector2(cx, cy - 32), Vector2(cx + 9, cy - 22), 8)
			var gate_pts := PackedVector2Array([Vector2(cx - 9, cy - 4)])
			gate_pts.append_array(gate)
			gate_pts.append(Vector2(cx + 9, cy - 4))
			Brush.fill_stroke(item, gate_pts, Color("#2a1d12"), 1.4)
			tower(item, cx, cy - 36, 28, 38, Color("#b0a994"), roof)
			for px in [cx - 40, cx + 40]:
				item.draw_line(Vector2(px - 8, cy - 47), Vector2(px - 8, cy - 25), Color("#ece0ba"), 1.0, true)
		"village":
			house(item, cx - 28, cy - 6, 24, 15, wall, Color("#a98a4a"))
			house(item, cx + 22, cy - 2, 26, 16, wall, Color("#a98a4a"))
			house(item, cx - 2, cy - 22, 22, 14, wall, Color("#9b7d42"))
			for i in 2:
				Brush.fill_stroke(item, Brush.ellipse(cx + 52 - i * 18, cy + 4 + i * 4 - 5, 8, 7, 14), Color("#cfb45a"), 1.2)
			var fence := Color("#4d3a22")
			for i in 6:
				item.draw_line(Vector2(cx - 62 + i * 8, cy + 6), Vector2(cx - 62 + i * 8, cy - 4), fence, 1.6, true)
			item.draw_line(Vector2(cx - 62, cy - 1), Vector2(cx - 18, cy - 1), fence, 1.6, true)
		_:
			for t in [[-28, -4, 1.0], [24, -8, 1.1], [-2, -20, 0.9]]:
				var x: float = cx + t[0]
				var y: float = cy + t[1]
				var sc: float = t[2]
				Brush.fill_stroke(item, Brush.poly([x - 20 * sc, y, x, y - 32 * sc, x + 20 * sc, y]), Color("#3d352b"), 1.5)
				Brush.fill_stroke(item, Brush.poly([x, y - 32 * sc, x + 20 * sc, y, x + 4 * sc, y]), Color("#2a231b"), 0.0)
				Brush.fill_stroke(item, Brush.poly([x - 5 * sc, y, x, y - 14 * sc, x + 5 * sc, y]), Color("#120d08"), 1.0)
			for i in 4:
				var x := cx - 48 + i * 30
				item.draw_line(Vector2(x, cy + 12), Vector2(x, cy - 6), Color("#4d3a22"), 2.2, true)
				Brush.fill_stroke(item, Brush.ellipse(x, cy - 9, 4.4, 4.6, 10), Color("#d6cfbc"), 1.0)
			Brush.fill_stroke(item, Brush.ellipse(cx + 36, cy + 10, 5, 3, 10), Color("#4a4034"), 1.0)
			item.draw_colored_polygon(PackedVector2Array([Vector2(cx + 33, cy + 9), Vector2(cx + 36, cy), Vector2(cx + 39, cy + 9)]), Color("#ff9a2a"))
