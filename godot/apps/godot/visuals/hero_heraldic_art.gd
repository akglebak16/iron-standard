extends RefCounted
## The player's hero and companions in the heraldic style (#232): figures put together from parts
## drawn in key colours (tools/battle/render_heraldic_hero.cjs) and repainted for the chosen banner,
## skin and hair. Same layers and keys as OriginalArt.compose, so battle, campaign and the start
## screen use them unchanged. Each look is built once and kept.
const DominionHeraldic = preload("res://apps/godot/visuals/dominion_heraldic_art.gd")
const PARTS = preload("res://apps/godot/visuals/assets/hero_heraldic_parts.png")
const MOUNTED = preload("res://apps/godot/visuals/assets/hero_heraldic_mounted.png")
const GEO = preload("res://apps/godot/visuals/hero_heraldic_geometry.gd").DATA
const FRAME := Vector2i(152, 176)
const MOUNTED_FRAME := Vector2i(240, 244)
const FOOT_ANCHOR := Vector2(76, 158)
## Reference brightness of each key colour as drawn: a pixel keeps its shade relative to it.
const RED_V := 0.776
const GREEN_V := 0.49
const SKIN_V := 0.886
const HAIR_V := 0.784
const STEEL_ARMORS := ["mailfur", "mail", "mailtab", "scale", "goldscale", "lamellar", "goldlam", "plate"]
## Weapons without a drawing of their own borrow the nearest one.
const WEAPON_ART := {"mace": "club"}
const SHIELD_ART := {"kite": "kite", "round": "round", "small": "small"}
const BEARDS := ["", "beard1", "beard2"]

static var _parts: Image
static var _mounted: Image
static var _cache := {}

## Heraldic parts exist for this look: living hero or companion gear the parts cover.
static func supports(look: Dictionary) -> bool:
	if String(look.get("undead", "")) != "": return false
	return GEO.frames.has("torso:" + String(look.get("armor", "tunic"))) and GEO.frames.has("head:" + String(look.get("helm", "none")))

static func clear_cache() -> void:
	_cache.clear()

