extends RefCounted
## Procedural bust layers. SVG is rasterized once per appearance and palette.
const SIZE := Vector2(76, 88)
const PIVOT := Vector2(53, 52)
const OUTLINE := "#251c16"
const STEEL := "#b9c4cb"
const WOOD := "#88623e"
const SKIN := {"skel": "#d8d0b8", "zombie": "#9aa58a"}
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

func layers(unit: Dictionary) -> Dictionary:
	var look: Dictionary = unit.look
	var fallback := "nord" if unit.side == 0 else "emp"
	var faction: String = "player" if unit.hero or unit.companion else unit.faction
	var palette: Array = PALETTES.get(faction, PALETTES[fallback])
	var key := [palette[0], palette[1], unit.mounted]
	for field in LOOK_FIELDS:
		key.append(look.get(field))
	var cache_key := str(key)
	if not _cache.has(cache_key):
		_cache[cache_key] = {"body": _body(look, palette, unit.mounted), "weapon": _weapon(look.get("weapon")),
			"weapon_kind": look.get("weapon")}
	return _cache[cache_key]

static func _body(look: Dictionary, palette: Array, mounted: bool) -> Texture2D:
	var primary: String = palette[0]
	var trim: String = palette[1]
	var skin: String = SKIN.get(look.get("undead"), "#c79568")
	var armor: String = ARMOR.get(look.get("armor"), primary)
	var shapes := ""
	if mounted:
		var coat: String = HORSES.get(look.get("horse"), "#6b4226")
		shapes += _path("M6 77 Q3 57 22 55 L46 56 Q54 48 58 39 L60 33 L63 38 Q71 41 74 52 L70 55 L63 52 L62 72 Q52 85 22 82 Z", coat)
		shapes += _path("M46 56 Q53 43 60 33 Q58 46 54 58 Z", OUTLINE)
		shapes += '<circle cx="65" cy="45" r="1.5" fill="%s"/>' % OUTLINE
		shapes += _path("M13 60 Q29 56 49 60 L44 78 L17 77 Z", primary, trim)
		shapes += '<g transform="translate(0 -12)">'
	shapes += _path("M12 72 Q12 51 25 46 L48 46 Q60 50 61 72 Q37 82 12 72 Z", armor)
	shapes += _path("M17 66 L52 65 L53 71 Q34 76 17 71 Z", WOOD)
	shapes += _path("M30 47 L30 65 L41 67 L45 47 Z", primary, trim)
	shapes += _path("M25 40 Q20 27 27 20 Q39 13 47 23 L50 35 L46 38 L45 46 Q34 51 25 40 Z", skin)
	shapes += '<path d="M38 33h5 M39 41h5" stroke="%s" stroke-width="1.6"/>' % OUTLINE
	var helm: Variant = look.get("helm", "cap")
	match helm:
		"none": shapes += _path("M24 32 Q20 19 35 17 Q45 17 46 24 L29 27 L28 34 Z", WOOD)
		"hood", "cap", "furcap", "turban", "turbanm":
			shapes += _path("M22 38 Q18 22 29 16 Q43 11 50 26 L50 29 L29 30 L27 42 Z", primary, trim)
		"great", "greathelm":
			shapes += _path("M22 43 L23 18 L46 17 L51 44 L35 47 Z", STEEL)
			shapes += '<path d="M31 30h17 M42 36v5" stroke="%s" stroke-width="2"/>' % OUTLINE
		_:
			shapes += _path("M20 32 Q20 17 34 15 Q47 15 50 30 L45 31 L45 37 L41 37 L40 31 Z", STEEL)
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
