extends Node2D
## Smooth each junction-to-junction run once. Decks, entrances and shared junctions stay pinned.
const Brush = preload("res://apps/godot/presentation/campaign/map_brush.gd")
var _lanes: Array = []
var _tracts: Array = []

func build(world: RefCounted, runs: Array) -> void:
	for run in runs:
		var pts: PackedVector2Array = run.points
		var line := PackedVector2Array([pts[0]])
		for i in range(1, pts.size()-1):
			var p := pts[i]
			if world.bridge[world.cell_of(p.x, p.y)] != 0:
				line.append(p)
			else:
				var a := p.lerp(pts[i-1], 0.25)
				var b := p.lerp(pts[i+1], 0.25)
				line.append_array(Brush.quad(a, p, b, 4))
		line.append(pts[-1])
		(_tracts if run.main else _lanes).append(line)
	queue_redraw()

func _draw() -> void:
	for style in [[Color("#775b35"), 3.3, 8.4], [Color("#cfab70"), 2.3, 6.9], [Color("#f4d9a0"), 1.1, 4.6]]:
		for road in _lanes: draw_polyline(road, style[0], style[1], true)
		for road in _tracts: draw_polyline(road, style[0], style[2], true)
