extends Node2D
## Lords, vassals, bandits and caravans on the world map: a figure in faction colours with a small banner (drawWorld in src/07_main.js).
const EmblemArt = preload("res://campaign/presentation/emblem_art.gd")
const Brush = preload("res://campaign/presentation/map_brush.gd")
const FactionCatalog = preload("res://campaign/data/faction_catalog.gd")
const Rules = preload("res://campaign/world/party_rules.gd")

var roster: RefCounted
var player: RefCounted
var _factions := FactionCatalog.new()

func build(party_roster: RefCounted, player_party: RefCounted) -> void:
	roster = party_roster
	player = player_party
	assert(_factions.load_data())

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if roster == null:
		return
	var parties: Array = roster.parties.duplicate()
	parties.sort_custom(func(a, b): return a.y < b.y)  # lower parties are drawn on top
	for p in parties:
		if p.hide or p.kind == "camp":
			continue
		_draw_party(p)

func _draw_party(p: Dictionary) -> void:
	var look := _factions.get_faction(p.fac)
	var at := Vector2(p.x, p.y)
	var noble: bool = p.kind == "lord"
	var scale := 1.15 if noble else (0.7 if p.kind == "caravan" else 0.9)
	draw_colored_polygon(Brush.ellipse(at.x + 2, at.y + 3, 20 * scale, 7 * scale, 14), Color(0, 0, 0, 0.28))
	if Rules.hostile_to_player(p, player.rel):
		draw_arc(at + Vector2(0, 1), 22.0 * scale, 0.0, TAU, 24, Color(0.85, 0.2, 0.15, 0.85), 1.8, true)
	if p.kind == "caravan":
		Brush.fill_stroke(self, Brush.ellipse(at.x, at.y - 6, 11, 7, 12), Color("#8a6a3c"), 1.4)
		Brush.fill_stroke(self, Brush.ellipse(at.x - 9, at.y - 4, 4, 4, 8), Color("#4a3a22"), 1.2)
		return
	var body := Color(look.get("c1", "#555555"))
	Brush.fill_stroke(self, Brush.ellipse(at.x, at.y - 8 * scale, 8 * scale, 10 * scale, 14), body, 1.6)
	Brush.fill_stroke(self, Brush.ellipse(at.x, at.y - 20 * scale, 5 * scale, 5 * scale, 12), Color("#d6b48a"), 1.4)
	if p.kind != "bandit":
		EmblemArt.draw_banner(self, at.x + 13 * scale, at.y + 2, look, 9.0 * scale)
