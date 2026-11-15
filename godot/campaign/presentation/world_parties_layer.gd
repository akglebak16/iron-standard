extends Node2D
## Lords, vassals, bandits and caravans on the world map: a figure in faction colours with a small banner (drawWorld in src/07_main.js).
const EmblemArt = preload("res://campaign/presentation/emblem_art.gd")
const Brush = preload("res://campaign/presentation/map_brush.gd")
const OriginalArt = preload("res://ui/original_art.gd")
const FactionCatalog = preload("res://campaign/data/faction_catalog.gd")
const Rules = preload("res://campaign/world/party_rules.gd")

var roster: RefCounted
var player: RefCounted
var _factions := FactionCatalog.new()

func build(party_roster: RefCounted, player_party: RefCounted) -> void:
	roster = party_roster
	player = player_party
	if not (_factions.load_data()):
		push_error("Required content failed to load: campaign/presentation/world_parties_layer.gd")
		return

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
	var noble: bool = p.kind == "lord" or p.kind == "dead"
	var scale := 1.15 if noble else (0.7 if p.kind == "caravan" else 0.9)
	draw_colored_polygon(Brush.ellipse(at.x + 2, at.y + 3, 20 * scale, 7 * scale, 14), Color(0, 0, 0, 0.28))
	if Rules.hostile_to_player(p, player.rel):
		draw_arc(at + Vector2(0, 1), 22.0 * scale, 0.0, TAU, 24, Color(0.85, 0.2, 0.15, 0.85), 1.8, true)
	if p.kind == "caravan":
		draw_texture_rect(preload("res://ui/assets/caravan.png"), Rect2(at - Vector2(27.5, 28), Vector2(55, 35)), false)
		return
	var troop := ""
	var tier := -1
	for stack in p.troops:
		var info: Dictionary = roster.catalog.get_troop(stack.type)
		if int(info.tier) > tier:
			tier = int(info.tier)
			troop = stack.type
	var sprite := OriginalArt.sprite(troop, p.fac)
	if sprite != null:
		var key: String = troop + "|" + p.fac
		if not OriginalArt.MANIFEST.troops.has(key): key = troop + "|player"
		var anchor: Array = OriginalArt.MANIFEST.troops[key].anchor
		draw_texture_rect(sprite, Rect2(at - Vector2(anchor[0], anchor[1]) * 0.68, sprite.get_size() * 0.34), false)
	if p.kind != "bandit":
		EmblemArt.draw_banner(self, at.x + 13 * scale, at.y + 2, look, 9.0 * scale)
