extends Node2D
## Cartographic silhouettes are baked with the ground. Roads and passable mountain gaps reserve clear ground.
const Terrain = preload("res://core/campaign/world/terrain_generator.gd")
const WorldNoise = preload("res://core/campaign/world/noise.gd")
const ATLAS = preload("res://apps/godot/presentation/campaign/landscape/europe_relief.png")
const REGIONS := [
	Rect2(6, 120, 414, 214), Rect2(423, 156, 408, 184), Rect2(833, 198, 415, 124),
	Rect2(25, 499, 382, 248), Rect2(437, 477, 382, 274), Rect2(845, 482, 385, 267),
	Rect2(23, 940, 389, 228), Rect2(429, 911, 396, 277), Rect2(859, 907, 374, 289)]
var _stamps: Array = []

func build(world: RefCounted, roads: PackedByteArray, sites: Array) -> void:
	var rng := WorldNoise.Mulberry.new(world.seed_value + 3)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var reserved := roads.duplicate()
	for k in reserved.size():
		if world.is_mountain_pass(k): reserved[k] = 1
	for s in sites:
		var radius := 42 if s.kind == "town" else 22
		for x in range(-radius, radius+1, 10):
			for y in range(-radius, 15, 10):
				reserved[world.cell_of(s.x+x, s.y+y)] = 1
	var occupied := PackedByteArray()
	occupied.resize(roads.size())
	for j in Terrain.GH:
		for i in Terrain.GW:
			var k := j * Terrain.GW + i
			var t: int = world.cells[k]
			if reserved[k] or occupied[k] or t == 0 or t == 5: continue
			var chance := rng.next()
			if (t == 1 and chance > 0.011) or (t == 3 and chance > 0.35): continue
			var biome: int = world.bio[k]
			var art := 8
			var width := 13.0 + chance * 6.0
			if t == 4:
				art = 0 if biome == 1 or (biome == 0 and chance > 0.45) else 1
				width = 48.0 + 32.0 * chance
			elif t == 3:
				art = 2
				width = 27.0 + 20.0 * rng.next()
			elif t == 2:
				art = [3 if chance < 0.64 else 4, 5, 6, 7][biome]
				width = 28.0 + chance * 22.0
			else:
				art = [8, 5, 6, 7][biome]
			var at := Vector2((i+0.34+rng.next()*0.32)*Terrain.GC, (j+0.55+rng.next()*0.32)*Terrain.GC)
			var size := Vector2(width, width*REGIONS[art].size.y/REGIONS[art].size.x)
			# Limit overhang at the edge of a ridge and at road or settlement clearances.
			for attempt in 3:
				var blocked := false
				for dx in [-0.44, 0.0, 0.44]:
					for dy in [-0.8, -0.2]:
						var sample: int = world.cell_of(at.x+dx*size.x, at.y+dy*size.y)
						if reserved[sample] or world.cells[sample] in [0, 5]:
							blocked = true
				if not blocked: break
				size *= 0.65
			if size.x < 10.0: continue
			_stamps.append({"rect":Rect2(at-size*Vector2(0.5, 0.85), size), "art":art})
			if size.x > 44 and i+1 < Terrain.GW: occupied[k+1] = 1
	queue_redraw()

func _draw() -> void:
	for stamp in _stamps:
		draw_texture_rect_region(ATLAS, stamp.rect, REGIONS[stamp.art])
