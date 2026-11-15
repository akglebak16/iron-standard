extends RefCounted
const AssetPaths = preload("res://apps/godot/visuals/asset_paths.gd")
## Original Canvas layers shared by the battle and the campaign portraits.
const MANIFEST = preload("res://apps/godot/visuals/assets/visual_manifest.gd").DATA
const SHEETS = {
	"body": [preload("res://apps/godot/visuals/assets/body.png"), preload("res://apps/godot/visuals/assets/body_v1.png"), preload("res://apps/godot/visuals/assets/body_v2.png"), preload("res://apps/godot/visuals/assets/body_v3.png")],
	"weapon": [preload("res://apps/godot/visuals/assets/wpn.png"), preload("res://apps/godot/visuals/assets/wpn_v1.png"), preload("res://apps/godot/visuals/assets/wpn_v2.png"), preload("res://apps/godot/visuals/assets/wpn_v3.png")],
	"portrait": [preload("res://apps/godot/visuals/assets/portrait.png"), preload("res://apps/godot/visuals/assets/portrait_v1.png"), preload("res://apps/godot/visuals/assets/portrait_v2.png"), preload("res://apps/godot/visuals/assets/portrait_v3.png")],
	"headless": [preload("res://apps/godot/visuals/assets/headless.png"), preload("res://apps/godot/visuals/assets/headless_v1.png"), preload("res://apps/godot/visuals/assets/headless_v2.png"), preload("res://apps/godot/visuals/assets/headless_v3.png")],
	"head": [preload("res://apps/godot/visuals/assets/head.png"), preload("res://apps/godot/visuals/assets/head_v1.png"), preload("res://apps/godot/visuals/assets/head_v2.png"), preload("res://apps/godot/visuals/assets/head_v3.png")],
	"flash": [preload("res://apps/godot/visuals/assets/flash.png"), preload("res://apps/godot/visuals/assets/flash_v1.png"), preload("res://apps/godot/visuals/assets/flash_v2.png"), preload("res://apps/godot/visuals/assets/flash_v3.png")],
	"corpse": [preload("res://apps/godot/visuals/assets/corpse.png"), preload("res://apps/godot/visuals/assets/corpse_v1.png"), preload("res://apps/godot/visuals/assets/corpse_v2.png"), preload("res://apps/godot/visuals/assets/corpse_v3.png")],
	"corpse_headless": [preload("res://apps/godot/visuals/assets/corpse_headless.png"), preload("res://apps/godot/visuals/assets/corpse_headless_v1.png"), preload("res://apps/godot/visuals/assets/corpse_headless_v2.png"), preload("res://apps/godot/visuals/assets/corpse_headless_v3.png")],
}
static var _cache := {}
static var _looks := {}
static var _component_pages := {}

static func palette(faction: String) -> Dictionary:
	return MANIFEST.palettes.get(faction, MANIFEST.palettes.player).duplicate()

