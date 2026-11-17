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
## Terrain part of cell_cost (0 = impassable). Cells and biomes never change after the terrain is generated, the roads do
## (the road generator writes `road` between searches), so only the road discount is applied at use.
var _base := PackedFloat64Array()
## Neighbours in the order the search has always visited them: (di, dj) for dj, di in -1..1 without the centre.
const NEIGHBOURS_DI := [-1, 0, 1, -1, 1, -1, 0, 1]
const NEIGHBOURS_DJ := [-1, -1, -1, 0, 0, 1, 1, 1]

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

func _ensure_base() -> void:
	if _base.size() == GW * GH:
		return
	_base.resize(GW * GH)
	for k in GW * GH:
		var t: int = world.cells[k]
		var c := 0.0
		if passable_type(t):
			c = TCOST[t]
			if world.bio[k] == 1:
				c *= 1.25
			elif world.bio[k] == 3:
				c *= 1.1
		_base[k] = c

func cell_cost(k: int) -> float:
	_ensure_base()
	var c: float = _base[k]
	if c != 0.0 and road[k] != 0:
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
	var cells := world.cells
	for i in range(1, n):
		var t := float(i) / n
		var x := x0 + (x1 - x0) * t
		var y := y0 + (y1 - y0) * t
		var c: int = cells[clampi(floori(y / GC), 0, GH - 1) * GW + clampi(floori(x / GC), 0, GW - 1)]
		if c < 1 or c > 3:
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
	_ensure_base()
	_g.fill(1e9)
	_closed.fill(0)
	# The binary heap of heap.gd (same swaps, so equal-cost ties break the same way) on two flat arrays: no [priority, cell] pair per push.
	var hp := PackedFloat64Array()
	var hv := PackedInt32Array()
	var hn := 1
	hp.append(0.0)
	hv.append(s)
	_g[s] = 0.0
	_prev[s] = -1
	var base := _base
	var roads := road
	var closed := _closed
	var found := false
	while hn > 0:
		var cur: int = hv[0]
		hn -= 1
		var last_p: float = hp[hn]
		var last_v: int = hv[hn]
		hp.resize(hn)
		hv.resize(hn)
		if hn > 0:
			hp[0] = last_p
			hv[0] = last_v
			var i := 0
			while true:
				var l := i * 2 + 1
				var r := l + 1
				var m := i
				if l < hn and hp[l] < hp[m]:
					m = l
				if r < hn and hp[r] < hp[m]:
					m = r
				if m == i:
					break
				var tp := hp[m]
				hp[m] = hp[i]
				hp[i] = tp
				var tv := hv[m]
				hv[m] = hv[i]
				hv[i] = tv
				i = m
		if closed[cur] != 0:
			continue
		closed[cur] = 1
		if cur == e:
			found = true
			break
		var ci := cur % GW
		var cj := cur / GW
		var g_cur: float = _g[cur]
		for n in 8:
			var di: int = NEIGHBOURS_DI[n]
			var dj: int = NEIGHBOURS_DJ[n]
			var ni := ci + di
			var nj := cj + dj
			if ni < 0 or nj < 0 or ni >= GW or nj >= GH:
				continue
			var k := nj * GW + ni
			if closed[k] != 0:
				continue
			var cc: float = base[k]
			if cc == 0.0:
				continue
			if roads[k] != 0:
				cc *= 0.55
			var diagonal := di != 0 and dj != 0
			if diagonal and (base[cj * GW + ni] == 0.0 or base[nj * GW + ci] == 0.0):
				continue
			var g: float = g_cur + cc * (1.414 if diagonal else 1.0)
			if g < _g[k]:
				_g[k] = g
				_prev[k] = cur
				var dx := float(ni - b.x)
				var dy := float(nj - b.y)
				var pri := g + sqrt(dx * dx + dy * dy) * 0.55
				hp.append(pri)
				hv.append(k)
				var i := hn
				hn += 1
				while i > 0:
					var p := (i - 1) >> 1
					if hp[p] <= hp[i]:
						break
					var tp := hp[p]
					hp[p] = hp[i]
					hp[i] = tp
					var tv := hv[p]
					hv[p] = hv[i]
					hv[i] = tv
					i = p
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

