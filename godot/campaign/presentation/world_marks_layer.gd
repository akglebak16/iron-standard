extends Node2D
## War and quest marks over the world map (drawWar, sgDraw in src/06e_war.js and src/06i_siege.js, drawJqMark in
## src/06f_jquests.js): siege rings, fights lasting hours, fires and smoke, blockades, the quest target pointer.
const FactionCatalog = preload("res://campaign/data/faction_catalog.gd")

var state: RefCounted
var _factions := FactionCatalog.new()
var _time := 0.0
var _quest_mark: Variant = null # {x, y, t0}

func build(world_state: RefCounted) -> void:
	state = world_state
	if not (_factions.load_data()):
		push_error("Required content failed to load: campaign/presentation/world_marks_layer.gd")
		return

## Pulsing rings and a bouncing pointer over a quest target for seven seconds.
func show_quest_target(x: float, y: float) -> void:
	_quest_mark = {"x": x, "y": y, "t0": _time}

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _label(text: String, x: float, y: float, color: Color, size: int) -> void:
	var font := preload("res://ui/game_theme.gd").BODY_BOLD
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(font, Vector2(x - w / 2.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.05, 0.03, 0.02, 0.9))
	draw_string(font, Vector2(x - w / 2.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _ellipse(center: Vector2, rx: float, ry: float, color: Color, width: float, dashed := false) -> void:
	var points := PackedVector2Array()
	for i in 41:
		points.append(center + Vector2(cos(TAU * i / 40.0) * rx, sin(TAU * i / 40.0) * ry))
	if dashed:
		for i in range(0, 40, 2):
			draw_line(points[i], points[i + 1], color, width, true)
	else:
		draw_polyline(points, color, width, true)

func _draw() -> void:
	if state == null:
		return
	var zoom: float = get_viewport().get_canvas_transform().get_scale().x
	var k := 1.0 / maxf(0.2, zoom)
	var t := _time * 2.5
	for s in state.map.settles:
		var fire := int(s.get("fire", 0)) > 0
		var smoke := not fire and (float(s.get("dmg", 0.0)) > 0.3 or int(s.get("burnt", 0)) > 0)
		if s.get("blk") is Dictionary:
			_label("Блокада · еда %d дн." % ceili(state.siege.food_of(s)), s.x, s.y - 60, Color("#ffd27a"), 12)
		if fire or smoke:
			var bx: float = s.x
			var by: float = s.y - 8
			for i in 3:
				var ph := fmod(t * 0.35 + i / 3.0 + s.id * 0.13, 1.0)
				draw_circle(Vector2(bx + sin(ph * 5 + i) * 8 + (i - 1) * 8, by - 18 - ph * 46), 7 + ph * 11, Color(0.29, 0.27, 0.25, (1.0 - ph) * (0.5 if fire else 0.35)))
			if fire:
				for i in 6:
					var ox := (i - 2.5) * 8 + sin(s.id + i * 2) * 3
					var h := 13 + 7 * sin(t * 3.2 + i * 2.1 + s.id)
					var x: float = bx + ox
					var y: float = by + absf(cos(s.id * 3 + i)) * 6
					draw_colored_polygon(PackedVector2Array([Vector2(x - 5, y), Vector2(x - 3, y - h * 0.6), Vector2(x + sin(t * 2 + i) * 2.5, y - h), Vector2(x + 3, y - h * 0.5), Vector2(x + 5, y)]),
						Color("#ff9a2e") if i % 2 else Color("#ffd26a"))
				_label("Пожар", s.x, s.y - 74, Color("#ffb066"), 12)
		if s.get("siege") is Dictionary:
			_ellipse(Vector2(s.x, s.y + 6), 58.0 if s.kind == "castle" else 66.0, 24.0, Color(0.9, 0.27, 0.16, 0.85), 3.0, true)
			_label("Осада · " + String(_factions.get_faction(s.siege.f).get("name", "")).split(" ")[0], s.x, s.y - 52, Color("#ff9a7a"), 13)
	for sk in state.skirmish.fights:
		var c := Vector2(sk.x, sk.y - 4)
		draw_arc(c, 14 + sin(t) * 2, 0, TAU, 24, Color(0.9, 0.27, 0.16, 0.8), 2.0, true)
		draw_line(c + Vector2(-7, -7), c + Vector2(7, 7), Color("#ffd9a0"), 2.4, true)
		draw_line(c + Vector2(7, -7), c + Vector2(-7, 7), Color("#ffd9a0"), 2.4, true)
		_label("Бой", c.x, c.y - 22, Color("#ff9a7a"), 12)
	if _quest_mark != null:
		var qt: float = _time - float(_quest_mark.t0)
		if qt > 7.0:
			_quest_mark = null
			return
		var fade := (7.0 - qt) / 1.5 if qt > 5.5 else 1.0
		var qx: float = _quest_mark.x
		var qy: float = _quest_mark.y
		for i in 3:
			var ph := fmod(qt * 0.8 + i / 3.0, 1.0)
			var r := (18.0 + ph * 70.0) * k
			_ellipse(Vector2(qx, qy + 4 * k), r, r * 0.45, Color(1.0, 0.84, 0.42, 0.9 * (1.0 - ph) * fade), 3.0 * k)
		var y := qy - 52 * k - absf(sin(qt * 3.0)) * 6 * k
		var tri := PackedVector2Array([Vector2(qx, y + 22 * k), Vector2(qx - 12 * k, y), Vector2(qx + 12 * k, y)])
		draw_colored_polygon(tri, Color(1.0, 0.84, 0.42, 0.95 * fade))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0.16, 0.09, 0.02, fade), 2.0 * k, true)