static func _stamp(image: Image, key: String, offset: Vector2i) -> void:
	if not MANIFEST.components.has(key):
		return
	var component: Dictionary = MANIFEST.components[key]
	var page: int = component.page
	if not _component_pages.has(page):
		var texture: Texture2D = load(AssetPaths.path("components_%d" % page))
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
	var corpse := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var prefix := "|" + faction + "|"
	if mounted:
		_stamp(body, "horse" + prefix + String(look.horse), offset)
	else:
		_stamp(body, "base|" + faction, offset)
	if look.get("weapon") in ["bow", "xbow"]:
		_stamp(body, "quiver", rider)
	_stamp(body, "torso" + prefix + String(look.get("armor", "tunic")), rider)
	if mounted:
		_stamp(headless, "horse_corpse" + prefix + String(look.horse), offset)
		_stamp(corpse, "horse_corpse" + prefix + String(look.horse), offset)
	if look.get("weapon") in ["bow", "xbow"]: _stamp(corpse, "quiver", rider)
	_stamp(corpse, "torso" + prefix + String(look.get("armor", "tunic")), rider)
	if look.get("weapon") in ["bow", "xbow"]: _stamp(headless, "quiver", rider)
	_stamp(headless, "torso" + prefix + String(look.get("armor", "tunic")), rider)
	_stamp(headless, "stump", rider)
	_stamp(head, "head" + prefix + String(look.get("helm", "none")) + "|" + String(look.get("undead", "")), rider)
	body.blend_rect(head, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	corpse.blend_rect(head, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	if look.get("shield") != null:
		_stamp(body, "shield" + prefix + String(look.shield), rider)
		_stamp(headless, "shield" + prefix + String(look.shield), rider)
		_stamp(corpse, "shield" + prefix + String(look.shield), rider)
	if look.get("weapon") != null:
		_stamp(weapon, "weapon" + prefix + String(look.weapon), rider)
	var portrait := Image.new()
	portrait.copy_from(body)
	portrait.blend_rect(weapon, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	corpse.blend_rect(weapon, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	var corpse_headless := Image.new()
	corpse_headless.copy_from(headless)
	corpse_headless.blend_rect(weapon, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	return {"body": ImageTexture.create_from_image(body), "headless": ImageTexture.create_from_image(headless),
		"weapon": ImageTexture.create_from_image(weapon), "head": ImageTexture.create_from_image(head),
		"flash": _white_texture(portrait), "corpse": ImageTexture.create_from_image(corpse),
		"corpse_headless": ImageTexture.create_from_image(corpse_headless),
		"portrait": ImageTexture.create_from_image(portrait), "weapon_kind": look.get("weapon"),
		"anchor": Vector2(112, 264) if mounted else Vector2(76, 158),
		"head_center": (Vector2(37.5, 29) + Vector2(rider)) * 2,
		"pivot": (Vector2(54.5, 50.5) + Vector2(rider)) * 2, "scale": 0.31}

static func _white_texture(image: Image) -> ImageTexture:
	var bytes := image.get_data()
	for i in range(0, bytes.size(), 4):
		bytes[i] = 255
		bytes[i + 1] = 255
		bytes[i + 2] = 255
	return ImageTexture.create_from_image(Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, bytes))

static func layers_for(unit: Dictionary, troop_id := "", variant := 0) -> Dictionary:
	var look: Dictionary = unit.look
	if unit.mounted and not look.get("horse"):
		look = look.duplicate()
		look.horse = "bay"
	elif not unit.mounted and look.get("horse"):
		look = look.duplicate()
		look.horse = null
	var faction: String = "player" if unit.hero or unit.companion else unit.faction
	if not MANIFEST.crests.has(faction): faction = "nord" if unit.side == 0 else "emp"
	var signature := str([faction, unit.mounted, look, troop_id, variant])
	if _looks.has(signature):
		return _looks[signature]
	if troop_id != "" and MANIFEST.troops.has(troop_id + "|" + faction) and not unit.hero and not unit.companion:
		var entry := _troop_layers(troop_id, faction, look, unit.mounted, variant)
		_looks[signature] = entry
		return entry
	for key in ([] if unit.hero or unit.companion else MANIFEST.troops.keys()):
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
		var entry := _troop_layers(troop, faction, look, unit.mounted, variant)
		_looks[signature] = entry
		return entry
	var composed := compose(look, faction)
	_looks[signature] = composed
	return composed

static func _troop_layers(troop: String, faction: String, look: Dictionary, mounted: bool, variant: int) -> Dictionary:
	var definition: Dictionary = MANIFEST.troops[troop + "|" + faction]
	var entry := {"body": sprite(troop, faction, "body", variant), "weapon": sprite(troop, faction, "weapon", variant),
		"portrait": sprite(troop, faction, "portrait", variant),
		"headless": sprite(troop, faction, "headless", variant), "head": sprite(troop, faction, "head", variant),
		"flash": sprite(troop, faction, "flash", variant), "corpse": sprite(troop, faction, "corpse", variant),
		"corpse_headless": sprite(troop, faction, "corpse_headless", variant),
		"weapon_kind": look.get("weapon"), "anchor": Vector2(definition.anchor[0], definition.anchor[1]) * 2,
		"pivot": Vector2(definition.pivot[0], definition.pivot[1]) * 2, "scale": 0.31}
	entry.head_center = Vector2(43.5, 57) * 2 if mounted else Vector2(39.5, 34) * 2
	return entry

static func settlement(kind: String, culture: String, faction: String) -> Texture2D:
	var key := "%s|%s|%s" % [kind, culture, faction]
	if not MANIFEST.settlements.has(key):
		key = "%s|emp|%s" % [kind, faction]
	if not MANIFEST.settlements.has(key):
		return null
	if not _cache.has(key):
		var r: Array = MANIFEST.settlements[key]
		var atlas := AtlasTexture.new()
		atlas.atlas = preload("res://apps/godot/visuals/assets/settlements.png")
		atlas.filter_clip = true
		atlas.region = Rect2(r[0], r[1], r[2], r[3])
		_cache[key] = atlas
	return _cache[key]

static func item_icon(id: String) -> Texture2D:
	var key: String = MANIFEST.items.get(id, "bag")
	var path := AssetPaths.path("item_%s" % key)
	return load(path) if not path.is_empty() and ResourceLoader.exists(path) else preload("res://apps/godot/visuals/assets/icon_bag.svg")

static func sprite(troop: String, faction := "player", part := "portrait", variant := 0) -> Texture2D:
	var key := troop + "|" + faction
	if not MANIFEST.troops.has(key):
		key = troop + "|player"
	if not MANIFEST.troops.has(key):
		return null
	var cache_key := key + "|" + part + "|" + str(variant)
	if not _cache.has(cache_key):
		var rect: Array = MANIFEST.troops[key].rect
		var atlas := AtlasTexture.new()
		atlas.atlas = SHEETS[part][clampi(variant, 0, 3)]
		atlas.region = Rect2(rect[0], rect[1], rect[2], rect[3])
		_cache[cache_key] = atlas
	return _cache[cache_key]

static func crest(faction: String) -> Texture2D:
	var path := AssetPaths.path("crest_%s" % faction)
	return load(path) if not path.is_empty() and ResourceLoader.exists(path) else null

static func portrait_control(troop: String, faction := "player", height := 68.0) -> TextureRect:
	var image := TextureRect.new()
	image.texture = sprite(troop, faction)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(64, height)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image
