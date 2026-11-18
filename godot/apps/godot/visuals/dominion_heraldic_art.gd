extends RefCounted
## Dominion troop skins share the existing atlas/pose contract, including hired troops.
const IDS := ["d1", "d2", "d3", "d2s", "d3s", "d2x", "d3x"]
const PARTS := ["body", "weapon", "portrait", "headless", "head", "flash", "corpse", "corpse_headless"]
## Extra rows after PARTS for the shield block: the figure without its painted shield, and the shield.
const GUARD_PARTS := ["bare", "shield"]
const PAGES := [
	preload("res://apps/godot/visuals/assets/dominion_heraldic_0.png"),
	preload("res://apps/godot/visuals/assets/dominion_heraldic_1.png"),
	preload("res://apps/godot/visuals/assets/dominion_heraldic_2.png"),
	preload("res://apps/godot/visuals/assets/dominion_heraldic_3.png"),
]
const FRAME_SIZE := Vector2(152, 176)
const HEADS = preload("res://apps/godot/visuals/dominion_heraldic_heads.gd").DATA
const GRIPS := {"axe": Vector2(115, 116), "halberd": Vector2(118, 116), "xbow": Vector2(96, 128)}
const BANNERS = preload("res://apps/godot/visuals/assets/banner_definitions.gd").DATA
static var _sprites := {}
static var _banner_pages := {}

static func supports(troop: String, faction: String) -> bool:
	return troop in IDS and faction in ["dom", "player"]

static func sprite(troop: String, part: String, variant: int, banner := -1) -> Texture2D:
	var column := IDS.find(troop)
	var row := PARTS.find(part)
	if row < 0 and GUARD_PARTS.has(part): row = PARTS.size() + GUARD_PARTS.find(part)
	if column < 0 or row < 0: return null
	variant = clampi(variant, 0, 3)
	var key := "%s|%s|%d|%d" % [troop, part, variant, banner]
	if not _sprites.has(key):
		var texture := AtlasTexture.new()
		texture.atlas = _page(variant, banner)
		texture.region = Rect2(Vector2(column, row) * FRAME_SIZE, FRAME_SIZE)
		texture.filter_clip = true
		_sprites[key] = texture
	return _sprites[key]

static func _page(variant: int, banner: int) -> Texture2D:
	if banner < 0: return PAGES[variant]
	banner = clampi(banner, 0, BANNERS.size() - 1)
	var key := "%d|%d" % [variant, banner]
	if not _banner_pages.has(key):
		var image: Image = PAGES[variant].get_image()
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		var bytes := image.get_data()
		var primary := Color(BANNERS[banner].c1)
		var trim := Color(BANNERS[banner].c2)
		for y in image.get_height():
			var row := y / int(FRAME_SIZE.y)
			# Dye cloth/shields below the neck; preserve faces, steel and weapon layers.
			if row in [1, 4, 5] or y % int(FRAME_SIZE.y) < 88: continue
			for x in image.get_width():
				var p := (y * image.get_width() + x) * 4
				if bytes[p + 3] == 0: continue
				var source := Color8(bytes[p], bytes[p + 1], bytes[p + 2], bytes[p + 3])
				var replacement := source
				if source.h > 0.095 and source.h < 0.155 and source.s > 0.35:
					replacement = primary * clampf(source.v / 0.68, 0.45, 1.35)
				elif source.h > 0.08 and source.h < 0.20 and source.s < 0.32 and source.v < 0.32:
					replacement = trim * clampf(source.v / 0.22, 0.55, 1.2)
				bytes[p] = roundi(clampf(replacement.r, 0, 1) * 255)
				bytes[p + 1] = roundi(clampf(replacement.g, 0, 1) * 255)
				bytes[p + 2] = roundi(clampf(replacement.b, 0, 1) * 255)
		var dyed := Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, bytes)
		# Gloves and weapons keep their material colours in portraits as well as in battle.
		var full_row := Rect2i(0, 0, image.get_width(), int(FRAME_SIZE.y))
		var weapon_row := image.get_region(Rect2i(0, int(FRAME_SIZE.y), image.get_width(), int(FRAME_SIZE.y)))
		for target in [2, 6, 7]:
			var body_row := 3 if target == 7 else 0
			dyed.blit_rect(dyed.get_region(Rect2i(0, body_row * int(FRAME_SIZE.y), image.get_width(), int(FRAME_SIZE.y))), full_row, Vector2i(0, target * int(FRAME_SIZE.y)))
			dyed.blend_rect(weapon_row, full_row, Vector2i(0, target * int(FRAME_SIZE.y)))
		_banner_pages[key] = ImageTexture.create_from_image(dyed)
	return _banner_pages[key]
