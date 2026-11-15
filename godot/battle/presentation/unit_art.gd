extends RefCounted
const OriginalArt = preload("res://ui/original_art.gd")
## Procedural bust layers. SVG is rasterized once per appearance and palette.
const SIZE := Vector2(76, 88)
const PIVOT := Vector2(53, 52)
const ANCHOR := Vector2(37, 76)
const HEAD_CENTER := Vector2(36, 32)
const MOUNT_RIDER_RISE := 12.0
const SPRITE_SCALE := 0.43
const OUTLINE := "#251c16"
const STEEL := "#b9c4cb"
const WOOD := "#88623e"
const SKIN := {"skel": "#d8d0b8", "zombie": "#9aa58a"}
const DEFAULT_SKIN := "#c79568"
const ARMOR := {"mail": "#697476", "plate": "#89979e", "scale": "#81786b", "ribs": "#a49a85", "rags": "#657057"}
const HORSES := {"black": "#302824", "dun": "#b3945c", "grey": "#9c978d", "chestnut": "#8a4b22", "bone": "#cfc6ad"}
const PALETTES := {
	"nord": ["#2f5a85", "#dfe6ea"], "emp": ["#7d1f28", "#d8a838"],
	"khan": ["#1e6a5e", "#e6c868"], "kin": ["#5a3a92", "#f0e2a6"],
	"emi": ["#c4571f", "#f4e8c4"], "dom": ["#b58a28", "#2d2a22"],
	"pact": ["#dcd5c2", "#b3262e"], "bandit": ["#3b3a36", "#9a2f24"],
	"undead": ["#3f4636", "#a9b98e"], "player": ["#c08a2e", "#241a10"],
}
const LOOK_FIELDS := ["helm", "armor", "weapon", "shield", "horse", "undead"]

var _cache: Dictionary = {}

var _by_unit: Dictionary = {} # unit id -> cache entry; only the hero changes looks

func layers(unit: Dictionary, headless: bool = false) -> Dictionary:
	var uid = unit.get("id")
	var cacheable: bool = uid != null and not unit.get("hero", false)
	if cacheable:
		var known = _by_unit.get(uid)
		if known != null:
			if headless and not known.has("headless"):
				known.headless = _body(unit.look, _palette(unit), unit.mounted, true)
			return known
	var original := OriginalArt.layers_for(unit)
	if not original.is_empty():
		if cacheable:
			_by_unit[uid] = original
		return original
	var look: Dictionary = unit.look
	var palette := _palette(unit)
	var key := [palette[0], palette[1], unit.mounted]
	for field in LOOK_FIELDS:
		key.append(look.get(field))
	var cache_key := str(key)
	if not _cache.has(cache_key):
		_cache[cache_key] = {"body": _body(look, palette, unit.mounted, false), "weapon": _weapon(look.get("weapon")),
			"weapon_kind": look.get("weapon")}
	var entry: Dictionary = _cache[cache_key]
	if cacheable:
		_by_unit[uid] = entry
	if headless and not entry.has("headless"):
		entry.headless = _body(look, palette, unit.mounted, true)
	return entry

func detached_head(unit: Dictionary) -> Texture2D:
	var entry := layers(unit)
	if not entry.has("head"):
		entry.head = _texture(_head_shapes(unit.look, _palette(unit)))
	return entry.head

static func skin_color(unit: Dictionary) -> Color:
	return Color(SKIN.get(unit.look.get("undead"), DEFAULT_SKIN))

static func sleeve_color(unit: Dictionary) -> Color:
	return Color(_palette(unit)[0])

static func trim_color(unit: Dictionary) -> Color:
	return Color(_palette(unit)[1])

static func _palette(unit: Dictionary) -> Array:
	var fallback := "nord" if unit.side == 0 else "emp"
	var faction: String = "player" if unit.hero or unit.companion else unit.faction
	return PALETTES.get(faction, PALETTES[fallback])

static func _body(look: Dictionary, palette: Array, mounted: bool, headless: bool) -> Texture2D:
	var primary: String = palette[0]
	var trim: String = palette[1]
	var armor: String = ARMOR.get(look.get("armor"), primary)
	var shapes := ""
	if mounted:
		var coat: String = HORSES.get(look.get("horse"), "#6b4226")
		shapes += _path("M6 77 Q3 57 22 55 L46 56 Q54 48 58 39 L60 33 L63 38 Q71 41 74 52 L70 55 L63 52 L62 72 Q52 85 22 82 Z", coat)
		shapes += _path("M46 56 Q53 43 60 33 Q58 46 54 58 Z", OUTLINE)
		shapes += '<circle cx="65" cy="45" r="1.5" fill="%s"/>' % OUTLINE
		shapes += _path("M13 60 Q29 56 49 60 L44 78 L17 77 Z", primary, trim)
		shapes += '<g transform="translate(0 %s)">' % -MOUNT_RIDER_RISE
	shapes += _path("M12 72 Q12 51 25 46 L48 46 Q60 50 61 72 Q37 82 12 72 Z", armor)
	shapes += _armor_details(look.get("armor"))
	shapes += _path("M17 66 L52 65 L53 71 Q34 76 17 71 Z", WOOD)
	shapes += _path("M30 47 L30 65 L41 67 L45 47 Z", primary, trim)
	if not headless:
		shapes += _head_shapes(look, palette)
	var shield: Variant = look.get("shield")
	match shield:
		null, "", "none": pass
		"round", "small":
			var radius := 10 if shield == "round" else 7
			shapes += '<circle cx="21" cy="59" r="%d" fill="%s" stroke="%s" stroke-width="2"/><circle cx="21" cy="59" r="3" fill="%s"/>' % [radius, primary, trim, STEEL]
		_:
			shapes += _path("M10 49 Q20 45 32 49 L31 65 Q27 74 21 77 Q12 69 10 61 Z", primary, trim)
			shapes += '<path d="M21 49v20 M13 57h16" stroke="%s" stroke-width="2"/>' % trim
	if mounted:
		shapes += "</g>"
	return _texture(shapes)

