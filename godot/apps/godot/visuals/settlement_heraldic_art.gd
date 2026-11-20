extends RefCounted
## Settlements of the campaign map in the heraldic style (#254): one picture per kind and culture
## (tools/map/render_heraldic_settlements.cjs). The owner's banner is not drawn in: the map puts it on a
## pole at flag(), so a captured town changes colours at once.
const ATLAS = preload("res://apps/godot/visuals/assets/settlements_heraldic.png")
const GEO = preload("res://apps/godot/visuals/settlements_heraldic_geometry.gd").DATA
const FRAME := Vector2(220, 220)
## The point of the frame standing on the settlement's map position.
const ANCHOR := Vector2(110, 180)
## Cultures without their own drawings borrow one.
const FALLBACK_CULTURE := "emp"

static var _cache := {}

static func _key(kind: String, culture: String) -> String:
	if kind == "camp": return "camp"
	var key := "%s|%s" % [kind, culture]
	return key if GEO.cells.has(key) else "%s|%s" % [kind, FALLBACK_CULTURE]

## The picture of a settlement, or null for a kind without one.
static func texture(kind: String, culture: String) -> Texture2D:
	var key := _key(kind, culture)
	if not GEO.cells.has(key): return null
	if not _cache.has(key):
		var at: Array = GEO.cells[key]
		var atlas := AtlasTexture.new()
		atlas.atlas = ATLAS
		atlas.filter_clip = true
		atlas.region = Rect2(Vector2(at[0], at[1]), FRAME)
		_cache[key] = atlas
	return _cache[key]

## Foot of the owner's banner pole, from the anchor, in frame pixels.
static func flag(kind: String, culture: String) -> Vector2:
	var at: Array = GEO.flags.get(_key(kind, culture), [0, -80])
	return Vector2(at[0], at[1])