## Same search as find_path (keep the two in step: test_world_slicing compares them) that may rest between frames: with a slice budget (SliceBudget, optional) it gives the frame back when the
## budget is spent and goes on next frame, with scratch arrays of its own (other searches run meanwhile). Without it never suspends.
func find_path_co(sx: float, sy: float, tx: float, ty: float, raw := false, slicer = null):
	var a := nearest_pass(sx, sy)
	var b := nearest_pass(tx, ty)
	var s := a.y * GW + a.x
	var e := b.y * GW + b.x
	if s == e:
		return [Vector2(tx, ty)]
	_ensure_base()
	var sliced: bool = slicer != null and slicer.active
	var gs := _g
	var closed := _closed
	var prevs := _prev
	if sliced:
		gs = PackedFloat32Array()
		gs.resize(GW * GH)
		closed = PackedByteArray()
		closed.resize(GW * GH)
		prevs = PackedInt32Array()
		prevs.resize(GW * GH)
	gs.fill(1e9)
	closed.fill(0)
	var spins := 0
	# The binary heap of heap.gd (same swaps, so equal-cost ties break the same way) on two flat arrays: no [priority, cell] pair per push.
	var hp := PackedFloat64Array()
	var hv := PackedInt32Array()
	var hn := 1
	hp.append(0.0)
	hv.append(s)
	gs[s] = 0.0
	prevs[s] = -1
	var base := _base
	var roads := road
	var found := false
	while hn > 0:
		spins += 1
		if sliced and (spins & 15) == 0 and slicer.due():
			await slicer.next_frame()
		var cur: int = hv[0]
		hn -= 1
		var last_p: float = hp[hn]
		var last_v: int = hv[hn]
		hp.resize(hn)
		hv.resize(hn)
		if hn > 0:
			hp[0] = last_p
			hv[0] = last_v
			var i := 0
			while true:
				var l := i * 2 + 1
				var r := l + 1
				var m := i
				if l < hn and hp[l] < hp[m]:
					m = l
				if r < hn and hp[r] < hp[m]:
					m = r
				if m == i:
					break
				var tp := hp[m]
				hp[m] = hp[i]
				hp[i] = tp
				var tv := hv[m]
				hv[m] = hv[i]
				hv[i] = tv
				i = m
		if closed[cur] != 0:
			continue
		closed[cur] = 1
		if cur == e:
			found = true
			break
		var ci := cur % GW
		var cj := cur / GW
		var g_cur: float = gs[cur]
		for n in 8:
			var di: int = NEIGHBOURS_DI[n]
			var dj: int = NEIGHBOURS_DJ[n]
			var ni := ci + di
			var nj := cj + dj
			if ni < 0 or nj < 0 or ni >= GW or nj >= GH:
				continue
			var k := nj * GW + ni
			if closed[k] != 0:
				continue
			var cc: float = base[k]
			if cc == 0.0:
				continue
			if roads[k] != 0:
				cc *= 0.55
			var diagonal := di != 0 and dj != 0
			if diagonal and (base[cj * GW + ni] == 0.0 or base[nj * GW + ci] == 0.0):
				continue
			var g: float = g_cur + cc * (1.414 if diagonal else 1.0)
			if g < gs[k]:
				gs[k] = g
				prevs[k] = cur
				var dx := float(ni - b.x)
				var dy := float(nj - b.y)
				var pri := g + sqrt(dx * dx + dy * dy) * 0.55
				hp.append(pri)
				hv.append(k)
				var i := hn
				hn += 1
				while i > 0:
					var p := (i - 1) >> 1
					if hp[p] <= hp[i]:
						break
					var tp := hp[p]
					hp[p] = hp[i]
					hp[i] = tp
					var tv := hv[p]
					hv[p] = hv[i]
					hv[i] = tv
					i = p
	if not found:
		return null
	var pts: Array = []
	var k := e
	while k >= 0:
		pts.append(Vector2((k % GW) * GC + GC / 2.0, (k / GW) * GC + GC / 2.0))
		k = prevs[k]
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
