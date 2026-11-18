extends RefCounted
## Canonical undirected road edges, shared by routing, terrain clearance and painting.
const Terrain = preload("res://core/campaign/world/terrain_generator.gd")
var neighbours := {}
var runs: Array = []
var _anchors := {}

func _center(cell: int) -> Vector2:
	return Vector2((cell % Terrain.GW + 0.5) * Terrain.GC, (cell / Terrain.GW + 0.5) * Terrain.GC)

func build(paths: RefCounted, links: Array, sites: Array) -> void:
	var major := {}
	for s in sites:
		major[Vector2(s.x, s.y)] = s.kind in ["town", "castle"]
	var world = paths.world
	var spurs := {}
	for link in links:
		if link.size() < 2: continue
		var start: Vector2 = link.front()
		var finish: Vector2 = link.back()
		var trunk: bool = major.get(start, false) and major.get(finish, false)
		var a: Vector2 = paths.gate_approaches.get(start, start)
		var b: Vector2 = paths.gate_approaches.get(finish, finish)
		var route = paths.road_alignment(a, b)
		if route == null: continue
		for gate: Vector2 in [start, finish]:
			var apron: Vector2 = paths.gate_approaches.get(gate, gate)
			var cell: int = world.cell_of(apron.x, apron.y)
			_anchors[cell] = true
			if major.has(gate) and not spurs.has(gate):
				var points := PackedVector2Array([gate])
				if gate != apron: points.append(apron)
				if points[-1] != _center(cell): points.append(_center(cell))
				if points.size() > 1: runs.append({"points": points, "main": major[gate]})
				spurs[gate] = true
		var prev: int = world.cell_of(a.x, a.y)
		for point: Vector2 in route:
			var cell: int = world.cell_of(point.x, point.y)
			if cell != prev:
				_add_edge(prev, cell, trunk)
			prev = cell
	# Discard cul-de-sacs left by joining nearby paths, keeping destinations and bridges.
	var leaves := neighbours.keys()
	while not leaves.is_empty():
		var k: int = leaves.pop_back()
		if not neighbours.has(k) or _anchors.has(k) or world.bridge[k] != 0 or neighbours[k].size() != 1: continue
		var other: int = neighbours[k].keys()[0]
		neighbours.erase(k)
		neighbours[other].erase(k)
		leaves.append(other)
	paths.road.fill(0)
	for k in neighbours: paths.road[k] = 1
	for gate: Vector2 in spurs: paths.road[world.cell_of(gate.x, gate.y)] = 1
	var used := {}
	for k in neighbours:
		if neighbours[k].size() != 2 or _anchors.has(k): _trace(k, used, world)
	for k in neighbours: _trace(k, used, world)

func _add_edge(a: int, b: int, main: bool) -> void:
	if not neighbours.has(a): neighbours[a] = {}
	if not neighbours.has(b): neighbours[b] = {}
	if neighbours[a].has(b):
		main = main or neighbours[a][b]
	elif _nearby_connection(a, b):
		return
	neighbours[a][b] = main
	neighbours[b][a] = main

## A second lane closing a tiny loop reuses the established junction.
func _nearby_connection(a: int, b: int) -> bool:
	if neighbours[a].is_empty() or neighbours[b].is_empty(): return false
	var seen := {a:true}
	var frontier := [a]
	for depth in 7:
		var following := []
		for k in frontier:
			for n in neighbours[k]:
				if n == b: return true
				if not seen.has(n):
					seen[n] = true
					following.append(n)
		frontier = following
		if frontier.is_empty(): break
	return false

func _trace(start: int, used: Dictionary, world: RefCounted) -> void:
	for first in neighbours[start]:
		var a := start
		var b: int = first
		var main: bool = neighbours[a][b]
		var points := PackedVector2Array([_center(a)])
		while true:
			var key := Vector2i(mini(a, b), maxi(a, b))
			if used.has(key): break
			used[key] = true
			points.append(_center(b))
			if neighbours[b].size() != 2 or _anchors.has(b) or world.bridge[b] != 0: break
			var adjacent: Array = neighbours[b].keys()
			var next: int = adjacent[1] if adjacent[0] == a else adjacent[0]
			if neighbours[b][next] != main: break
			a = b
			b = next
		if points.size() > 1: runs.append({"points": points, "main": main})
