extends RefCounted
## Original Canvas layers shared by the battle and the campaign portraits.
const MANIFEST = preload("res://ui/assets/visual_manifest.gd").DATA
const SHEETS = {
	"body": preload("res://ui/assets/body.png"),
	"weapon": preload("res://ui/assets/wpn.png"),
	"portrait": preload("res://ui/assets/portrait.png"),
	"headless": preload("res://ui/assets/headless.png"),
	"head": preload("res://ui/assets/head.png"),
}
static var _cache := {}
static var _looks := {}
static var _component_pages := {}

static func _stamp(image: Image, key: String, offset: Vector2i) -> void:
	if not MANIFEST.components.has(key):
		return
	var component: Dictionary = MANIFEST.components[key]
	var page: int = component.page
	if not _component_pages.has(page):
		var texture: Texture2D = load("res://ui/assets/components_%d.png" % page)
		_component_pages[page] = texture.get_image()
	var r: Array = component.rect
	image.blend_rect(_component_pages[page], Rect2i(r[0], r[1], r[2], r[3]), offset * 2)

static func compose(look: Dictionary, faction := "player") -> Dictionary:
	var mounted: bool = look.get("horse") != null and look.get("horse") != ""
	var size := Vector2i(240, 244) if mounted else Vector2i(152, 176)
	var offset := Vector2i(2, 26) if mounted else Vector2i(2, 5)
	var rider := offset + (Vector2i(4, 2) if mounted else Vector2i.ZERO)
	var body := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var headless := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var weapon := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var head := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var prefix := "|" + faction + "|"
	if mounted:
		_stamp(body, "horse" + prefix + String(look.horse), offset)
	else:
		_stamp(body, "base|" + faction, offset)
	if look.get("weapon") in ["bow", "xbow"]:
		_stamp(body, "quiver", rider)
	_stamp(body, "torso" + prefix + String(look.get("armor", "tunic")), rider)
	if mounted: _stamp(headless, "horse" + prefix + String(look.horse), offset)
	if look.get("weapon") in ["bow", "xbow"]: _stamp(headless, "quiver", rider)
	_stamp(headless, "torso" + prefix + String(look.get("armor", "tunic")), rider)
	_stamp(headless, "stump", rider)
	_stamp(head, "head" + prefix + String(look.get("helm", "none")) + "|" + String(look.get("undead", "")), rider)
	body.blend_rect(head, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	if look.get("shield") != null:
		_stamp(body, "shield" + prefix + String(look.shield), rider)
		_stamp(headless, "shield" + prefix + String(look.shield), rider)
	if look.get("weapon") != null:
		_stamp(weapon, "weapon" + prefix + String(look.weapon), rider)
	var portrait := Image.new()
	portrait.copy_from(body)
	portrait.blend_rect(weapon, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	return {"body": ImageTexture.create_from_image(body), "headless": ImageTexture.create_from_image(headless),
		"weapon": ImageTexture.create_from_image(weapon), "head": ImageTexture.create_from_image(head),
		"portrait": ImageTexture.create_from_image(portrait), "weapon_kind": look.get("weapon"),
		"anchor": Vector2(112, 264) if mounted else Vector2(76, 158),
		"head_center": (Vector2(37.5, 29) + Vector2(rider)) * 2,
		"pivot": (Vector2(54.5, 50.5) + Vector2(rider)) * 2, "scale": 0.31}

static func layers_for(unit: Dictionary) -> Dictionary:
	var look: Dictionary = unit.look
	if unit.mounted and not look.get("horse"):
		look = look.duplicate()
		look.horse = "bay"
	elif not unit.mounted and look.get("horse"):
		look = look.duplicate()
		look.horse = null
	var faction: String = "player" if unit.hero or unit.companion else unit.faction
	if not MANIFEST.crests.has(faction): faction = "nord" if unit.side == 0 else "emp"
	var signature := str([faction, unit.mounted, look])
	if _looks.has(signature):
		return _looks[signature]
	for key in MANIFEST.troops:
		var definition: Dictionary = MANIFEST.troops[key]
		if key.get_slice("|", 1) != faction:
			continue
		var same := true
		for field in ["helm", "armor", "weapon", "shield", "horse", "undead"]:
			if look.get(field) != definition.look.get(field):
				same = false
				break
		if not same:
			continue
		var troop: String = key.get_slice("|", 0)
		var entry := {"body": sprite(troop, faction, "body"), "weapon": sprite(troop, faction, "weapon"),
			"headless": sprite(troop, faction, "headless"), "head": sprite(troop, faction, "head"),
			"weapon_kind": look.get("weapon"), "anchor": Vector2(definition.anchor[0], definition.anchor[1]) * 2,
			"pivot": Vector2(definition.pivot[0], definition.pivot[1]) * 2, "scale": 0.31}
		entry.head_center = Vector2(43.5, 57) * 2 if unit.mounted else Vector2(39.5, 34) * 2
		_looks[signature] = entry
		return entry
	var composed := compose(look, faction)
	_looks[signature] = composed
	return composed

static func settlement(kind: String, culture: String, faction: String) -> Texture2D:
	var key := "%s|%s|%s" % [kind, culture, faction]
	if not MANIFEST.settlements.has(key):
		key = "%s|emp|%s" % [kind, faction]
	if not MANIFEST.settlements.has(key):
		return null
	if not _cache.has(key):
		var r: Array = MANIFEST.settlements[key]
		var atlas := AtlasTexture.new()
		atlas.atlas = preload("res://ui/assets/settlements.png")
		atlas.region = Rect2(r[0], r[1], r[2], r[3])
		_cache[key] = atlas
	return _cache[key]

static func item_icon(id: String) -> Texture2D:
	var key: String = MANIFEST.items.get(id, "bag")
	var path := "res://ui/assets/item_%s.svg" % key
	return load(path) if ResourceLoader.exists(path) else preload("res://ui/assets/icon_bag.svg")

static func sprite(troop: String, faction := "player", part := "portrait") -> Texture2D:
	var key := troop + "|" + faction
	if not MANIFEST.troops.has(key):
		key = troop + "|player"
	if not MANIFEST.troops.has(key):
		return null
	var cache_key := key + "|" + part
	if not _cache.has(cache_key):
		var rect: Array = MANIFEST.troops[key].rect
		var atlas := AtlasTexture.new()
		atlas.atlas = SHEETS[part]
		atlas.region = Rect2(rect[0], rect[1], rect[2], rect[3])
		_cache[cache_key] = atlas
	return _cache[cache_key]

static func crest(faction: String) -> Texture2D:
	var path := "res://ui/assets/crest_%s.png" % faction
	return load(path) if ResourceLoader.exists(path) else null

static func portrait_control(troop: String, faction := "player", height := 68.0) -> TextureRect:
	var image := TextureRect.new()
	image.texture = sprite(troop, faction)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(64, height)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image
