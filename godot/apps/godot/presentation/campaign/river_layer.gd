extends Node2D
## Rivers and bridges, like drawRivers()/drawBridges() in src/05b_worldart.js.
const Generator = preload("res://core/campaign/world/terrain_generator.gd")
const Brush = preload("res://apps/godot/presentation/campaign/map_brush.gd")

var _world: Generator

func build(world: Generator) -> void:
	_world = world
	queue_redraw()

func _draw() -> void:
	if _world == null:
		return
	var passes := [[Color(36 / 255.0, 52 / 255.0, 40 / 255.0, 0.55), 4.4], [Color("#4a82a0"), 0.0], [Color(190 / 255.0, 226 / 255.0, 236 / 255.0, 0.45), -0.62]]
	for pass_def in passes:
		for river in _world.rivers:
			var pts: Array = river.p
			var i := 0
			while i < pts.size() - 1:
				var last := mini(pts.size() - 1, i + 7)
				var line := PackedVector2Array()
				for k in range(i, last + 1):
					line.append(Vector2(pts[k][0], pts[k][1]))
				var width: float = float(river.w) * (0.5 + 0.5 * i / pts.size())
				var add: float = pass_def[1]
				width = width * -add if add < 0.0 else width + add
				draw_polyline(line, pass_def[0], width, true)
				draw_circle(line[0], width / 2.0, pass_def[0])  # round joints between pieces
				draw_circle(line[line.size() - 1], width / 2.0, pass_def[0])
				i += 6
	for b in _world.bridges:
		_bridge(b)

func _bridge(b: Dictionary) -> void:
	var length: float = float(b.w) + 18.0
	var height := 12.0
	draw_set_transform(Vector2(b.x, b.y), PI / 2.0 if int(b.ax) != 0 else 0.0, Vector2.ONE)
	Brush.fill_rect(self, -length / 2 + 1, -height / 2 + 3, length, height, Color(10 / 255.0, 20 / 255.0, 20 / 255.0, 0.35))
	Brush.fill_rect(self, -length / 2, -height / 2, length, height, Color("#85653c"))
	var plank := Color(40 / 255.0, 26 / 255.0, 12 / 255.0, 0.55)
	var x := -length / 2 + 3
	while x < length / 2:
		draw_line(Vector2(x, -height / 2), Vector2(x, height / 2), plank, 1.0, true)
		x += 3.5
	Brush.fill_rect(self, -length / 2, -height / 2 - 1.8, length, 2.6, Color("#4a3520"))
	Brush.fill_rect(self, -length / 2, height / 2 - 0.8, length, 2.6, Color("#4a3520"))
	for post_x in [-length / 2 - 1, length / 2 - 4]:
		Brush.fill_rect(self, post_x, -height / 2 - 2, 5, height + 4, Color("#9a9484"))
		Brush.stroke_rect(self, post_x, -height / 2 - 2, 5, height + 4, Brush.OUTLINE, 1.1)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
