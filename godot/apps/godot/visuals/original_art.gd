extends RefCounted
const AssetPaths = preload("res://apps/godot/visuals/asset_paths.gd")
const DominionHeraldic = preload("res://apps/godot/visuals/dominion_heraldic_art.gd")
## Original Canvas layers shared by the battle and the campaign portraits.
const MANIFEST = preload("res://apps/godot/visuals/assets/visual_manifest.gd").DATA
const BANNERS = preload("res://apps/godot/visuals/assets/banner_definitions.gd").DATA
## Hero and companion faces, helms by banner and neck stumps (exported once from the removed JS version).
const FACES = preload("res://apps/godot/visuals/assets/face_manifest.gd").DATA
const FaceVariant = preload("res://apps/godot/visuals/face_variant.gd")
const HeroHeraldic = preload("res://apps/godot/visuals/hero_heraldic_art.gd")
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
static var _face_pages := {}
static var _banner_sheets := {}
static var _player_banner := 0
static var _guards := {}
static var _sheet_images := {}
static var _batching := false
const GUARD_DILATE := 2
const GUARD_PAD := 2

## Appearance preference only. Call at mode preparation, before constructing the new views.
static func select_player_banner(index: int) -> void:
	index = clampi(index, 0, BANNERS.size() - 1)
	if index == _player_banner: return
	_player_banner = index
	_cache.clear()
	_looks.clear()
	_component_pages.clear()
	_face_pages.clear()
	_banner_sheets.clear()
	_guards.clear()
	HeroHeraldic.clear_cache()

static func _banner_image(source: Image, key: String) -> Image:
	if _player_banner == 0: return source
	var path := AssetPaths.path("banner_%d_%s" % [_player_banner, key])
	if path.is_empty(): return source
	var replacement := (load(path) as Texture2D).get_image()
	var image := Image.new()
	image.copy_from(source)
	image.blit_rect_mask(replacement, replacement, Rect2i(Vector2i.ZERO, replacement.get_size()), Vector2i.ZERO)
	image.fix_alpha_edges()
	return image

static func _banner_sheet(source: Texture2D, key: String) -> Texture2D:
	if _player_banner == 0: return source
	if not _banner_sheets.has(key):
		_banner_sheets[key] = ImageTexture.create_from_image(_banner_image(source.get_image(), key))
	return _banner_sheets[key]

static func palette(faction: String) -> Dictionary:
	var result: Dictionary = MANIFEST.palettes.get(faction, MANIFEST.palettes.player).duplicate()
	if faction == "player":
		result.c1 = BANNERS[_player_banner].c1
		result.c2 = BANNERS[_player_banner].c2
	return result

static func _stamp(image: Image, key: String, offset: Vector2i) -> void:
	if not MANIFEST.components.has(key):
		return
	var component: Dictionary = MANIFEST.components[key]
	var page: int = component.page
	if not _component_pages.has(page):
		var texture: Texture2D = load(AssetPaths.path("components_%d" % page))
		_component_pages[page] = _banner_image(texture.get_image(), "components_%d" % page)
	var r: Array = component.rect
	image.blend_rect(_component_pages[page], Rect2i(r[0], r[1], r[2], r[3]), offset * 2)

static func _stamp_face(image: Image, key: String, offset: Vector2i) -> bool:
	if not FACES.frames.has(key):
		return false
	var frame: Dictionary = FACES.frames[key]
	var page: int = frame.page
	if not _face_pages.has(page):
		var texture: Texture2D = load(AssetPaths.path("faces_%d" % page))
		_face_pages[page] = texture.get_image()
	var r: Array = frame.rect
	image.blend_rect(_face_pages[page], Rect2i(r[0], r[1], r[2], r[3]), offset * 2)
	return true

