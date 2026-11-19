extends RefCounted
## Heraldic troop skins (Dominion, Nordmark, Empire, Khanate) share the existing atlas/pose contract, including hired troops.
## Each faction brings foot atlases (152×176 frames) and cavalry atlases (240×244, one more row).
const IDS := ["d1", "d2", "d3", "d2s", "d3s", "d2x", "d3x"]
## Mounted troops: a heraldic horse carrying a rider built from the same kind of parts.
const CAVALRY_IDS := ["d2c", "d3c"]
const NORD_IDS := ["n1", "n2", "n3", "n2s", "n2a", "n3a"]
const NORD_CAVALRY_IDS := ["n3c"]
const EMP_IDS := ["e1", "e2", "e3", "e2s", "e3s", "e2a", "e3a"]
const EMP_CAVALRY_IDS := ["e3c"]
const KHAN_IDS := ["k1", "k2", "k2a"]
const KHAN_CAVALRY_IDS := ["k2c", "k3h", "k3c"]
const PARTS := ["body", "weapon", "portrait", "headless", "head", "flash", "corpse", "corpse_headless"]
## Extra rows after PARTS for the shield block: the figure without its painted shield, and the shield.
const GUARD_PARTS := ["bare", "shield"]
## Cavalry only, after GUARD_PARTS: the rider with his weapon and without the horse.
const RIDER_PART := "rider"
## Cavalry of newer factions, after RIDER_PART: the horse alone (the faction's own caparison).
const MOUNT_PART := "mount"
const PAGES := [
	preload("res://apps/godot/visuals/assets/dominion_heraldic_0.png"),
	preload("res://apps/godot/visuals/assets/dominion_heraldic_1.png"),
	preload("res://apps/godot/visuals/assets/dominion_heraldic_2.png"),
	preload("res://apps/godot/visuals/assets/dominion_heraldic_3.png"),
]
const CAVALRY_PAGES := [
	preload("res://apps/godot/visuals/assets/dominion_heraldic_cavalry_0.png"),
	preload("res://apps/godot/visuals/assets/dominion_heraldic_cavalry_1.png"),
	preload("res://apps/godot/visuals/assets/dominion_heraldic_cavalry_2.png"),
	preload("res://apps/godot/visuals/assets/dominion_heraldic_cavalry_3.png"),
]
const NORD_PAGES := [
	preload("res://apps/godot/visuals/assets/nord_heraldic_0.png"),
	preload("res://apps/godot/visuals/assets/nord_heraldic_1.png"),
	preload("res://apps/godot/visuals/assets/nord_heraldic_2.png"),
	preload("res://apps/godot/visuals/assets/nord_heraldic_3.png"),
]
const NORD_CAVALRY_PAGES := [
	preload("res://apps/godot/visuals/assets/nord_heraldic_cavalry_0.png"),
	preload("res://apps/godot/visuals/assets/nord_heraldic_cavalry_1.png"),
	preload("res://apps/godot/visuals/assets/nord_heraldic_cavalry_2.png"),
	preload("res://apps/godot/visuals/assets/nord_heraldic_cavalry_3.png"),
]
const EMP_PAGES := [
	preload("res://apps/godot/visuals/assets/emp_heraldic_0.png"),
	preload("res://apps/godot/visuals/assets/emp_heraldic_1.png"),
	preload("res://apps/godot/visuals/assets/emp_heraldic_2.png"),
	preload("res://apps/godot/visuals/assets/emp_heraldic_3.png"),
]
const EMP_CAVALRY_PAGES := [
	preload("res://apps/godot/visuals/assets/emp_heraldic_cavalry_0.png"),
	preload("res://apps/godot/visuals/assets/emp_heraldic_cavalry_1.png"),
	preload("res://apps/godot/visuals/assets/emp_heraldic_cavalry_2.png"),
	preload("res://apps/godot/visuals/assets/emp_heraldic_cavalry_3.png"),
]
const KHAN_PAGES := [
	preload("res://apps/godot/visuals/assets/khan_heraldic_0.png"),
	preload("res://apps/godot/visuals/assets/khan_heraldic_1.png"),
	preload("res://apps/godot/visuals/assets/khan_heraldic_2.png"),
	preload("res://apps/godot/visuals/assets/khan_heraldic_3.png"),
]
const KHAN_CAVALRY_PAGES := [
	preload("res://apps/godot/visuals/assets/khan_heraldic_cavalry_0.png"),
	preload("res://apps/godot/visuals/assets/khan_heraldic_cavalry_1.png"),
	preload("res://apps/godot/visuals/assets/khan_heraldic_cavalry_2.png"),
	preload("res://apps/godot/visuals/assets/khan_heraldic_cavalry_3.png"),
]
## The seven coats as single 240×244 frames, in this order (shared by every faction).
const HORSES = preload("res://apps/godot/visuals/assets/dominion_heraldic_horses.png")
const HORSE_COATS := ["bay", "chestnut", "dun", "black", "grey", "barded", "bone"]
const FRAME_SIZE := Vector2(152, 176)
## Same box and ground anchor as the previous mounted sheets, so battle placement is unchanged.
const CAVALRY_FRAME_SIZE := Vector2(240, 244)
const CAVALRY_ANCHOR := Vector2(112, 264)
const HEADS = preload("res://apps/godot/visuals/dominion_heraldic_heads.gd").DATA
const CAVALRY = preload("res://apps/godot/visuals/dominion_heraldic_cavalry_geometry.gd").DATA
const NORD = preload("res://apps/godot/visuals/nord_heraldic_geometry.gd").DATA
const EMP = preload("res://apps/godot/visuals/emp_heraldic_geometry.gd").DATA
const KHAN = preload("res://apps/godot/visuals/khan_heraldic_geometry.gd").DATA
## Dominion foot figures predate the stored grips; newer factions record theirs in the geometry.
const GRIPS := {"axe": Vector2(115, 116), "halberd": Vector2(118, 116), "xbow": Vector2(96, 128)}
const BANNERS = preload("res://apps/godot/visuals/assets/banner_definitions.gd").DATA
## Banner dye per faction: hue range of the faction cloth turned into the banner colour, whether the
## dark trim follows the banner's second colour, rows left undyed and the line above which a foot
## frame (cavalry: + 23 px) is left as drawn.
const FACTIONS := {
	"dom": {"foot": IDS, "cavalry": CAVALRY_IDS, "pages": PAGES, "cavalry_pages": CAVALRY_PAGES,
		"hue": [0.095, 0.155], "trim": true, "skip_rows": [1, 4, 5], "neck_line": 88},
	# Nordmark blue also dyes hoods, caps and the severed head, so the whole figure follows the banner.
	"nord": {"foot": NORD_IDS, "cavalry": NORD_CAVALRY_IDS, "pages": NORD_PAGES, "cavalry_pages": NORD_CAVALRY_PAGES,
		# The navy outline shares the cloth's hue: only brighter pixels are cloth.
		"hue": [0.52, 0.68], "min_value": 0.24, "trim": false, "skip_rows": [1, 5], "neck_line": 0, "mount_row": true},
	# Imperial crimson wraps around hue 0 (low > high); the gold trim stays gold. Blood has the same
	# hue, so the cut neck (headless, head and headless corpse rows) is left as drawn: "spare_wound".
	"emp": {"foot": EMP_IDS, "cavalry": EMP_CAVALRY_IDS, "pages": EMP_PAGES, "cavalry_pages": EMP_CAVALRY_PAGES,
		"hue": [0.94, 0.03], "trim": false, "skip_rows": [1, 5], "neck_line": 0, "mount_row": true, "spare_wound": true},
	# Khanate teal; gold, fur and felt keep their colours.
	"khan": {"foot": KHAN_IDS, "cavalry": KHAN_CAVALRY_IDS, "pages": KHAN_PAGES, "cavalry_pages": KHAN_CAVALRY_PAGES,
		"hue": [0.42, 0.53], "trim": false, "skip_rows": [1, 5], "neck_line": 0, "mount_row": true},
}
static var _sprites := {}
static var _banner_pages := {}
static var _horses := {}

