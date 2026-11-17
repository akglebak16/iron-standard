extends Node2D
## The player's party marker and the dashed route on the world map (drawWorld in src/07_main.js).
## A hero sprite replaces the marker when the characters module is hooked into the map.
const EmblemArt = preload("res://apps/godot/presentation/campaign/emblem_art.gd")
const Brush = preload("res://apps/godot/presentation/campaign/map_brush.gd")
const OriginalArt = preload("res://apps/godot/visuals/original_art.gd")
const HeroGear = preload("res://core/equipment/rules/hero_gear.gd")
var gear_catalog: RefCounted
var _appearance_inputs: Dictionary = {}
var _resolved_look: Dictionary = {}
var _figure: Dictionary = {}
const APPEARANCE_FIELDS := ["sel", "armor", "weapon", "shield", "horse", "seed", "beard", "hair", "face"]

var party: RefCounted
var look: Dictionary = {}
var motion: RefCounted # world_motion.gd; draws the marker between steps

func build(player: RefCounted, player_look: Dictionary, gear: RefCounted = null) -> void:
	party = player
	look = player_look
	gear_catalog = gear
	_appearance_inputs.clear()
	_resolved_look.clear()
	_figure.clear()

var _frozen: Variant = null  # {p, pts} while the simulation thread owns the world (world_sim_thread.gd)

## The world goes to the simulation thread: remember where the player is and his route. Call while owning the world.
func freeze() -> void:
	var pts := PackedVector2Array()
	if party.has_route():
		for i in range(party.pi, party.path.size()):
			pts.append(party.path[i])
	_frozen = {"p": Vector2(party.x, party.y), "pts": pts}

func thaw() -> void:
	_frozen = null

func _update_figure() -> void:
	var hero: Dictionary = party.hero
	var equipment: Variant = hero.get("eq")
	# Compare the small appearance projection. Equipment can be edited in place.
	var inputs := {"has_eq": hero.has("eq"), "eq": equipment}
	for field in APPEARANCE_FIELDS:
		inputs[field] = hero.get(field)
	if inputs == _appearance_inputs:
		return
	_appearance_inputs = inputs.duplicate(true)
	var resolved := HeroGear.resolve(hero, gear_catalog)
	var current_look: Dictionary = resolved.get("look", {})
	if current_look != _resolved_look or _figure.is_empty():
		_resolved_look = current_look
		_figure = OriginalArt.compose(current_look) if not current_look.is_empty() else {}

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if party == null:
		return
	var p: Vector2 = _frozen.p if _frozen != null else Vector2(party.x, party.y)
	if motion != null:
		p = motion.at(-1, p)
	var route: PackedVector2Array = _frozen.pts if _frozen != null else PackedVector2Array()
	if _frozen == null and party.has_route():
		for i in range(party.pi, party.path.size()):
			route.append(party.path[i])
	if not route.is_empty():
		var pts := PackedVector2Array([p])
		pts.append_array(route)
		_dashed(pts, Color(20 / 255.0, 12 / 255.0, 4 / 255.0, 0.8), 5.0)
		_dashed(pts, Color("#ffe9a0"), 2.6)
		draw_arc(pts[pts.size() - 1], 9.0, 0.0, TAU, 20, Color("#ffe9a0"), 2.6, true)
	draw_colored_polygon(Brush.ellipse(p.x + 2, p.y + 3, 24, 8, 16), Color(0, 0, 0, 0.3))
	draw_arc(p + Vector2(0, 1), 26.0, 0.0, TAU, 28, Color("#ffd86a"), 2.0, true)
	if gear_catalog != null and _frozen == null:
		_update_figure()
	if not _figure.is_empty():
		var k := 0.4
		draw_texture_rect(_figure.portrait, Rect2(p - Vector2(_figure.anchor) * k, _figure.portrait.get_size() * k), false)
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
