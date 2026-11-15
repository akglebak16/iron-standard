extends RefCounted
## Port of genRoads / thinPath (src/05_world.js): a spanning network between all settlements,
## two nearest neighbours each, camps to the nearest town, and approaches to every bridge.
const Generator = preload("res://campaign/world/terrain_generator.gd")
const Pathfinder = preload("res://campaign/world/pathfinder.gd")

var roads: Array = []   # each road is an Array of Vector2
var _paths: Pathfinder
var _world: Generator

func generate(world: Generator, paths: Pathfinder, settles: Array) -> Array:
	_world = world
	_paths = paths
	roads = []
	paths.road.fill(0)
	var towns: Array = settles.filter(func(s): return s.kind != "camp")
	var done := {}
	var edges: Array = []
	for i in towns.size():
		for j in range(i + 1, towns.size()):
			edges.append([_dist(towns[i], towns[j]), i, j])
	edges.sort_custom(func(p, q): return p[0] < q[0] or (p[0] == q[0] and (p[1] < q[1] or (p[1] == q[1] and p[2] < q[2]))))
	var up: Array = []
	for i in towns.size():
		up.append(i)
	for e in edges:
		if e[0] > 1500.0:
			break
		var i: int = e[1]
		var j: int = e[2]
		if _find(up, i) == _find(up, j):
			continue
		if _link(towns[i], towns[j]):
			up[_find(up, i)] = _find(up, j)
			done[_key(towns[i], towns[j])] = true
	for a in towns:
		var others: Array = []
		for idx in towns.size():
			if towns[idx] != a:
				others.append([_dist(a, towns[idx]), idx])
		others.sort_custom(func(p, q): return p[0] < q[0] or (p[0] == q[0] and p[1] < q[1]))
		var n := 0
		for o in others:
			var b: Dictionary = towns[o[1]]
			var key := _key(a, b)
			if done.has(key):
				n += 1
				if n >= 2:
					break
				continue
			done[key] = true
			_link(a, b)
			n += 1
			if n >= 2:
				break
	for c in settles.filter(func(s): return s.kind == "camp"):
		var sorted_towns := towns.duplicate()
		sorted_towns.sort_custom(func(p, q): return _dist(p, c) < _dist(q, c))
		var b: Dictionary = sorted_towns[0]
		if _dist(b, c) < 380.0:
			_link(c, b)
	_bridge_approaches(towns)
	return roads

func _dist(a: Dictionary, b: Dictionary) -> float:
	return sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))

func _key(a: Dictionary, b: Dictionary) -> String:
	return "%d-%d" % [mini(a.id, b.id), maxi(a.id, b.id)]

func _find(up: Array, i: int) -> int:
	while up[i] != i:
		up[i] = up[up[i]]
		i = up[i]
	return i

func _link(a: Dictionary, b: Dictionary) -> bool:
	var p = _paths.find_path(a.x, a.y, b.x, b.y, true)
	if p == null:
		return false
	var seg: Array = [Vector2(a.x, a.y)]
	seg.append_array(p)
	_add_road(_thin(seg))
	return true

func _add_road(seg: Array) -> void:
	for i in seg.size() - 1:
		var length: float = (seg[i + 1] - seg[i]).length()
		var n := ceili(length / 8.0)
		for k in n + 1:
			var t := float(k) / n if n > 0 else 0.0
			var pt: Vector2 = seg[i].lerp(seg[i + 1], t)
			_paths.road[_world.cell_of(pt.x, pt.y)] = 1
	roads.append(seg)

# Straight pieces between cell centres need no extra points, except bridges (the picture needs them).
func _thin(seg: Array) -> Array:
	var out: Array = [seg[0]]
	for i in range(1, seg.size() - 1):
		var ax: float = seg[i].x - seg[i - 1].x
		var ay: float = seg[i].y - seg[i - 1].y
		var bx: float = seg[i + 1].x - seg[i].x
		var by: float = seg[i + 1].y - seg[i].y
		if absf(ax * by - ay * bx) < 1e-6 and ax * bx + ay * by > 0.0 and _world.bridge[_world.cell_of(seg[i].x, seg[i].y)] == 0:
			continue
		out.append(seg[i])
	out.append(seg[seg.size() - 1])
	return out

func _bridge_approaches(towns: Array) -> void:
	for b in _world.bridges:
		if _paths.road[b.k] != 0:
			continue
		for sg in [-1, 1]:
			var sp := _bridge_point(b, sg, 1)
			if not _paths.passable_type(_paths.terr_at(sp.x, sp.y)):
				continue
			var target = null
			var best := 900.0
			for q in towns:
				var d := sqrt((q.x - sp.x) * (q.x - sp.x) + (q.y - sp.y) * (q.y - sp.y))
				if d < best:
					best = d
					target = q
			var tail = _paths.find_path(sp.x, sp.y, target.x, target.y, true) if target != null else null
			if tail == null:
				tail = []
				for n in range(2, 5):
					var q := _bridge_point(b, sg, n)
					if _paths.passable_type(_paths.terr_at(q.x, q.y)):
						tail.append(q)
					else:
						break
			var seg: Array = [Vector2(b.x, b.y), sp]
			seg.append_array(tail)
			_add_road(_thin(seg))

func _bridge_point(b: Dictionary, sg: int, n: int) -> Vector2:
	var gc := float(Generator.GC)
	return Vector2(b.x + sg * gc * n, b.y) if int(b.ax) == 0 else Vector2(b.x, b.y + sg * gc * n)