## The faction whose heraldic skins draw this troop, or "".
static func home_of(troop: String) -> String:
	for key: String in FACTIONS:
		if troop in FACTIONS[key].foot or troop in FACTIONS[key].cavalry: return key
	return ""

static func supports(troop: String, faction: String) -> bool:
	var home := home_of(troop)
	return home != "" and faction in [home, "player"]

static func is_cavalry(troop: String) -> bool:
	var home := home_of(troop)
	return home != "" and troop in FACTIONS[home].cavalry

## Head centre, neck joint and shield centre (frame pixels); newer figures also store their grip.
static func geometry(troop: String) -> Dictionary:
	match home_of(troop):
		"dom": return CAVALRY.get(troop, {}) if is_cavalry(troop) else HEADS.get(troop, {})
		"nord": return NORD.get(troop, {})
		"emp": return EMP.get(troop, {})
		"khan": return KHAN.get(troop, {})
	return {}

## Where the weapon turns: the glove holding it.
static func pivot(troop: String, weapon: Variant) -> Vector2:
	var grip: Array = geometry(troop).get("grip", [])
	if grip.size() == 2: return Vector2(grip[0], grip[1])
	return GRIPS.get(weapon, Vector2(125, 116))

## The four complexion variants of a troop's atlas.
static func pages(troop: String) -> Array:
	var home := home_of(troop)
	if home == "": return []
	return FACTIONS[home].cavalry_pages if is_cavalry(troop) else FACTIONS[home].pages

