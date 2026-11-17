extends Node2D
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## Lords, vassals, bandits and caravans on the world map: a figure in faction colours with a small banner (drawWorld in src/07_main.js).
const EmblemArt = preload("res://apps/godot/presentation/campaign/emblem_art.gd")
const Brush = preload("res://apps/godot/presentation/campaign/map_brush.gd")
const OriginalArt = preload("res://apps/godot/visuals/original_art.gd")
const FactionCatalog = preload("res://core/campaign/data/faction_catalog.gd")
const Rules = preload("res://core/campaign/world/party_rules.gd")
const Decals = preload("res://apps/godot/presentation/campaign/party_decals.gd")
const DECAL_SHADER = preload("res://apps/godot/presentation/campaign/party_decals.gdshader")
const DRAW_MARGIN := 64.0 # banner, hostile ring and shadow extend beyond the party centre

var roster: RefCounted
var player: RefCounted
var motion: RefCounted # world_motion.gd; draws parties between steps
var _factions := FactionCatalog.new()
var _decals: SubViewport
var cache_decals := true
var _tiers := {}
var _records := {}  # party id -> its frozen copy, kept between freezes
var _freezes := 0
var _frozen: Variant = null  # copies of what is drawn, while the simulation thread owns the world (world_sim_thread.gd)

## The world goes to the simulation thread: remember what to draw. Call while the main thread still owns the world.
func freeze() -> void:
	var out: Array = []
	_freezes += 1
	var renew := _freezes % 16 == 0  # the figure of a party (its best troop) is looked up again now and then
	var kept := {}
	for party in roster.parties:
		if party.hide or party.kind == "camp":
			continue
		var rec: Variant = _records.get(party.id)
		if rec == null or renew or rec.stacks != party.troops.size():
			rec = {"id": party.id, "kind": party.kind, "fac": party.fac, "hide": false, "top": _top_troop(party), "stacks": party.troops.size()}
		rec.x = party.x
		rec.y = party.y
		rec.hostile = Rules.hostile_to_player(party, player.rel)
		kept[party.id] = rec
		out.append(rec)
	_records = kept
	_frozen = out

func thaw() -> void:
	_frozen = null

func _top_troop(p: Dictionary) -> String:
	var troop := ""
	var tier := -1
	for stack in p.troops:
		var t := _tier_of(stack.type)
		if t > tier:
			tier = t
			troop = stack.type
	return troop

## Tier of a troop type, remembered: the catalogue hands out a deep copy of the troop on every question.
func _tier_of(type: String) -> int:
	if not _tiers.has(type):
		_tiers[type] = int(roster.catalog.get_troop(type).tier)
	return _tiers[type]

func build(party_roster: RefCounted, player_party: RefCounted) -> void:
	roster = party_roster
	player = player_party
	if not (ContentLoader.populate(_factions)):
		push_error("Required content failed to load: apps/godot/presentation/campaign/world_parties_layer.gd")
		return
	if cache_decals and DisplayServer.get_name() != "headless":
		var palettes := _factions.factions.duplicate()
		palettes.player = OriginalArt.palette("player")
		_decals = Decals.new()
		add_child(_decals)
		_decals.bake(palettes)
		var atlas_material := ShaderMaterial.new()
		atlas_material.shader = DECAL_SHADER
		material = atlas_material

func _process(_delta: float) -> void:
	if is_visible_in_tree(): queue_redraw()

func _draw() -> void:
	if roster == null:
		return
	var visible_area: Rect2 = (get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()).grow(DRAW_MARGIN)
	var parties: Array = []
	for party in (_frozen if _frozen != null else roster.parties):
		if not party.hide and party.kind != "camp" and visible_area.has_point(Vector2(party.x, party.y)):
			parties.append(party)
	parties.sort_custom(func(a, b): return a.y < b.y)  # lower parties are drawn on top
	for p in parties:
		_draw_party(p)

func _draw_party(p: Dictionary) -> void:
	var at := Vector2(p.x, p.y)
	if motion != null:
		at = motion.at(int(p.id), at)
	var noble: bool = p.kind == "lord" or p.kind == "dead"
	var variant := 2 if noble else (0 if p.kind == "caravan" else 1)
	var scale_factor: float = Decals.MARKER_SCALES[variant]
	var hostile: bool = p.hostile if p.has("hostile") else Rules.hostile_to_player(p, player.rel)
	var cached: bool = _decals != null and _decals.ready_to_draw
	if cached:
		_decals.draw_base(self, at, variant, hostile)
	else:
		draw_colored_polygon(Brush.ellipse(at.x + 2, at.y + 3, 20 * scale_factor, 7 * scale_factor, 14), Color(0, 0, 0, 0.28))
		if hostile:
			draw_arc(at + Vector2(0, 1), 22.0 * scale_factor, 0.0, TAU, 24, Decals.HOSTILE, 1.8, true)
	if p.kind == "caravan":
		draw_texture_rect(preload("res://apps/godot/visuals/assets/caravan.png"), Rect2(at - Vector2(27.5, 28), Vector2(55, 35)), false)
		return
	var troop: String = p.top if p.has("top") else _top_troop(p)
	var sprite := OriginalArt.sprite(troop, p.fac)
	if sprite != null:
		var key: String = troop + "|" + p.fac
		if not OriginalArt.MANIFEST.troops.has(key): key = troop + "|player"
		var anchor: Array = OriginalArt.MANIFEST.troops[key].anchor
		draw_texture_rect(sprite, Rect2(at - Vector2(anchor[0], anchor[1]) * 0.68, sprite.get_size() * 0.34), false)
	if p.kind != "bandit":
		if cached:
			_decals.draw_flag(self, at, variant, p.fac)
		else:
			var look := OriginalArt.palette("player") if p.fac == "player" else _factions.get_faction(p.fac)
			EmblemArt.draw_banner(self, at.x + 13 * scale_factor, at.y + 2, look, 9.0 * scale_factor)