## Face, beard and scar from the hero's seed, then his helm painted in the chosen banner colours
## (drawHead and drawHelm in src/02_art.js; a bald head without a helm shows no hair).
static func _stamp_own_head(image: Image, helm: String, face: Dictionary, offset: Vector2i) -> bool:
	var key := "face|%s|%s|%d|%d|%d" % [face.skin, face.hair, face.beard, face.stache, 1 if face.scar else 0]
	if not _stamp_face(image, key, offset):
		return false
	if helm == "none":
		if not face.bald:
			_stamp_face(image, "helm|%d|none|%s" % [_player_banner, face.hair], offset)
	elif not _stamp_face(image, "helm|%d|%s" % [_player_banner, helm], offset):
		_stamp_face(image, "helm|0|%s" % helm, offset)
	return true

static func compose(look: Dictionary, faction := "player") -> Dictionary:
	# The hero and companions in the heraldic style, painted in the player's banner (#232).
	if faction == "player" and HeroHeraldic.supports(look):
		var own_face := FaceVariant.of_look(look)
		if not own_face.is_empty():
			return HeroHeraldic.compose(look, own_face, BANNERS[_player_banner])
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
	var face := FaceVariant.of_look(look) if faction == "player" and String(look.get("undead", "")) == "" else {}
	if face.is_empty() or not _stamp_face(headless, "stump|" + String(face.skin), rider):
		_stamp(headless, "stump", rider)
	if face.is_empty() or not _stamp_own_head(head, String(look.get("helm", "none")), face, rider):
		_stamp(head, "head" + prefix + String(look.get("helm", "none")) + "|" + String(look.get("undead", "")), rider)
	body.blend_rect(head, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	corpse.blend_rect(head, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	var bare: Image = null
	var shield_layer: Image = null
	if look.get("shield") != null:
		bare = Image.new()
		bare.copy_from(body)
		shield_layer = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		_stamp(shield_layer, "shield" + prefix + String(look.shield), rider)
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
	var result := {"body": ImageTexture.create_from_image(body), "headless": ImageTexture.create_from_image(headless),
		"weapon": ImageTexture.create_from_image(weapon), "head": ImageTexture.create_from_image(head),
		"flash": _white_texture(portrait), "corpse": ImageTexture.create_from_image(corpse),
		"corpse_headless": ImageTexture.create_from_image(corpse_headless),
		"portrait": ImageTexture.create_from_image(portrait), "weapon_kind": look.get("weapon"),
		"anchor": Vector2(112, 264) if mounted else Vector2(76, 158),
		"head_center": (Vector2(37.5, 29) + Vector2(rider)) * 2,
		"pivot": (Vector2(54.5, 50.5) + Vector2(rider)) * 2, "scale": 0.31}
	if bare != null:
		# Kept as images: the battle splits the shield off only for figures that fight.
		result.guard_source = [bare, shield_layer]
	return result

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
	var faction := _faction(unit)
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

static func _faction(unit: Dictionary) -> String:
	var faction: String = "player" if unit.get("hero", false) or unit.get("companion", false) else String(unit.get("faction", ""))
	if not MANIFEST.crests.has(faction): faction = "nord" if int(unit.get("side", 0)) == 0 else "emp"
	return faction

## Raised-shield layers for the battle block animation, built once per look. "layers" paint the figure
## without its resting shield (texture and offset in body-image pixels); "shield" is drawn separately
## around "shield_center". Troops keep their sheet pixels: only the shield and a GUARD_DILATE px rim
## around it are replaced by what the components paint under it.
static func guard_layers(unit: Dictionary, troop_id := "", variant := 0) -> Dictionary:
	var shield_kind = unit.look.get("shield")
	if shield_kind == null or String(shield_kind) == "":
		return {}
	# Heraldic Dominion figures carry their own rows: the figure without the shield and the shield.
	if not troop_id.is_empty() and DominionHeraldic.supports(troop_id, _faction(unit)):
		var geometry: Dictionary = DominionHeraldic.geometry(troop_id)
		# A heraldic rider asked for on foot (cut from his horse) keeps his shield on.
		if not geometry.has("shield_center") or (DominionHeraldic.is_cavalry(troop_id) and not unit.get("mounted", false)):
			return {}
		var banner := _player_banner if _faction(unit) == "player" else -1
		return {"layers": [[DominionHeraldic.sprite(troop_id, "bare", variant, banner), Vector2.ZERO]],
			"shield": DominionHeraldic.sprite(troop_id, "shield", variant, banner), "shield_origin": Vector2.ZERO,
			"shield_center": Vector2(geometry.shield_center[0], geometry.shield_center[1])}
	var entry := layers_for(unit, troop_id, variant)
	if entry.is_empty() or entry.get("body") == null:
		return {}
	var key: int = (entry.body as Texture2D).get_instance_id()
	if _guards.has(key):
		return _guards[key]
	var parts := {}
	if entry.has("guard_source"):
		parts = _guard_parts(entry.guard_source[0], entry.guard_source[1])
	elif entry.body is AtlasTexture and entry.get("head") is AtlasTexture:
		var body := _region_image(entry.body)
		var size := body.get_size()
		var mounted: bool = unit.get("mounted", false)
		var faction := _faction(unit)
		var prefix := "|" + faction + "|"
		var offset := Vector2i(2, 26) if mounted else Vector2i(2, 5)
		var rider := offset + (Vector2i(4, 2) if mounted else Vector2i.ZERO)
		var horse = unit.look.get("horse")
		var under := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		_stamp(under, "horse" + prefix + String(horse if horse else "bay") if mounted else "base|" + faction, offset)
		_stamp(under, "torso" + prefix + String(unit.look.get("armor", "tunic")), rider)
		var head := _region_image(entry.head)
		under.blend_rect(head, Rect2i(Vector2i.ZERO, head.get_size()), Vector2i.ZERO)
		var shield := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		_stamp(shield, "shield" + prefix + String(shield_kind), rider)
		var used := shield.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var area := used.grow(GUARD_DILATE).intersection(Rect2i(Vector2i.ZERO, size))
			var mask := Image.create(area.size.x, area.size.y, false, Image.FORMAT_RGBA8)
			for dy in range(-GUARD_DILATE, GUARD_DILATE + 1):
				for dx in range(-GUARD_DILATE, GUARD_DILATE + 1):
					if absi(dx) + absi(dy) <= GUARD_DILATE:
						mask.blend_rect(shield, area, Vector2i(dx, dy))
			body.blit_rect_mask(under.get_region(area), mask, Rect2i(Vector2i.ZERO, area.size), area.position)
			parts = _guard_parts(body, shield)
	if not _batching:
		_sheet_images.clear()
	_guards[key] = parts
	return parts

static func _guard_parts(bare: Image, shield: Image) -> Dictionary:
	var used := shield.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return {}
	var rect := used.grow(GUARD_PAD).intersection(Rect2i(Vector2i.ZERO, shield.get_size()))
	return {"layers": [[ImageTexture.create_from_image(bare), Vector2.ZERO]],
		"shield": ImageTexture.create_from_image(shield.get_region(rect)), "shield_origin": Vector2(rect.position),
		"shield_center": Vector2(used.position) + Vector2(used.size) * 0.5}

## Batch guard_layers calls while a battle prepares: each troop sheet is read once, then dropped.
static func begin_batch() -> void:
	_batching = true

static func end_batch() -> void:
	_batching = false
	_sheet_images.clear()

## Pixels of one cell of a troop sheet (a fresh copy).
static func _region_image(texture: AtlasTexture) -> Image:
	var key := texture.atlas.get_instance_id()
	if not _sheet_images.has(key):
		var image := texture.atlas.get_image()
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		_sheet_images[key] = image
	return (_sheet_images[key] as Image).get_region(Rect2i(texture.region))

## Draw the fallen mount without its rider for a severed-rider corpse.
static func mount_corpse(unit: Dictionary, size: Vector2i, troop_id := "", variant := 0) -> Image:
	if (unit.get("hero", false) or unit.get("companion", false)) and HeroHeraldic.supports(unit.look) and size == HeroHeraldic.MOUNTED_FRAME:
		var coat := DominionHeraldic.horse(String(unit.look.get("horse", "bay")))
		coat.convert(Image.FORMAT_RGBA8)
		return coat
	if DominionHeraldic.is_cavalry(troop_id) and DominionHeraldic.supports(troop_id, _faction(unit)):
		# The faction's own horse when its atlas carries one, otherwise the shared coat. Variant pages
		# may carry another coat, so the fallen horse keeps the rider's variant.
		var own := DominionHeraldic.sprite(troop_id, DominionHeraldic.MOUNT_PART, variant, _player_banner if _faction(unit) == "player" else -1)
		var horse: Image = own.get_image() if own != null else DominionHeraldic.horse(String(unit.look.get("horse", "bay")))
		horse.convert(Image.FORMAT_RGBA8)
		if horse.get_size() == size: return horse
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var faction: String = unit.faction
	if not MANIFEST.crests.has(faction): faction = "nord" if unit.side == 0 else "emp"
	_stamp(image, "horse_corpse|%s|%s" % [faction, unit.look.get("horse", "bay")], Vector2i(2, 26))
	return image

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
	if DominionHeraldic.is_cavalry(troop) and DominionHeraldic.supports(troop, faction):
		var rider: Dictionary = DominionHeraldic.geometry(troop)
		entry.anchor = DominionHeraldic.CAVALRY_ANCHOR
		entry.pivot = Vector2(rider.grip[0], rider.grip[1])
		entry.head_center = Vector2(rider.center[0], rider.center[1])
		entry.neck_center = Vector2(rider.neck[0], rider.neck[1])
		if not mounted:
			# The rider on his own (cut from the saddle): same frame and coordinates, no horse.
			var alone := sprite(troop, faction, DominionHeraldic.RIDER_PART, variant)
			entry.body = alone
			entry.corpse = alone
			entry.portrait = alone
		return entry
	if DominionHeraldic.supports(troop, faction):
		entry.anchor = Vector2(76, 158)
		entry.pivot = DominionHeraldic.pivot(troop, look.get("weapon"))
		var head_geometry: Dictionary = DominionHeraldic.geometry(troop)
		entry.head_center = Vector2(head_geometry.center[0], head_geometry.center[1])
		entry.neck_center = Vector2(head_geometry.neck[0], head_geometry.neck[1])
		# A presentation-only pose key; the gameplay weapon remains xbow.
		if look.get("weapon") == "xbow": entry.weapon_kind = "heraldic_xbow"
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
		if faction == "player": atlas.atlas = _banner_sheet(atlas.atlas, "settlements")
		atlas.filter_clip = true
		atlas.region = Rect2(r[0], r[1], r[2], r[3])
		_cache[key] = atlas
	return _cache[key]

static func item_icon(id: String) -> Texture2D:
	var key: String = MANIFEST.items.get(id, "bag")
	var path := AssetPaths.path("item_%s" % key)
	return load(path) if not path.is_empty() and ResourceLoader.exists(path) else preload("res://apps/godot/visuals/assets/icon_bag.svg")

static func sprite(troop: String, faction := "player", part := "portrait", variant := 0) -> Texture2D:
	if DominionHeraldic.supports(troop, faction):
		return DominionHeraldic.sprite(troop, part, variant, _player_banner if faction == "player" else -1)
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
		if key.ends_with("|player") and part != "flash":
			atlas.atlas = _banner_sheet(atlas.atlas, "%s_v%d" % ["wpn" if part == "weapon" else part, clampi(variant, 0, 3)])
		atlas.filter_clip = true
		atlas.region = Rect2(rect[0], rect[1], rect[2], rect[3])
		_cache[cache_key] = atlas
	return _cache[cache_key]

static func crest(faction: String) -> Texture2D:
	var key := "banner_%d_crest" % _player_banner if faction == "player" and _player_banner > 0 else "crest_%s" % faction
	var path := AssetPaths.path(key)
	return load(path) if not path.is_empty() and ResourceLoader.exists(path) else null

static func portrait_control(troop: String, faction := "player", height := 68.0) -> TextureRect:
	var image := TextureRect.new()
	image.texture = sprite(troop, faction)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(64, height)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image
