extends Node2D
const MapCamera = preload("res://apps/godot/presentation/campaign/world_camera.gd")
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
## Settlements on the map: sprites from a sheet drawn once, owner banners and name labels (like drawWorld in src/07_main.js).
const SettlementArt = preload("res://apps/godot/presentation/campaign/settlement_art.gd")
const OriginalArt = preload("res://apps/godot/visuals/original_art.gd")
const EmblemArt = preload("res://apps/godot/presentation/campaign/emblem_art.gd")
const FactionCatalog = preload("res://core/campaign/data/faction_catalog.gd")

const KINDS := ["town", "castle", "village", "camp"]
const SHEET_SCALE := 2.0
## Width in simulation units and the normalized entrance on each illustration.
const LANDMARKS := {
	"Бельмон": [preload("res://apps/godot/presentation/campaign/settlements/belmont.png"), 121.0, Vector2(0.58, 0.97)],
	"Вентум": [preload("res://apps/godot/presentation/campaign/settlements/ventum.png"), 124.0, Vector2(0.47, 0.97)],
	"Кастра Нигра": [preload("res://apps/godot/presentation/campaign/settlements/castra_nigra.png"), 64.0, Vector2(0.48, 0.97)],
	"Остра": [preload("res://apps/godot/presentation/campaign/settlements/ostra.png"), 47.0, Vector2(0.37, 0.92)],
}
const KIND_NAMES := {"town": "Город", "castle": "Замок", "village": "Деревня", "camp": "Логово разбойников"}
const LABEL_OFFSETS := [0, 24, -24, 48, -48, 72, -72, 96, -96]

var _sheet: SubViewport
var _settles: Array = []
var _landmarks := {}
var _front_to_back: Array = []
var _factions := FactionCatalog.new()

class SheetPainter extends Node2D:
	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * SHEET_SCALE)
		for row in KINDS.size():
			for col in SettlementArt.CULTURES.size():
				var cx: float = col * SettlementArt.SPRITE_SIZE.x + SettlementArt.ANCHOR.x
				var cy: float = row * SettlementArt.SPRITE_SIZE.y + SettlementArt.ANCHOR.y
				SettlementArt.draw_settlement(self, KINDS[row], SettlementArt.CULTURES[col], cx, cy)

func build(settles: Array) -> void:
	if not (ContentLoader.populate(_factions)):
		push_error("Required content failed to load: apps/godot/presentation/campaign/settlement_layer.gd")
		return
	_settles = settles.duplicate()
	_settles.sort_custom(func(a, b): return a.y < b.y)
	for s in _settles:
		var art: Array = LANDMARKS.get(s.get("name0", s.name), [])
		if art.is_empty():
			continue
		var texture: Texture2D = art[0]
		var dimensions := texture.get_size() * (float(art[1]) / texture.get_width())
		var entrance: Vector2 = art[2]
		var mask := BitMap.new()
		mask.create_from_image_alpha(texture.get_image(), 0.25)
		_landmarks[s.id] = {"texture": texture, "mask": mask, "rect": Rect2(Vector2(s.x, s.y) - entrance * dimensions, dimensions)}
		_front_to_back.push_front(s.id)
	_sheet = SubViewport.new()
	_sheet.size = Vector2i(SettlementArt.SPRITE_SIZE * Vector2(SettlementArt.CULTURES.size(), KINDS.size()) * SHEET_SCALE)
	_sheet.transparent_bg = true
	_sheet.disable_3d = true
	_sheet.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sheet.add_child(SheetPainter.new())
	add_child(_sheet)
	queue_redraw()

static func scale_of(kind: String) -> float:
	return 0.72 if kind == "town" else 0.7 if kind == "castle" else 0.6

func landmark_at(at: Vector2) -> int:
	for id in _front_to_back:
		var art: Dictionary = _landmarks[id]
		var rect: Rect2 = art.rect
		if rect.has_point(at):
			var texture: Texture2D = art.texture
			var pixel := Vector2i((at - rect.position) / rect.size * texture.get_size())
			if art.mask.get_bitv(pixel):
				return id
	return -1

func has_landmark(id: int) -> bool:
	return _landmarks.has(id)

