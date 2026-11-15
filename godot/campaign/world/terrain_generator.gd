extends RefCounted
## Port of genWorldV2 / genRivers (src/05_world.js): terrain of Europe on a 20 px grid.
## Cell types: 0 sea, 1 plain, 2 forest, 3 hills, 4 mountains, 5 river.
## Biomes: 0 grass, 1 snow, 2 steppe, 3 arid.
const WorldNoise = preload("res://campaign/world/noise.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const Heap = preload("res://campaign/world/heap.gd")

const WW := 5200
const WH := 3400
const GC := 20
const GW := 260
const GH := 170
const RES := 10
const LW := 520
const LH := 340
const BIOME_NAMES := ["grass", "snow", "steppe", "arid"]

var seed_value := 0
var cells := PackedByteArray()
var bio := PackedByteArray()
var comp := PackedInt32Array()
var main_comp := -1
var rivers: Array = []   # {w, p: [[x,y]...], c: [cell...]}
var bridges: Array = []  # {k, x, y, ax, w}
var bridge := PackedByteArray()

var _data: EuropeData
var _n_e: WorldNoise.ValueNoise
var _n_m: WorldNoise.ValueNoise
var _n_f: WorldNoise.ValueNoise
var _n_d: WorldNoise.ValueNoise
var _n_c: WorldNoise.ValueNoise
var _lsh := PackedFloat32Array()
var _lwd := PackedFloat32Array()
var _rid := PackedFloat32Array()
var _rid_pass := PackedFloat32Array()
var _carve := PackedByteArray()

func eu_x(lon: float) -> float:
	return (lon - float(_data.eu.lon0)) / (float(_data.eu.lon1) - float(_data.eu.lon0)) * WW
func eu_y(lat: float) -> float:
	return (float(_data.eu.lat1) - lat) / (float(_data.eu.lat1) - float(_data.eu.lat0)) * WH
func eu_lon(x: float) -> float:
	return float(_data.eu.lon0) + x / WW * (float(_data.eu.lon1) - float(_data.eu.lon0))
func eu_lat(y: float) -> float:
	return float(_data.eu.lat1) - y / WH * (float(_data.eu.lat1) - float(_data.eu.lat0))

func generate(seed_in: int, data: EuropeData, with_rivers := true) -> void:
	seed_value = seed_in
	_data = data
	_n_e = WorldNoise.ValueNoise.new(seed_in)
	_n_m = WorldNoise.ValueNoise.new((seed_in ^ 0x9e3779b9) & 0xFFFFFFFF)
	_n_f = WorldNoise.ValueNoise.new(seed_in + 77)
	_n_d = WorldNoise.ValueNoise.new(seed_in + 5)
	_n_c = WorldNoise.ValueNoise.new(seed_in + 31)
	var mask := PackedByteArray()
	mask.resize(LW * LH)
	for sh in _data.shapes:
		var pts := PackedFloat64Array()
		var i := 1
		while i < sh.size():
			pts.append(eu_x(float(sh[i])))
			pts.append(eu_y(float(sh[i + 1])))
			i += 2
		_poly_fill(mask, pts, int(sh[0]))
	var maskf := PackedFloat32Array()
	maskf.resize(LW * LH)
	for k in mask.size():
		maskf[k] = mask[k]
	_lsh = _box_blur(maskf, 2, 2)
	_lwd = _box_blur(maskf, 8, 2)
	_ridge_grid(WorldNoise.Mulberry.new(seed_in + 101))
	_carve.resize(GW * GH)
	cells.resize(GW * GH)
	bio.resize(GW * GH)
	for j in GH:
		for i in GW:
			var x := i * GC + GC / 2.0
			var y := j * GC + GC / 2.0
			cells[j * GW + i] = terrain_at(x, y)
			bio[j * GW + i] = biome_id(x, y)
	_cut_passes()
	bridge.resize(GW * GH)
	rivers = []
	bridges = []
	if with_rivers:
		_gen_rivers()
	var lab := _label_comps()
	comp = lab.comp
	main_comp = lab.main

# ---------- fields ----------
func _poly_fill(m: PackedByteArray, pts: PackedFloat64Array, v: int) -> void:
	var n := pts.size() / 2
	var y0 := 1e9
	var y1 := -1e9
	for i in range(1, pts.size(), 2):
		y0 = minf(y0, pts[i])
		y1 = maxf(y1, pts[i])
	for j in range(maxi(0, floori(y0 / RES) - 1), mini(LH - 1, ceili(y1 / RES) + 1) + 1):
		var y := (j + 0.5) * RES
		var xs: Array = []
		for i in n:
			var k := (i + 1) % n
			var ay := pts[i * 2 + 1]
			var by := pts[k * 2 + 1]
			if (ay <= y) != (by <= y):
				xs.append(pts[i * 2] + (y - ay) / (by - ay) * (pts[k * 2] - pts[i * 2]))
		xs.sort()
		var q := 0
		while q + 1 < xs.size():
			var i0 := maxi(0, ceili(xs[q] / RES - 0.5))
			var i1 := mini(LW - 1, floori(xs[q + 1] / RES - 0.5))
			for i in range(i0, i1 + 1):
				m[j * LW + i] = v
			q += 2

func _box_blur(src: PackedFloat32Array, r: int, passes: int) -> PackedFloat32Array:
	var a := src.duplicate()
	var b := PackedFloat32Array()
	b.resize(LW * LH)
	var k := 1.0 / (2 * r + 1)
	for p in passes:
		for j in LH:
			var o := j * LW
			var s := 0.0
			for i in range(-r, r + 1):
				s += a[o + clampi(i, 0, LW - 1)]
			for i in LW:
				b[o + i] = s * k
				s += a[o + mini(LW - 1, i + r + 1)] - a[o + maxi(0, i - r)]
		for i in LW:
			var s := 0.0
			for j in range(-r, r + 1):
				s += b[clampi(j, 0, LH - 1) * LW + i]
			for j in LH:
				a[j * LW + i] = s * k
				s += b[mini(LH - 1, j + r + 1) * LW + i] - b[maxi(0, j - r) * LW + i]
	return a

static func _dist_seg(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	var l := dx * dx + dy * dy
	var t := clampf(((px - ax) * dx + (py - ay) * dy) / l, 0.0, 1.0) if l != 0.0 else 0.0
	return sqrt((px - ax - dx * t) * (px - ax - dx * t) + (py - ay - dy * t) * (py - ay - dy * t))

func _ridge_grid(rng: WorldNoise.Mulberry) -> void:
	var n := LW * LH
	var R := PackedFloat32Array()
	var P := PackedFloat32Array()
	var T := PackedFloat32Array()
	var X := PackedFloat32Array()
	var Y := PackedFloat32Array()
	for arr in [R, P, T, X, Y]:
		arr.resize(n)
	for j in LH:
		for i in LW:
			var x := (i + 0.5) * RES
			var y := (j + 0.5) * RES
			X[j * LW + i] = x + (_n_f.value(x / 260.0, y / 260.0) - 0.5) * 110.0
			Y[j * LW + i] = y + (_n_d.value(x / 260.0 + 5.0, y / 260.0) - 0.5) * 110.0
	for rd in _data.ridges:
		var w := float(rd[0])
		var pts: Array = []
		var i := 1
		while i < rd.size():
			pts.append([eu_x(float(rd[i])), eu_y(float(rd[i + 1]))])
			i += 2
		T.fill(0.0)
		var total := 0.0
		var lens: Array = []
		for s in pts.size() - 1:
			lens.append(_hyp(pts[s + 1][0] - pts[s][0], pts[s + 1][1] - pts[s][1]))
			total += lens[s]
		for s in pts.size() - 1:
			var ax: float = pts[s][0]
			var ay: float = pts[s][1]
			var bx: float = pts[s + 1][0]
			var by: float = pts[s + 1][1]
			var pad := w * 2.6 + 60.0
			var i0 := maxi(0, floori((minf(ax, bx) - pad) / RES))
			var i1 := mini(LW - 1, ceili((maxf(ax, bx) + pad) / RES))
			var j0 := maxi(0, floori((minf(ay, by) - pad) / RES))
			var j1 := mini(LH - 1, ceili((maxf(ay, by) + pad) / RES))
			for j in range(j0, j1 + 1):
				for ii in range(i0, i1 + 1):
					var k := j * LW + ii
					var d := _dist_seg(X[k], Y[k], ax, ay, bx, by)
					var v := exp(-(d / w) * (d / w))
					if v > T[k]:
						T[k] = v
		if total >= 200.0:
			var cnt := ceili(total / (200.0 + w * 1.2))
			var ph := 22.0 + w * 0.1
			for q in cnt:
				var at: float = total * (q + 0.5 + (rng.next() - 0.5) * 0.5) / cnt
				var s := 0
				while s < lens.size() - 1 and at > lens[s]:
					at -= lens[s]
					s += 1
				var t: float = at / lens[s] if lens[s] != 0.0 else 0.0
				var px: float = pts[s][0] + (pts[s + 1][0] - pts[s][0]) * t
				var py: float = pts[s][1] + (pts[s + 1][1] - pts[s][1]) * t
				var i0 := maxi(0, floori((px - ph * 2) / RES))
				var i1 := mini(LW - 1, ceili((px + ph * 2) / RES))
				var j0 := maxi(0, floori((py - ph * 2) / RES))
				var j1 := mini(LH - 1, ceili((py + ph * 2) / RES))
				for j in range(j0, j1 + 1):
					for ii in range(i0, i1 + 1):
						var k := j * LW + ii
						var d := _hyp(X[k] - px, Y[k] - py)
						if d < ph * 1.4:
							var f := clampf((d - ph) / (ph * 0.4), 0.0, 1.0)
							T[k] *= f
							if 1 - f > P[k]:
								P[k] = 1 - f
		for k in n:
			if T[k] > R[k]:
				R[k] = T[k]
	_rid = R
	_rid_pass = P

static func _hyp(a: float, b: float) -> float:
	return sqrt(a * a + b * b)

func _bilin(F: PackedFloat32Array, x: float, y: float) -> float:
	var u := x / RES - 0.5
	var v := y / RES - 0.5
	var i := floori(u)
	var j := floori(v)
	var fx := u - i
	var fy := v - j
	var i0 := clampi(i, 0, LW - 1)
	var i1 := clampi(i + 1, 0, LW - 1)
	var j0 := clampi(j, 0, LH - 1)
	var j1 := clampi(j + 1, 0, LH - 1)
	return (F[j0 * LW + i0] * (1 - fx) + F[j0 * LW + i1] * fx) * (1 - fy) + (F[j1 * LW + i0] * (1 - fx) + F[j1 * LW + i1] * fx) * fy

func _kof(x: float, y: float) -> int:
	return clampi(floori(y / GC), 0, GH - 1) * GW + clampi(floori(x / GC), 0, GW - 1)

# ---------- point queries ----------
func biome_id(x: float, y: float) -> int:
	var lon0 := eu_lon(x)
	var lat := eu_lat(y)
	var w1 := _n_f.value(x / 200.0, y / 200.0) - 0.5
	var w2 := _n_f.value(x / 330.0 + 9.0, y / 330.0) - 0.5
	var lon := lon0 + w2 * 7.0
	if lat > 40.0 and _bilin(_rid, x, y) > 0.82 + w1 * 0.3:
		return 1
	if lat > 61.8 + w2 * 3.2:
		return 1
	var al := lat + w1 * 2.4
	if (al < 37.4 and lon > -10.0 and lon < 12.5) or al < 36.4 or (lon > -8.5 and lon < -0.2 and al < 38.4) or (lon > 49.0 and al < 43.5) or (lon > 34.0 and al < 37.6):
		return 3
	var ex := (lon - 42.0) / 16.0
	var ey := (lat - 48.2) / 5.2
	var hx := (lon - 20.0) / 2.6
	var hy := (lat - 47.0) / 1.3
	if ex * ex + ey * ey < 1.0 + w1 * 0.7 or hx * hx + hy * hy < 1.0 + w1:
		return 2
	return 0

func biome_name(x: float, y: float) -> String:
	return BIOME_NAMES[biome_id(x, y)]

func elevation(x: float, y: float) -> float:
	var ls := _bilin(_lsh, x, y)
	var lw := _bilin(_lwd, x, y)
	return 0.33 + (ls - 0.5) * 0.8 + (lw - 0.5) * 0.3 + (_n_e.value(x / 240.0, y / 240.0) - 0.5) * 0.2 + (_n_c.value(x / 60.0, y / 60.0) - 0.5) * 0.16

func terrain_at(x: float, y: float) -> int:
	return terrain_given(x, y, elevation(x, y))

## Same as terrain_at when the elevation at (x, y) is already known (painting needs both).
func terrain_given(x: float, y: float, e: float) -> int:
	if e < 0.33:
		return 0
	var m := _n_m.value(x / 230.0, y / 230.0)
	var r := _bilin(_rid, x, y)
	var mt := r * (0.55 + 0.9 * m)
	if mt > 0.66 or (m > 0.78 and _bilin(_rid_pass, x, y) < 0.2):
		return 3 if _carve[_kof(x, y)] != 0 else 4
	if mt > 0.34 or m > 0.64:
		return 3
	var b := biome_id(x, y)
	if b != 3:
		var lat := eu_lat(y)
		var thr := 0.62 - 0.09 * clampf((lat - 47.0) / 10.0, -1.2, 1.4) + (0.14 if b == 2 else 0.0)
		if _n_f.value(x / 130.0, y / 130.0) > thr:
			return 2
	return 1

## Data for the GPU painter: the five noise tables (E, M, F, D, C stacked, 64 x 320), the blurred
## fields (R = shoreline, G = wide shoreline, B = ridges, A = open passes; 520 x 340) and carved passes.
func noise_table_image() -> Image:
	var all := PackedFloat32Array()
	for n in [_n_e, _n_m, _n_f, _n_d, _n_c]:
		all.append_array(n.table())
	return Image.create_from_data(64, 320, false, Image.FORMAT_RF, all.to_byte_array())

func field_image() -> Image:
	var all := PackedFloat32Array()
	all.resize(LW * LH * 4)
	for k in LW * LH:
		all[k * 4] = _lsh[k]
		all[k * 4 + 1] = _lwd[k]
		all[k * 4 + 2] = _rid[k]
		all[k * 4 + 3] = _rid_pass[k]
	return Image.create_from_data(LW, LH, false, Image.FORMAT_RGBAF, all.to_byte_array())

func carve_image() -> Image:
	return Image.create_from_data(GW, GH, false, Image.FORMAT_R8, _carve)

func detail_noise(x: float, y: float) -> float:
	return _n_d.value(x, y)

func cell_of(x: float, y: float) -> int:
	return _kof(x, y)

func walkable(t: int) -> bool:
	return t >= 1 and t <= 3

# ---------- connectivity ----------
# Same as the browser: TCOST[5] is undefined there, so river cells do not count as walkable land when labelling.
func _passable(t: int) -> bool:
	return t >= 1 and t <= 3

func _label_comps() -> Dictionary:
	var lab := PackedInt32Array()
	lab.resize(GW * GH)
	lab.fill(-1)
	var best := -1
	var best_n := 0
	var cid := 0
	for s in cells.size():
		if lab[s] >= 0 or not _passable(cells[s]):
			continue
		var n := 0
		var st := [s]
		lab[s] = cid
		while not st.is_empty():
			var c: int = st.pop_back()
			n += 1
			var ci := c % GW
			var cj := c / GW
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var x: int = ci + d[0]
				var y: int = cj + d[1]
				if x < 0 or y < 0 or x >= GW or y >= GH:
					continue
				var k := y * GW + x
				if lab[k] < 0 and _passable(cells[k]):
					lab[k] = cid
					st.append(k)
		if n > best_n:
			best_n = n
			best = cid
		cid += 1
	return {"comp": lab, "main": best}

func _cut_passes() -> void:
	var lab := _label_comps()
	for pass_i in 8:
		var sizes := {}
		for k in cells.size():
			if lab.comp[k] >= 0:
				sizes[lab.comp[k]] = int(sizes.get(lab.comp[k], 0)) + 1
		var dist := PackedFloat32Array()
		dist.resize(cells.size())
		dist.fill(1e9)
		var prev := PackedInt32Array()
		prev.resize(cells.size())
		prev.fill(-1)
		var h: Array = []
		for k in cells.size():
			if lab.comp[k] == lab.main:
				dist[k] = 0.0
				Heap.push(h, 0.0, k)
		while not h.is_empty():
			var top := Heap.pop(h)
			var d: float = top[0]
			var c: int = top[1]
			if d > dist[c]:
				continue
			var ci := c % GW
			var cj := c / GW
			for dd in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var x: int = ci + dd[0]
				var y: int = cj + dd[1]
				if x < 0 or y < 0 or x >= GW or y >= GH:
					continue
				var k := y * GW + x
				if cells[k] == 0:
					continue
				var nd := d + (6.0 if cells[k] == 4 else 1.0)
				if nd < dist[k]:
					dist[k] = nd
					prev[k] = c
					Heap.push(h, nd, k)
		var best_of := {}
		for k in cells.size():
			var c: int = lab.comp[k]
			if c < 0 or c == lab.main or dist[k] >= 1e9 or int(sizes.get(c, 0)) < 8:
				continue
			if not best_of.has(c) or dist[k] < dist[best_of[c]]:
				best_of[c] = k
		if best_of.is_empty():
			break
		for k0 in best_of.values():
			var k: int = k0
			while k >= 0 and dist[k] > 0.0:
				if cells[k] == 4:
					cells[k] = 3
					_carve[k] = 1
				k = prev[k]
		lab = _label_comps()

# ---------- rivers ----------
func _gen_rivers() -> void:
	var rnd := WorldNoise.Mulberry.new(seed_value + 211)
	var n_r := WorldNoise.ValueNoise.new(seed_value + 313)
	var rk := PackedByteArray()
	rk.resize(GW * GH)
	for ri in _data.rivers.size():
		var rd: Array = _data.rivers[ri]
		var w := float(rd[0])
		var P: Array = []
		var i := 1
		while i < rd.size():
			P.append([eu_x(float(rd[i])), eu_y(float(rd[i + 1]))])
			i += 2
		var D: Array = []
		for a in P.size() - 1:
			var p0: Array = P[maxi(0, a - 1)]
			var p1: Array = P[a]
			var p2: Array = P[a + 1]
			var p3: Array = P[mini(P.size() - 1, a + 2)]
			var n := maxi(2, ceili(_hyp(p2[0] - p1[0], p2[1] - p1[1]) / 6.0))
			for j in n:
				var t := float(j) / n
				var t2 := t * t
				var t3 := t2 * t
				var pt := []
				for ax in 2:
					pt.append(0.5 * (2 * p1[ax] + (-p0[ax] + p2[ax]) * t + (2 * p0[ax] - 5 * p1[ax] + 4 * p2[ax] - p3[ax]) * t2 + (-p0[ax] + 3 * p1[ax] - 3 * p2[ax] + p3[ax]) * t3))
				D.append(pt)
		D.append(P[P.size() - 1])
		var s := 0.0
		var M: Array = []
		for a in D.size():
			var p: Array = D[a]
			if a > 0:
				s += _hyp(p[0] - D[a - 1][0], p[1] - D[a - 1][1])
			var pa: Array = D[maxi(0, a - 2)]
			var pb: Array = D[mini(D.size() - 1, a + 2)]
			var L := _hyp(pb[0] - pa[0], pb[1] - pa[1])
			if L == 0.0:
				L = 1.0
			var o := (n_r.value(s / 150.0, ri * 9.7) - 0.5) * 48.0 * minf(1.0, s / 200.0)
			M.append([p[0] - (pb[1] - pa[1]) / L * o, p[1] + (pb[0] - pa[0]) / L * o])
		var cs: Array = []
		var curve: Array = []
		var own := {}
		var last := -1
		var started := false
		var stop := false
		var join := false
		var end := M.size()
		var a := 0
		while a < M.size() and not stop:
			var x: float = M[a][0]
			var y: float = M[a][1]
			a += 1
			if x < 0 or y < 0 or x >= WW or y >= WH:
				continue
			var k := _kof(x, y)
			if not started:
				if cells[k] == 0:
					continue
				started = true
			if k != last:
				var ci := k % GW
				var cj := k / GW
				if last >= 0:
					var li := last % GW
					var lj := last / GW
					if ci != li and cj != lj:
						var ka := lj * GW + ci
						var kb := cj * GW + li
						var da := _hyp(_cx(ka) - x, _cy(ka) - y)
						var db := _hyp(_cx(kb) - x, _cy(kb) - y)
						var res := _river_add(ka if da <= db else kb, ri, rk, own, cs)
						if res & 1: stop = true
						if res & 2: join = true
				if not stop:
					var res2 := _river_add(k, ri, rk, own, cs)
					if res2 & 1: stop = true
					if res2 & 2: join = true
				last = k
			curve.append([_r1(x), _r1(y)])
			if stop:
				end = a - 1
		if stop and not join:
			for q in range(end + 1, mini(M.size(), end + 5)):
				curve.append([_r1(M[q][0]), _r1(M[q][1])])
		if join and not curve.is_empty():
			var bd := 1e9
			var bp = null
			var tip: Array = curve[curve.size() - 1]
			for r in rivers:
				for q in r.p:
					var d := _hyp(q[0] - tip[0], q[1] - tip[1])
					if d < bd:
						bd = d
						bp = q
			if bp != null and bd < 60.0:
				curve.append(bp)
		if cs.size() >= 4:
			rivers.append({"w": w, "p": curve, "c": cs})
	_place_bridges(rk, rnd)

static func _r1(v: float) -> float:
	return floorf(v * 10.0 + 0.5) / 10.0

func _cx(k: int) -> float:
	return (k % GW) * GC + GC / 2.0
func _cy(k: int) -> float:
	return (k / GW) * GC + GC / 2.0

# returns bit 1 = stop, bit 2 = join
func _river_add(k: int, ri: int, rk: PackedByteArray, own: Dictionary, cs: Array) -> int:
	if cells[k] == 0 and rk[k] == 0:
		return 1
	if rk[k] != 0 and not own.has(k):
		if cs.size() > 5:
			return 3
		return 0
	if own.has(k):
		return 0
	if cells[k] == 4:
		return 0
	cells[k] = 5
	rk[k] = ri + 1
	own[k] = true
	cs.append(k)
	return 0

func _land(k: int) -> bool:
	return k >= 0 and k < cells.size() and (cells[k] == 1 or cells[k] == 2 or cells[k] == 3)

func _axis_of(k: int) -> int:
	var ci := k % GW
	var w := ci > 0 and _land(k - 1)
	var e := ci < GW - 1 and _land(k + 1)
	var n := _land(k - GW)
	var s := _land(k + GW)
	if w and e and not n and not s:
		return 0
	if n and s and not w and not e:
		return 1
	return -1

func _open_bridge(k: int, ax: int, w: float, rk: PackedByteArray) -> void:
	cells[k] = 1
	rk[k] = 0
	bridge[k] = 1
	bridges.append({"k": k, "x": _cx(k), "y": _cy(k), "ax": maxi(ax, 0), "w": w})

func _place_bridges(rk: PackedByteArray, rnd: WorldNoise.Mulberry) -> void:
	for r in rivers:
		var nxt := 100.0 + rnd.next() * 120.0
		var i := 0
		while i < r.c.size():
			if i * GC < nxt:
				i += 1
				continue
			var done := false
			var j := i
			while j < mini(r.c.size(), i + 8) and not done:
				var k: int = r.c[j]
				var ax := _axis_of(k)
				if ax >= 0:
					_open_bridge(k, ax, float(r.w) * (0.55 + 0.45 * j / r.c.size()), rk)
					done = true
					i = j
				j += 1
			if done:
				nxt = i * GC + 260.0 + rnd.next() * 200.0
			i += 1
	for pass_i in 12:
		var lab := _label_comps()
		var sizes := {}
		for k in cells.size():
			if lab.comp[k] >= 0:
				sizes[lab.comp[k]] = int(sizes.get(lab.comp[k], 0)) + 1
		var best := {}
		for k in cells.size():
			if cells[k] != 5:
				continue
			var ci := k % GW
			var ns: Array = []
			for q in [k - 1 if ci > 0 else -1, k + 1 if ci < GW - 1 else -1, k - GW, k + GW]:
				ns.append(lab.comp[q] if q >= 0 and q < cells.size() and lab.comp[q] >= 0 else -1)
			var ids: Array = []
			for q in ns:
				if q >= 0 and not ids.has(q):
					ids.append(q)
			if ids.size() < 2:
				continue
			var sc := (2 if _axis_of(k) >= 0 else 0) + (1 if ids.has(lab.main) else 0)
			for c in ids:
				if c == lab.main or int(sizes.get(c, 0)) < 8:
					continue
				if not best.has(c) or sc > best[c].sc:
					best[c] = {"k": k, "sc": sc}
		if best.is_empty():
			break
		for v in best.values():
			var k: int = v.k
			if cells[k] == 5:
				var rv: float = float(rivers[rk[k] - 1].w) if rk[k] - 1 >= 0 and rk[k] - 1 < rivers.size() else 10.0
				_open_bridge(k, _axis_of(k), rv * 0.8, rk)
