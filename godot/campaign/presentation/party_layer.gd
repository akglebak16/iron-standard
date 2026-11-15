extends Node2D
## The player's party marker and the dashed route on the world map (drawWorld in src/07_main.js).
## A hero sprite replaces the marker when the characters module is hooked into the map.
const EmblemArt = preload("res://campaign/presentation/emblem_art.gd")
const Brush = preload("res://campaign/presentation/map_brush.gd")

var party: RefCounted
var look: Dictionary = {}

func build(player: RefCounted, player_look: Dictionary) -> void:
	party = player
	look = player_look

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if party == null:
		return
	if party.has_route():
		var pts := PackedVector2Array([Vector2(party.x, party.y)])
		for i in range(party.pi, party.path.size()):
			pts.append(party.path[i])
		_dashed(pts, Color(20 / 255.0, 12 / 255.0, 4 / 255.0, 0.8), 5.0)
		_dashed(pts, Color("#ffe9a0"), 2.6)
		draw_arc(pts[pts.size() - 1], 9.0, 0.0, TAU, 20, Color("#ffe9a0"), 2.6, true)
	var p := Vector2(party.x, party.y)
	draw_colored_polygon(Brush.ellipse(p.x + 2, p.y + 3, 24, 8, 16), Color(0, 0, 0, 0.3))
	draw_arc(p + Vector2(0, 1), 26.0, 0.0, TAU, 28, Color("#ffd86a"), 2.0, true)
	var body_color := Color(look.get("c1", "#c08a2e"))
	Brush.fill_stroke(self, Brush.ellipse(p.x, p.y - 8, 9, 11, 14), body_color, 1.8)
	Brush.fill_stroke(self, Brush.ellipse(p.x, p.y - 22, 6, 6, 12), Color("#d6b48a"), 1.6)
	if not look.is_empty():
		EmblemArt.draw_banner(self, p.x + 16, p.y + 2, look, 11.0)

func _dashed(pts: PackedVector2Array, color: Color, width: float) -> void:
	var dash := 8.0
	var gap := 7.0
	var carry := 0.0
	var drawing := true
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var length := a.distance_to(b)
		var pos := 0.0
		while pos < length:
			var span := (dash if drawing else gap) - carry
			var end := minf(length, pos + span)
			if drawing:
				draw_line(a.lerp(b, pos / length), a.lerp(b, end / length), color, width, true)
			carry += end - pos
			pos = end
			if carry >= (dash if drawing else gap) - 0.001:
				carry = 0.0
				drawing = not drawing