func _draw() -> void:
	if _sheet == null:
		return
	var tex := _sheet.get_texture()
	var size := SettlementArt.SPRITE_SIZE
	for s in _settles:
		var row := KINDS.find(s.kind)
		var culture: String = s.get("cult", s.fac)
		var col := 0 if s.kind == "camp" else SettlementArt.CULTURES.find(culture)
		if col < 0:
			col = SettlementArt.CULTURES.size() - 1
		var k := scale_of(s.kind) * MapCamera.MARKER_SCALE
		var src := Rect2(Vector2(col * size.x, row * size.y) * SHEET_SCALE, size * SHEET_SCALE)
		var dest := Rect2(Vector2(s.x, s.y) - SettlementArt.ANCHOR * k, size * k)
		var tint := Color.WHITE
		if s.get("cleared", false) and s.kind == "camp":
			tint = Color(1, 1, 1, 0.5)
		elif s.fac == "undead":
			tint = Color(0.55, 0.62, 0.5)
		elif int(s.get("burnt", 0)) > 0 or float(s.get("dmg", 0.0)) > 0.3:
			tint = Color(0.6, 0.5, 0.45)
		var original := OriginalArt.settlement(s.kind, culture, s.fac)
		if _landmarks.has(s.id):
			var art: Dictionary = _landmarks[s.id]
			draw_texture_rect(art.texture, art.rect, false, tint)
			EmblemArt.draw_banner(self, s.x + 8, s.y, _factions.get_faction(s.fac), 8.0)
		elif original != null:
			draw_texture_rect(original, dest, false, tint)
		else:
			draw_texture_rect_region(tex, dest, src, tint)
		if int(s.get("burnt", 0)) > 0 or int(s.get("fire", 0)) > 0:
			for i in 3:
				draw_circle(Vector2(s.x + (i - 1) * 9.0 * k, s.y - 30.0 * k - i * 6.0), (7.0 + i * 3.0) * k, Color(0.3, 0.28, 0.26, 0.45))
		if s.kind != "camp" and original == null:
			var bx: float = 14.0 if s.kind == "castle" else 20.0
			var by: float = -62.0 if s.kind == "town" else -66.0 if s.kind == "castle" else -28.0
			EmblemArt.draw_banner(self, s.x + bx * k, s.y + by * k, _factions.get_faction(s.fac), 13.0 * k)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * MapCamera.MARKER_SCALE)
	_draw_labels()

func _draw_labels() -> void:
	var font := preload("res://apps/godot/visuals/game_theme.gd").BODY
	var entries: Array = []
	for s in _settles:
		var size := 13 if s.kind == "village" else 16
		var color := Color("#ff7a66") if s.kind == "camp" else (Color("#a9b98e") if s.fac == "undead" else Color("#f0e6c8"))
		entries.append({"text": s.name, "x": s.x * MapCamera.MAP_SCALE, "y": s.y * MapCamera.MAP_SCALE + 22.0, "color": color, "size": size})
	entries.sort_custom(func(a, b): return a.size > b.size)
	var boxes: Array[Rect2] = []
	for e in entries:
		var w := font.get_string_size(e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, e.size).x + 12.0
		var h: float = e.size + 6.0
		var placed := Rect2()
		var ok: bool = false
		for offset in LABEL_OFFSETS:
			var box := Rect2(e.x - w / 2.0, e.y + offset - h, w, h)
			var clash := false
			for b in boxes:
				if box.intersects(b):
					clash = true
					break
			if clash:
				continue
			placed = box
			boxes.append(box)
			ok = true
			break
		if not ok:
			continue
		var yy := placed.position.y + h
		if absf(yy - e.y) > 2.0:
			draw_line(Vector2(e.x, e.y - 10.0), Vector2(e.x, yy - h / 2.0), Color(232 / 255.0, 214 / 255.0, 166 / 255.0, 0.5), 1.0, true)
		draw_rect(Rect2(placed.position.x, placed.position.y + 2.0, w, h), Color(29 / 255.0, 24 / 255.0, 14 / 255.0, 0.65))
		draw_string_outline(font, Vector2(e.x - w / 2.0 + 6.0, yy - 3.0), e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, e.size, 4, Color(14 / 255.0, 9 / 255.0, 4 / 255.0, 0.9))
		draw_string(font, Vector2(e.x - w / 2.0 + 6.0, yy - 3.0), e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, e.size, e.color)
