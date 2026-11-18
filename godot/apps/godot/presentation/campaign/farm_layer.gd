extends Node2D
## Fields and farms around settlements (drawFarms in src/05b_worldart.js): decoration only, same random sequence.
const Generator = preload("res://core/campaign/world/terrain_generator.gd")
const WorldNoise = preload("res://core/campaign/world/noise.gd")
const SettlementArt = preload("res://apps/godot/presentation/campaign/settlement_art.gd")
const Brush = preload("res://apps/godot/presentation/campaign/map_brush.gd")

const CROP := [["#ad935e", "#887242"], ["#c5ae69", "#9e8c4f"], ["#969a54", "#768044"], ["#a5a65b", "#85894d"], ["#af9566", "#907a4d"]]

var _fields: Array = []   # {x, y, ang, w, h, crop}
var _houses: Array = []   # {x, y}

func build(world: Generator, road: PackedByteArray, settles: Array) -> void:
	var rng := WorldNoise.Mulberry.new(world.seed_value + 7)
	var placed: Array = []
	var ok_at := func(x: float, y: float) -> bool:
		if x < 30 or y < 30 or x > Generator.WW - 30 or y > Generator.WH - 30:
			return false
		var k := world.cell_of(x, y)
		return world.cells[k] == 1 and road[k] == 0 and world.bio[k] != 1 and world.bio[k] != 3
	for s in settles:
		if s.kind == "camp":
			continue
		var n: int = 7 + floori(rng.next() * 4) if s.kind == "village" else 6 + floori(rng.next() * 4) if s.kind == "town" else 3 + floori(rng.next() * 2)
		var r0 := 60.0 if s.kind == "village" else 88.0 if s.kind == "town" else 80.0
		var base := rng.next() * PI
		var farm: Array = []
		var t := 0
		while farm.size() < n and t < 90:
			t += 1
			var w := 34.0 + rng.next() * 22.0
			var h := 22.0 + rng.next() * 14.0
			var x := 0.0
			var y := 0.0
			var ang := 0.0
			if farm.is_empty() or rng.next() < 0.12:
				var a := rng.next() * TAU
				var d := r0 + rng.next() * 55.0
				x = s.x + cos(a) * d
				y = s.y + sin(a) * d * 0.8
				ang = base + (0.0 if rng.next() < 0.5 else PI / 2.0) + (rng.next() - 0.5) * 0.3
			else:
				var q: Dictionary = farm[floori(rng.next() * farm.size())]
				ang = q.ang
				var sg := 1.0 if rng.next() < 0.5 else -1.0
				var c := cos(ang)
				var sn := sin(ang)
				var lx := 0.0
				var ly := 0.0
				if rng.next() < 0.55:
					lx = sg * (q.w / 2.0 + w / 2.0 + 2.5)
					ly = (rng.next() - 0.5) * h * 0.5
				else:
					lx = (rng.next() - 0.5) * w * 0.5
					ly = sg * (q.h / 2.0 + h / 2.0 + 2.5)
				x = q.x + lx * c - ly * sn
				y = q.y + lx * sn + ly * c
			var corners := _corners(x, y, ang, w, h)
			var bad: bool = not ok_at.call(x, y)
			for p in corners:
				if not ok_at.call(p.x, p.y):
					bad = true
			if bad or sqrt((s.x - x) * (s.x - x) + (s.y - y) * (s.y - y)) < r0 - 6.0:
				continue
			for o in settles:
				if o != s and sqrt((o.x - x) * (o.x - x) + (o.y - y) * (o.y - y)) < 80.0:
					bad = true
					break
			if bad:
				continue
			for o in placed:
				if sqrt((o.x - x) * (o.x - x) + (o.y - y) * (o.y - y)) < 90.0 and _overlap(o.corners, corners):
					bad = true
					break
			if bad:
				continue
			var field := {"x": x, "y": y, "ang": ang, "w": w, "h": h, "corners": corners, "crop": floori(rng.next() * CROP.size())}
			farm.append(field)
			placed.append(field)
			_fields.append(field)
		if s.kind == "village" and not farm.is_empty():
			var q: Dictionary = farm[0]
			var hx: float = q.x + cos(q.ang + 1.57) * (q.h / 2.0 + 11.0)
			var hy: float = q.y + sin(q.ang + 1.57) * (q.h / 2.0 + 11.0)
			if ok_at.call(hx, hy):
				_houses.append({"x": hx, "y": hy})
	queue_redraw()

static func _corners(x: float, y: float, ang: float, w: float, h: float) -> Array:
	var c := cos(ang)
	var sn := sin(ang)
	var out: Array = []
	for q in [[-w / 2, -h / 2], [w / 2, -h / 2], [w / 2, h / 2], [-w / 2, h / 2]]:
		out.append(Vector2(x + q[0] * c - q[1] * sn, y + q[0] * sn + q[1] * c))
	return out

static func _overlap(a: Array, b: Array) -> bool:
	for poly in [a, b]:
		for i in 2:
			var ex: float = poly[i + 1].x - poly[i].x
			var ey: float = poly[i + 1].y - poly[i].y
			var pa := _project(a, ex, ey)
			var pb := _project(b, ex, ey)
			if pa[1] < pb[0] + 1.5 or pb[1] < pa[0] + 1.5:
				return false
	return true

static func _project(corners: Array, ex: float, ey: float) -> Array:
	var lo := 1e9
	var hi := -1e9
	for q in corners:
		var d: float = q.x * ey - q.y * ex
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return [lo, hi]

func _draw() -> void:
	for f in _fields:
		var crop: Array = CROP[f.crop]
		draw_set_transform(Vector2(f.x, f.y), f.ang, Vector2.ONE)
		var w: float = f.w * 0.91
		var h: float = f.h * 0.91
		var plot := PackedVector2Array([Vector2(-w * 0.5, -h * 0.42), Vector2(w * 0.39, -h * 0.5), Vector2(w * 0.5, h * 0.36), Vector2(w * 0.31, h * 0.47), Vector2(-w * 0.46, h * 0.5)])
		draw_colored_polygon(plot, Color(crop[0]))
		var furrow := Color(crop[1])
		furrow.a = 0.42
		var yy := -h * 0.35
		while yy < h * 0.34:
			draw_line(Vector2(-w * 0.42, yy), Vector2(w * 0.36, yy - 0.6), furrow, 1.0, true)
			yy += 3.4
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for hs in _houses:
		SettlementArt.house(self, hs.x + 0.0, hs.y + 0.0, 16, 11, Color("#cdbd96"), Color("#9b7d42"))
		Brush.fill_stroke(self, Brush.ellipse(hs.x + 14, hs.y + 2, 5, 4, 10), Color("#c9a94a"), 1.0)
