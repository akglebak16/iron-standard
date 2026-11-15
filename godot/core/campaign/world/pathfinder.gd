extends RefCounted
## Port of cellCost / nearestPass / losClear / findPath (src/05_world.js): A* over the 20 px grid.
## `road` marks cells covered by roads (cheaper to walk); the road generator fills it.
const Generator = preload("res://core/campaign/world/terrain_generator.gd")
const Heap = preload("res://core/campaign/world/heap.gd")
const GW := Generator.GW
const GH := Generator.GH
const GC := Generator.GC
const TCOST := [0.0, 1.0, 1.75, 1.5, 0.0]

var world: Generator
var road := PackedByteArray()
var _g := PackedFloat32Array()
var _prev := PackedInt32Array()
var _closed := PackedByteArray()

func _init(terrain: Generator) -> void:
	world = terrain
	road.resize(GW * GH)
	_g.resize(GW * GH)
	_prev.resize(GW * GH)
	_closed.resize(GW * GH)

func terr_at(x: float, y: float) -> int:
	return world.cells[world.cell_of(x, y)]

func passable_type(t: int) -> bool:
	return t >= 1 and t <= 3

func cell_cost(k: int) -> float:
	var t: int = world.cells[k]
	if not passable_type(t):
		return 0.0
	var c: float = TCOST[t]
	if world.bio[k] == 1:
		c *= 1.25
	elif world.bio[k] == 3:
		c *= 1.1
	if road[k] != 0:
		c *= 0.55
	return c

func nearest_pass(x: float, y: float) -> Vector2i:
	var ci := clampi(floori(x / GC), 0, GW - 1)
	var cj := clampi(floori(y / GC), 0, GH - 1)
	if passable_type(world.cells[cj * GW + ci]):
		return Vector2i(ci, cj)
	for r in range(1, 40):
		for j in range(cj - r, cj + r + 1):
			for i in range(ci - r, ci + r + 1):
				if i < 0 or j < 0 or i >= GW or j >= GH:
					continue
				if maxi(absi(i - ci), absi(j - cj)) != r:
					continue
				if passable_type(world.cells[j * GW + i]) and world.comp[j * GW + i] == world.main_comp:
					return Vector2i(i, j)
	return Vector2i(ci, cj)

func los_clear(x0: float, y0: float, x1: float, y1: float) -> bool:
	var d := sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
	var n := ceili(d / (GC * 0.25))  # rivers are always on in the Europe map
	for i in range(1, n):
		var t := float(i) / n
		if not passable_type(terr_at(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)):
			return false
	return true

## Returns an Array of Vector2 points, or null when there is no way. `raw` keeps every cell centre (used for roads).
func find_path(sx: float, sy: float, tx: float, ty: float, raw := false):
	var a := nearest_pass(sx, sy)
	var b := nearest_pass(tx, ty)
	var s := a.y * GW + a.x
	var e := b.y * GW + b.x
	if s == e:
		return [Vector2(tx, ty)]
	_g.fill(1e9)
	_closed.fill(0)
	var h: Array = []
	_g[s] = 0.0
	_prev[s] = -1
	Heap.push(h, 0.0, s)
	var found := false
	while not h.is_empty():
		var cur: int = Heap.pop(h)[1]
		if _closed[cur] != 0:
			continue
		_closed[cur] = 1
		if cur == e:
			found = true
			break
		var ci := cur % GW
		var cj := cur / GW
		for dj in range(-1, 2):
			for di in range(-1, 2):
				if di == 0 and dj == 0:
					continue
				var ni := ci + di
				var nj := cj + dj
				if ni < 0 or nj < 0 or ni >= GW or nj >= GH:
					continue
				var k := nj * GW + ni
				if _closed[k] != 0:
					continue
				var cc := cell_cost(k)
				if cc == 0.0:
					continue
				if di != 0 and dj != 0 and (cell_cost(cj * GW + ni) == 0.0 or cell_cost(nj * GW + ci) == 0.0):
					continue
				var g: float = _g[cur] + cc * (1.414 if di != 0 and dj != 0 else 1.0)
				if g < _g[k]:
					_g[k] = g
					_prev[k] = cur
					var dx := float(ni - b.x)
					var dy := float(nj - b.y)
					Heap.push(h, g + sqrt(dx * dx + dy * dy) * 0.55, k)
	if not found:
		return null
	var pts: Array = []
	var k := e
	while k >= 0:
		pts.append(Vector2((k % GW) * GC + GC / 2.0, (k / GW) * GC + GC / 2.0))
		k = _prev[k]
	pts.reverse()
	pts[0] = Vector2(sx, sy)
	pts[pts.size() - 1] = Vector2(tx, ty)
	if not passable_type(terr_at(tx, ty)):
		pts[pts.size() - 1] = pts[pts.size() - 2] if pts.size() >= 2 else pts[0]
	if raw:
		var kept: Array = []
		for i in range(1, pts.size()):
			if pts[i] != pts[i - 1]:
				kept.append(pts[i])
		return kept
	var out: Array = [pts[0]]
	var i := 0
	while i < pts.size() - 1:
		var j := pts.size() - 1
		while j > i + 1 and not los_clear(pts[i].x, pts[i].y, pts[j].x, pts[j].y):
			j -= 1
		out.append(pts[j])
		i = j
	out.pop_front()
	return out
