extends Node2D
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## Lords, vassals, bandits and caravans on the world map: a figure in faction colours with a small banner (drawWorld in src/07_main.js).
const EmblemArt = preload("res://apps/godot/presentation/campaign/emblem_art.gd")
const Brush = preload("res://apps/godot/presentation/campaign/map_brush.gd")
const OriginalArt = preload("res://apps/godot/visuals/original_art.gd")
const FactionCatalog = preload("res://core/campaign/data/faction_catalog.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const DRAW_MARGIN := 64.0 # banner, hostile ring and shadow extend beyond the party centre

var roster: RefCounted
var player: RefCounted
var _factions := FactionCatalog.new()

func build(party_roster: RefCounted, player_party: RefCounted) -> void:
	roster = party_roster
	player = player_party
	if not (ContentLoader.populate(_factions)):
		push_error("Required content failed to load: apps/godot/presentation/campaign/world_parties_layer.gd")
		return

func _process(_delta: float) -> void:
	if is_visible_in_tree(): queue_redraw()

func _draw() -> void:
	if roster == null:
		return
	var visible_area: Rect2 = (get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()).grow(DRAW_MARGIN)
	var parties: Array = []
	for party in roster.parties:
		if not party.hide and party.kind != "camp" and visible_area.has_point(Vector2(party.x, party.y)):
			parties.append(party)
	parties.sort_custom(func(a, b): return a.y < b.y)  # lower parties are drawn on top
	for p in parties:
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
		draw_texture_rect(preload("res://apps/godot/visuals/assets/caravan.png"), Rect2(at - Vector2(27.5, 28), Vector2(55, 35)), false)
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