static func _head_shapes(look: Dictionary, palette: Array) -> String:
	var primary: String = palette[0]
	var trim: String = palette[1]
	var skin: String = SKIN.get(look.get("undead"), DEFAULT_SKIN)
	var shapes := ""
	shapes += _path("M25 40 Q20 27 27 20 Q39 13 47 23 L50 35 L46 38 L45 46 Q34 51 25 40 Z", skin)
	shapes += '<path d="M38 33h5 M39 41h5" stroke="%s" stroke-width="1.6"/>' % OUTLINE
	var helm: Variant = look.get("helm", "cap")
	match helm:
		"none": shapes += _path("M24 32 Q20 19 35 17 Q45 17 46 24 L29 27 L28 34 Z", WOOD)
		"turban", "turbanm":
			shapes += _path("M20 31 Q18 20 26 17 Q36 10 48 19 Q54 23 51 31 Q35 27 23 35 Z", primary, trim)
			shapes += '<path d="M21 27Q35 18 49 25 M21 31Q35 23 50 28" fill="none" stroke="%s"/>' % trim
		"hood", "cap", "furcap":
			shapes += _path("M22 38 Q18 22 29 16 Q43 11 50 26 L50 29 L29 30 L27 42 Z", primary, trim)
		"kettle":
			shapes += _path("M23 28 Q23 15 36 15 Q47 16 49 28 L55 31 Q49 35 19 34 L17 31 Z", STEEL)
		"great", "greathelm":
			shapes += _path("M22 43 L23 18 L46 17 L51 44 L35 47 Z", STEEL)
			shapes += '<path d="M31 30h17 M42 36v5" stroke="%s" stroke-width="2"/>' % OUTLINE
		_:
			shapes += _path("M20 32 Q20 17 34 15 Q47 15 50 30 L45 31 L45 37 L41 37 L40 31 Z", STEEL)
	return shapes

static func _armor_details(kind: Variant) -> String:
	var detail := ""
	match kind:
		"mail", "scale":
			for row in 4:
				for column in 6:
					var x := 20 + column * 6 + (row % 2) * 3
					var y := 50 + row * 4
					detail += '<path d="M%d %dq2 3 4 0" fill="none" stroke="%s" stroke-opacity=".65"/>' % [x, y, OUTLINE]
		"plate":
			detail = '<path d="M18 54Q36 61 56 53 M17 60Q37 67 57 59" fill="none" stroke="%s"/><path d="M24 49Q37 54 48 49" fill="none" stroke="%s"/>' % [OUTLINE, STEEL]
		"ribs":
			detail = '<path d="M21 52Q37 60 51 51 M19 57Q36 66 54 56 M18 62Q37 70 55 61" fill="none" stroke="%s" stroke-width="2"/>' % STEEL
	return detail

static func _weapon(kind: Variant) -> Texture2D:
	var shapes := ""
	match kind:
		"bow":
			shapes = '<path d="M55 23 Q72 44 55 67" fill="none" stroke="%s" stroke-width="3"/><path d="M55 23v44" stroke="#ebdfce"/>' % WOOD
		"xbow":
			shapes = _path("M45 55 L68 49 L69 52 L46 59 Z", WOOD)
			shapes += '<path d="M59 38 Q74 46 65 62" fill="none" stroke="%s" stroke-width="3"/>' % STEEL
		"spear", "halberd", "lance", "throw":
			shapes = _path("M51 78 L58 15 L60 15 L54 78 Z", WOOD)
			shapes += _path("M58 17 L57 12 L62 4 L63 14 Z", STEEL)
			if kind == "halberd":
				shapes += _path("M59 16 L69 11 L70 27 L58 24 Z", STEEL)
		"axe", "mace", "club":
			shapes = _path("M51 72 L58 23 L62 24 L55 72 Z", WOOD)
			if kind != "club":
				shapes += _path("M58 23 Q72 17 71 35 L57 37 Z", STEEL)
		"sword", "sabre":
			shapes = _path("M55 48 L62 20 L67 15 L65 26 L60 49 Z", STEEL)
			shapes += _path("M51 48 L63 50 L63 53 L51 51 Z M55 51 L58 52 L56 63 L53 62 Z", WOOD)
		_:
			return null
	shapes += _path("M50 54 Q51 49 56 51 Q60 53 56 58 L51 58 Z", "#a47c56")
	return _texture(shapes)

static func _path(commands: String, fill: String, stroke: String = OUTLINE) -> String:
	return '<path d="%s" fill="%s" stroke="%s" stroke-width="1.5" stroke-linejoin="round"/>' % [commands, fill, stroke]

static func _texture(shapes: String) -> Texture2D:
	var image := Image.new()
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">%s</svg>' % [int(SIZE.x), int(SIZE.y), shapes]
	var error := image.load_svg_from_string(svg)
	if error != OK:
		push_error("Cannot rasterize unit art: " + error_string(error))
		return null
	return ImageTexture.create_from_image(image)