## Layers of a figure: face from FaceVariant, banner as {c1, c2} colours, mounted when look.horse is set.
static func compose(look: Dictionary, face: Dictionary, banner: Dictionary) -> Dictionary:
	var key := str([look, face, banner])
	if _cache.has(key): return _cache[key]
	var mounted: bool = look.get("horse") != null and String(look.get("horse")) != ""
	var size := MOUNTED_FRAME if mounted else FRAME
	var rider := Vector2i(int(GEO.rider[0]), int(GEO.rider[1])) if mounted else Vector2i.ZERO
	var armor := String(look.get("armor", "tunic"))
	var helm := String(look.get("helm", "none"))
	var c1 := Color(String(banner.get("c1", "#c08a2e")))
	var c2 := Color(String(banner.get("c2", "#241a10")))
	var skin := Color(String(face.get("skin", "#e2b48c")))
	var hair := Color(String(face.get("hair", "#4a3020")))

	var torso := _part("torso:" + armor)
	_dye_cloth(torso, c1, c2)
	var head_part := _part("head:" + helm)
	_dye(head_part, c1, c2, skin, null)
	if helm == "none" and not bool(face.get("bald", false)):
		_overlay(head_part, "hair:hair", hair)
	var open_face: bool = helm in GEO.open_face
	var beard := int(face.get("beard", 0))
	if open_face and beard > 0 and beard < BEARDS.size():
		_overlay(head_part, "hair:" + BEARDS[beard], hair)
	elif open_face and int(face.get("stache", 0)) == 1:
		_overlay(head_part, "hair:stache", hair)
	if open_face and bool(face.get("scar", false)):
		_scar(head_part, skin)

	var horse: Image = null
	if mounted:
		horse = DominionHeraldic.horse(String(look.horse))
		horse.convert(Image.FORMAT_RGBA8)
	var head_shift := rider + Vector2i(0, int(GEO.torso_head_dy.get(armor, 0)))
	var head := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	head.blend_rect(head_part, Rect2i(Vector2i.ZERO, FRAME), head_shift)
	var under := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	if horse != null: under.blend_rect(horse, Rect2i(Vector2i.ZERO, horse.get_size()), Vector2i.ZERO)
	under.blend_rect(torso, Rect2i(Vector2i.ZERO, FRAME), rider)

	var bare := under.duplicate() as Image
	bare.blend_rect(head, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	var headless := under.duplicate() as Image
	headless.blend_rect(_part("wound"), Rect2i(Vector2i.ZERO, FRAME), rider)
	var body := bare.duplicate() as Image
	var shield_layer: Image = null
	var shield_kind = look.get("shield")
	var shield_center := Vector2.ZERO
	if shield_kind != null and String(shield_kind) != "" and String(shield_kind) != "none":
		var art: String = SHIELD_ART.get(String(shield_kind), "round")
		var picture := _part("shield:" + art)
		_dye_cloth(picture, c1, c2)
		shield_layer = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		shield_layer.blend_rect(picture, Rect2i(Vector2i.ZERO, FRAME), rider)
		body.blend_rect(shield_layer, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
		headless.blend_rect(shield_layer, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
		shield_center = Vector2(GEO.shield_center[art][0], GEO.shield_center[art][1]) + Vector2(rider)

	var weapon := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var pivot := Vector2(GEO.grip.sword[0], GEO.grip.sword[1]) + Vector2(rider)
	var kind = look.get("weapon")
	if kind != null and String(kind) != "":
		var art_kind: String = WEAPON_ART.get(String(kind), String(kind))
		if not GEO.grip.has(art_kind): art_kind = "sword"
		var name := "weapon:%s:%s" % [art_kind, "steel" if armor in STEEL_ARMORS else "leather"]
		if mounted and GEO.mounted_frames.has(name):
			weapon.blend_rect(_mounted_part(name), Rect2i(Vector2i.ZERO, MOUNTED_FRAME), Vector2i.ZERO)
			pivot = Vector2(GEO.mounted_grip[art_kind][0], GEO.mounted_grip[art_kind][1])
		else:
			weapon.blend_rect(_part(name), Rect2i(Vector2i.ZERO, FRAME), rider)
			pivot = Vector2(GEO.grip[art_kind][0], GEO.grip[art_kind][1]) + Vector2(rider)

	var portrait := body.duplicate() as Image
	portrait.blend_rect(weapon, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	var corpse_headless := headless.duplicate() as Image
	corpse_headless.blend_rect(weapon, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	var flash := portrait.duplicate() as Image
	var bytes := flash.get_data()
	for i in range(0, bytes.size(), 4):
		bytes[i] = 255
		bytes[i + 1] = 255
		bytes[i + 2] = 255
	flash.set_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
	var result := {"body": ImageTexture.create_from_image(body), "headless": ImageTexture.create_from_image(headless),
		"weapon": ImageTexture.create_from_image(weapon), "head": ImageTexture.create_from_image(head),
		"flash": ImageTexture.create_from_image(flash), "corpse": ImageTexture.create_from_image(portrait),
		"corpse_headless": ImageTexture.create_from_image(corpse_headless),
		"portrait": ImageTexture.create_from_image(portrait), "weapon_kind": kind,
		"anchor": DominionHeraldic.CAVALRY_ANCHOR if mounted else FOOT_ANCHOR,
		"head_center": Vector2(GEO.head_center[0], GEO.head_center[1]) + Vector2(head_shift),
		"neck_center": Vector2(GEO.neck[0], GEO.neck[1]) + Vector2(head_shift),
		"pivot": pivot, "scale": 0.31}
	if shield_layer != null:
		# Kept as images: the battle splits the shield off only for figures that fight.
		result.guard_source = [bare, shield_layer]
		result.shield_center = shield_center
	_cache[key] = result
	return result

static func _part(name: String) -> Image:
	if _parts == null:
		_parts = PARTS.get_image()
		if _parts.is_compressed(): _parts.decompress()
		_parts.convert(Image.FORMAT_RGBA8)
	var at: Array = GEO.frames[name]
	return _parts.get_region(Rect2i(Vector2i(int(at[0]), int(at[1])), FRAME))

static func _mounted_part(name: String) -> Image:
	if _mounted == null:
		_mounted = MOUNTED.get_image()
		if _mounted.is_compressed(): _mounted.decompress()
		_mounted.convert(Image.FORMAT_RGBA8)
	var at: Array = GEO.mounted_frames[name]
	return _mounted.get_region(Rect2i(Vector2i(int(at[0]), int(at[1])), MOUNTED_FRAME))

## Hair, a beard or a moustache in the chosen hair colour, laid over the head.
static func _overlay(head: Image, name: String, hair: Color) -> void:
	var layer := _part(name)
	_dye(layer, null, null, null, hair)
	head.blend_rect(layer, Rect2i(Vector2i.ZERO, FRAME), Vector2i.ZERO)

## A pale healed cut across the right cheek.
static func _scar(head: Image, skin: Color) -> void:
	var from := Vector2(GEO.scar[0][0], GEO.scar[0][1])
	var to := Vector2(GEO.scar[1][0], GEO.scar[1][1])
	var mark := skin.darkened(0.35)
	var steps := int(ceil(from.distance_to(to)))
	for i in steps + 1:
		var p := Vector2i(from.lerp(to, float(i) / maxf(1.0, steps)).round())
		if head.get_pixelv(p).a > 0.5: head.set_pixelv(p, mark)

static func _dye_cloth(image: Image, c1: Color, c2: Color) -> void:
	_dye(image, c1, c2, null, null)

## Repaint the key colours inside the drawn area, keeping each pixel's shade.
static func _dye(image: Image, c1, c2, skin, hair) -> void:
	var used := image.get_used_rect()
	if used.size.x <= 0: return
	var width := image.get_width()
	var data := image.get_data()
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			var p := (y * width + x) * 4
			if data[p + 3] < 20: continue
			var color := Color8(data[p], data[p + 1], data[p + 2])
			var h := color.h
			var s := color.s
			var v := color.v
			var target = null
			var reference := 1.0
			if hair != null:
				if h > 0.55 and h < 0.7 and s > 0.4 and v > 0.18:
					target = hair
					reference = HAIR_V
			elif c1 != null and (h < 0.035 or h > 0.95) and s > 0.35 and v > 0.15:
				target = c1
				reference = RED_V
			elif c2 != null and h > 0.2 and h < 0.5 and s > 0.1 and v > 0.06:
				target = c2
				reference = GREEN_V
			elif skin != null and h > 0.04 and h < 0.11 and s > 0.18 and s < 0.56 and v > 0.62:
				target = skin
				reference = SKIN_V
			if target == null: continue
			var k := v / reference
			data[p] = clampi(roundi(target.r * 255.0 * k), 0, 255)
			data[p + 1] = clampi(roundi(target.g * 255.0 * k), 0, 255)
			data[p + 2] = clampi(roundi(target.b * 255.0 * k), 0, 255)
	image.set_data(width, image.get_height(), false, Image.FORMAT_RGBA8, data)
