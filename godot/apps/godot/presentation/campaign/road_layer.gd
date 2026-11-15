extends Node2D
## Roads: roadCurve/curvePath/drawRoads from src/05b_worldart.js. The polyline is smoothed and bent by noise so it winds like a real road.
const Generator = preload("res://core/campaign/world/terrain_generator.gd")
const Brush = preload("res://apps/godot/presentation/campaign/map_brush.gd")

var _runs_small: Array = []
var _runs_big: Array = []

func build(world: Generator, roads: Array, settles: Array) -> void:
	var seen := {}
	for seg in roads:
		if seg.size() < 2:
			continue
		var a := _kind_at(seg[0], settles)
		var b := _kind_at(seg[seg.size() - 1], settles)
		var main := (a == "town" or a == "castle") and (b == "town" or b == "castle")
		var curve := _flatten(_road_curve(world, seg))
		# Shared stretches of different roads coincide: draw each piece once so semi-transparent strokes do not stack.
		var run := PackedVector2Array()
		for i in curve.size() - 1:
			var key := "%d,%d,%d,%d" % [roundi(curve[i].x * 2), roundi(curve[i].y * 2), roundi(curve[i + 1].x * 2), roundi(curve[i + 1].y * 2)]
			var rev := "%d,%d,%d,%d" % [roundi(curve[i + 1].x * 2), roundi(curve[i + 1].y * 2), roundi(curve[i].x * 2), roundi(curve[i].y * 2)]
			if seen.has(key) or seen.has(rev):
				if run.size() > 1:
					(_runs_big if main else _runs_small).append(run)
				run = PackedVector2Array()
				continue
			seen[key] = true
			if run.is_empty():
				run.append(curve[i])
			run.append(curve[i + 1])
		if run.size() > 1:
			(_runs_big if main else _runs_small).append(run)
	queue_redraw()

func _kind_at(p: Vector2, settles: Array) -> String:
	for s in settles:
		if sqrt((s.x - p.x) * (s.x - p.x) + (s.y - p.y) * (s.y - p.y)) < 40.0:
			return s.kind
	return "none"

func _road_curve(world: Generator, seg: Array) -> Array:
	var pts: Array = []   # [x, y, pin]
	for i in seg.size():
		var q: Vector2 = seg[i]
		if i > 0:
			var a: Vector2 = seg[i - 1]
			var n := ceili(a.distance_to(q) / 16.0)
			for k in range(1, n):
				var p := a.lerp(q, float(k) / n)
				pts.append([p.x, p.y, false])
		pts.append([q.x, q.y, i == 0 or i == seg.size() - 1 or world.bridge[world.cell_of(q.x, q.y)] == 1])
	var n := pts.size()
	if n < 3:
		return pts
	var acc := PackedFloat64Array()
	acc.resize(n)
	for i in range(1, n):
		acc[i] = acc[i - 1] + sqrt(pow(pts[i][0] - pts[i - 1][0], 2) + pow(pts[i][1] - pts[i - 1][1], 2))
	var wt := PackedFloat64Array()
	wt.resize(n)
	for i in n:
		var bd := 1e9
		for b in world.bridges:
			bd = minf(bd, sqrt(pow(b.x - pts[i][0], 2) + pow(b.y - pts[i][1], 2)))
		wt[i] = minf(clampf((bd - 14.0) / 46.0, 0.0, 1.0), clampf((minf(acc[i], acc[n - 1] - acc[i]) - 10.0) / 50.0, 0.0, 1.0))
	for it in 3:
		var q: Array = []
		for p in pts:
			q.append([p[0], p[1]])
		for i in range(1, n - 1):
			if pts[i][2]:
				continue
			pts[i][0] = lerpf(q[i][0], (q[i - 1][0] + 2.0 * q[i][0] + q[i + 1][0]) / 4.0, wt[i])
			pts[i][1] = lerpf(q[i][1], (q[i - 1][1] + 2.0 * q[i][1] + q[i + 1][1]) / 4.0, wt[i])
	for i in n:
		if pts[i][2]:
			continue
		pts[i][0] += (world.detail_noise(pts[i][0] / 90.0 + 3.0, pts[i][1] / 90.0) - 0.5) * 15.0 * wt[i]
		pts[i][1] += (world.detail_noise(pts[i][0] / 90.0, pts[i][1] / 90.0 + 7.0) - 0.5) * 15.0 * wt[i]
	return pts

# Quadratic pieces through the midpoints, flattened to a polyline.
func _flatten(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	out.append(Vector2(pts[0][0], pts[0][1]))
	if n < 3:
		for i in range(1, n):
			out.append(Vector2(pts[i][0], pts[i][1]))
		return out
	var cur := Vector2(pts[0][0], pts[0][1])
	for i in range(1, n - 1):
		var c := Vector2(pts[i][0], pts[i][1])
		var next := Vector2(pts[i + 1][0], pts[i + 1][1])
		var mid := (c + next) / 2.0
		var curve := Brush.quad(cur, c, mid, 4)
		for k in range(1, curve.size()):
			out.append(curve[k])
		cur = mid
	out.append(Vector2(pts[n - 1][0], pts[n - 1][1]))
	return out

func _draw() -> void:
	var outline := Color(52 / 255.0, 36 / 255.0, 18 / 255.0, 0.5)
	var body := Color("#b8955f")
	var light := Color(224 / 255.0, 200 / 255.0, 150 / 255.0, 0.7)
	for pass_def in [[outline, 8.6, 11.0], [body, 5.4, 7.4], [light, 2.2, 3.2]]:
		for run in _runs_small:
			draw_polyline(run, pass_def[0], pass_def[1], true)
		for run in _runs_big:
			draw_polyline(run, pass_def[0], pass_def[2], true)