static func sprite(troop: String, part: String, variant: int, banner := -1) -> Texture2D:
	var home := home_of(troop)
	if home == "": return null
	var cavalry := is_cavalry(troop)
	var ids: Array = FACTIONS[home].cavalry if cavalry else FACTIONS[home].foot
	var column := ids.find(troop)
	var row := PARTS.find(part)
	if row < 0 and GUARD_PARTS.has(part): row = PARTS.size() + GUARD_PARTS.find(part)
	if row < 0 and cavalry and part == RIDER_PART: row = PARTS.size() + GUARD_PARTS.size()
	if row < 0 and cavalry and part == MOUNT_PART and FACTIONS[home].get("mount_row", false): row = PARTS.size() + GUARD_PARTS.size() + 1
	if column < 0 or row < 0: return null
	variant = clampi(variant, 0, 3)
	var key := "%s|%s|%d|%d" % [troop, part, variant, banner]
	if not _sprites.has(key):
		var frame: Vector2 = CAVALRY_FRAME_SIZE if cavalry else FRAME_SIZE
		var texture := AtlasTexture.new()
		texture.atlas = _page(variant, banner, home, cavalry)
		texture.region = Rect2(Vector2(column, row) * frame, frame)
		texture.filter_clip = true
		_sprites[key] = texture
	return _sprites[key]

## The mount alone for a rider thrown off or cut down (same frame as the cavalry sheet).
static func horse(coat: String) -> Image:
	var index := maxi(0, HORSE_COATS.find(coat))
	if not _horses.has(index):
		var image: Image = HORSES.get_image()
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		_horses[index] = image.get_region(Rect2i(Vector2i(int(CAVALRY_FRAME_SIZE.x) * index, 0), Vector2i(CAVALRY_FRAME_SIZE)))
	return (_horses[index] as Image).duplicate() as Image

static func _page(variant: int, banner: int, home: String, cavalry: bool) -> Texture2D:
	var spec: Dictionary = FACTIONS[home]
	var source: Array = spec.cavalry_pages if cavalry else spec.pages
	if banner < 0: return source[variant]
	banner = clampi(banner, 0, BANNERS.size() - 1)
	var key := "%s|%d|%d|%s" % [home, variant, banner, cavalry]
	if not _banner_pages.has(key):
		var frame: Vector2 = CAVALRY_FRAME_SIZE if cavalry else FRAME_SIZE
		# Faces and helmets sit above this line in every frame (the rider rides 23 px lower).
		var neck_line: int = spec.neck_line + (23 if cavalry and spec.neck_line > 0 else 0)
		var skip_rows: Array = spec.skip_rows
		var hue_low: float = spec.hue[0]
		var hue_high: float = spec.hue[1]
		var min_value: float = spec.get("min_value", 0.0)
		var spare_wound: bool = spec.get("spare_wound", false)
		var neck := Vector2(80, 101) if cavalry else Vector2(76, 78)
		var image: Image = source[variant].get_image()
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		var bytes := image.get_data()
		var primary := Color(BANNERS[banner].c1)
		var trim := Color(BANNERS[banner].c2)
		for y in image.get_height():
			var row := y / int(frame.y)
			# Dye cloth/shields below the neck; preserve faces, steel and weapon layers.
			if row in skip_rows or y % int(frame.y) < neck_line: continue
			var near_neck: bool = spare_wound and row in [3, 4, 7] and absf(y % int(frame.y) - neck.y) < 16
			for x in image.get_width():
				var p := (y * image.get_width() + x) * 4
				if bytes[p + 3] == 0: continue
				if near_neck and absf(x % int(frame.x) - neck.x) < 32: continue
				var source_colour := Color8(bytes[p], bytes[p + 1], bytes[p + 2], bytes[p + 3])
				var replacement := source_colour
				var in_hue := (source_colour.h > hue_low and source_colour.h < hue_high) if hue_low < hue_high else (source_colour.h > hue_low or source_colour.h < hue_high)
				if in_hue and source_colour.s > 0.35 and source_colour.v > min_value:
					replacement = primary * clampf(source_colour.v / 0.68, 0.45, 1.35)
				elif spec.trim and source_colour.h > 0.08 and source_colour.h < 0.20 and source_colour.s < 0.32 and source_colour.v < 0.32:
					replacement = trim * clampf(source_colour.v / 0.22, 0.55, 1.2)
				bytes[p] = roundi(clampf(replacement.r, 0, 1) * 255)
				bytes[p + 1] = roundi(clampf(replacement.g, 0, 1) * 255)
				bytes[p + 2] = roundi(clampf(replacement.b, 0, 1) * 255)
		var dyed := Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, bytes)
		# Gloves and weapons keep their material colours in portraits as well as in battle.
		var height := int(frame.y)
		var full_row := Rect2i(0, 0, image.get_width(), height)
		var weapon_row := image.get_region(Rect2i(0, height, image.get_width(), height))
		for target in [2, 6, 7]:
			var body_row := 3 if target == 7 else 0
			dyed.blit_rect(dyed.get_region(Rect2i(0, body_row * height, image.get_width(), height)), full_row, Vector2i(0, target * height))
			dyed.blend_rect(weapon_row, full_row, Vector2i(0, target * height))
		_banner_pages[key] = ImageTexture.create_from_image(dyed)
	return _banner_pages[key]
