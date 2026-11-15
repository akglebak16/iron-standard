extends Node2D
## Draws every relief icon (trees, hills, mountains, bushes) once into a sheet, like the
## per-icon canvas code in paintTerrain() (src/05b_worldart.js). The map then stamps these sprites.
const Brush = preload("res://campaign/presentation/map_brush.gd")

const SCALE := 2.0                     ## sheet pixels per world unit
const CELL := Vector2i(128, 128)
const MOUNT_CELL := Vector2i(256, 192)
const MOUNT_REF := 1.65                ## mountain scale the sheet is drawn at
const ANCHOR := Vector2(64, 100)
const MOUNT_ANCHOR := Vector2(100, 160)
const SHEET := Vector2i(1280, 320)
const PINE := 0
const TREE_STEPPE := 1
const TREE_GRASS := 2

var _shadow: Texture2D

## Regions in the sheet: key -> Rect2i. Anchor of an icon is at region.position + anchor_of(key).
static func region_of(key: String) -> Rect2i:
	var parts := key.split(":")
	var variant := int(parts[1])
	match parts[0]:
		"tree":
			return Rect2i(Vector2i(variant * CELL.x, 0), CELL)  # variant = kind * 2 + leaf shade
		"hill":
			return Rect2i(Vector2i((6 + variant) * CELL.x, 0), CELL)
		"bush":
			return Rect2i(Vector2i(variant * CELL.x, CELL.y), CELL)
		"mount":
			return Rect2i(Vector2i(4 * CELL.x, CELL.y), MOUNT_CELL)
	return Rect2i()

static func anchor_of(key: String) -> Vector2:
	return MOUNT_ANCHOR if key.begins_with("mount") else ANCHOR

func _ready() -> void:
	_shadow = Brush.soft_shadow_texture()
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * SCALE)
	for kind in 3:
		for leaf in 2:
			_tree(kind, leaf, region_of("tree:%d" % (kind * 2 + leaf)).position + Vector2i(ANCHOR))
	for bio in 4:
		_hill(bio, region_of("hill:%d" % bio).position + Vector2i(ANCHOR))
		_bush(bio, region_of("bush:%d" % bio).position + Vector2i(ANCHOR))
	_mount(region_of("mount:0").position + Vector2i(MOUNT_ANCHOR))

func _tree(kind: int, leaf: int, anchor: Vector2i) -> void:
	var x := anchor.x / SCALE
	var y := anchor.y / SCALE
	draw_texture_rect(_shadow, Rect2(x + 4 - 11, y + 2 - 4, 22, 8), false)
	draw_colored_polygon(Brush.ellipse(x + 3, y + 1, 7, 2.6), Color(0, 0, 0, 0.24))
	if kind == PINE:
		Brush.fill_rect(self, x - 0.8, y - 2, 1.8, 3, Color("#3b2a1a"))
		Brush.fill_stroke(self, Brush.poly([x, y - 16, x + 6.5, y - 1, x - 6.5, y - 1]), Color("#2a4434"), 1.2)
		Brush.fill_stroke(self, Brush.poly([x, y - 16, x + 6.5, y - 1, x + 1, y - 1]), Color(0, 0, 0, 0.25), 0.0)
		Brush.fill_stroke(self, Brush.poly([x, y - 16, x + 3.2, y - 9, x - 3.4, y - 9]), Color("#eef4f5"), 0.5)
		return
	Brush.fill_rect(self, x - 1, y - 4, 2.2, 5, Color("#3b2a1a"))
	var steppe := kind == TREE_STEPPE
	var dk := Color("#5c6424") if steppe else Color("#2a4619")
	var md := Color("#707a2e") if steppe else Color("#3d6226")
	var lt := Color("#8e9843") if steppe else Color("#5f8a35")
	Brush.fill_stroke(self, Brush.ellipse(x, y - 9, 6.6, 6.8), dk, 1.2)
	draw_colored_polygon(Brush.ellipse(x + 2, y - 6.5, 4.4, 3.6), Color(0, 0, 0, 0.18))
	draw_colored_polygon(Brush.ellipse(x - 1.6, y - 10.4, 4.6, 4.6), md)
	draw_colored_polygon(Brush.ellipse(x - 3, y - 12, 2.4, 2.1), lt)
	var dot := Color("#8b9c48") if leaf == 1 else Color("#729441")
	for n in 4:
		draw_colored_polygon(Brush.ellipse(x - 3.8 + n * 1.7, y - 12 + (n % 2) * 2, 0.9, 0.6, 8), dot)

func _hill(bio: int, anchor: Vector2i) -> void:
	var x := anchor.x / SCALE
	var y := anchor.y / SCALE
	var color := Color("#c8d2d3") if bio == 1 else Color("#a59152") if bio == 2 else Color("#bfa268") if bio == 3 else Color("#8a8f4e")
	var outline := Brush.quad(Vector2(x - 17, y), Vector2(x, y - 18), Vector2(x + 17, y), 16)
	Brush.fill_stroke(self, outline, color, 1.1)
	# shaded right side, clipped to the hill: the part of the outline with x >= x + 2
	var shade := PackedVector2Array()
	for p in outline:
		if p.x >= x + 2:
			shade.append(p)
	if shade.size() >= 2:
		shade.append(Vector2(shade[shade.size() - 1].x, y))
		shade.append(Vector2(shade[0].x, y))
		draw_colored_polygon(shade, Color(0, 0, 0, 0.16))
	# thin highlight along the crest
	var crest := PackedVector2Array()
	for p in outline:
		if p.x > x - 12 and p.x < x + 1:
			crest.append(p + Vector2(0, 1.2))
	if crest.size() >= 2:
		draw_polyline(crest, Color(1, 1, 1, 0.22), 1.6, true)

func _bush(bio: int, anchor: Vector2i) -> void:
	var x := anchor.x / SCALE
	var y := anchor.y / SCALE
	var color := Color("#8ea08a") if bio == 1 else Color("#8c8a3e") if bio == 2 else Color("#9a8a4e") if bio == 3 else Color("#4d6b27")
	Brush.fill_stroke(self, Brush.ellipse(x, y - 3, 5, 3.6), color, 1.0)

func _mount(anchor: Vector2i) -> void:
	var x := anchor.x / SCALE
	var y := anchor.y / SCALE
	var s := MOUNT_REF
	draw_colored_polygon(Brush.ellipse(x + 6 * s, y, 22 * s, 4.4 * s), Color(0, 0, 0, 0.25))
	Brush.fill_stroke(self, Brush.poly([x - 21 * s, y, x - 3 * s, y - 34 * s, x + 6 * s, y - 24 * s, x + 13 * s, y - 30 * s, x + 25 * s, y]), Color("#948e82"), 1.6)
	Brush.fill_stroke(self, Brush.poly([x - 3 * s, y - 34 * s, x + 6 * s, y - 24 * s, x + 13 * s, y - 30 * s, x + 25 * s, y, x + 7 * s, y]), Color("#6c675d"), 0.0)
	Brush.fill_stroke(self, Brush.poly([x - 3 * s, y - 34 * s, x - 21 * s, y, x - 12 * s, y]), Color(1, 1, 1, 0.12), 0.0)
	var ridge := Color(0.118, 0.102, 0.078, 0.45)
	draw_polyline(PackedVector2Array([Vector2(x - 3 * s, y - 34 * s), Vector2(x + 1 * s, y - 14 * s), Vector2(x - 3 * s, y - 2 * s)]), ridge, 0.9, true)
	draw_polyline(PackedVector2Array([Vector2(x + 13 * s, y - 30 * s), Vector2(x + 14 * s, y - 14 * s), Vector2(x + 18 * s, y - 2 * s)]), ridge, 0.9, true)
	draw_polyline(PackedVector2Array([Vector2(x + 6 * s, y - 24 * s), Vector2(x + 8 * s, y - 12 * s)]), ridge, 0.9, true)
	Brush.fill_stroke(self, Brush.poly([x - 7 * s, y - 27 * s, x - 3 * s, y - 34 * s, x + 2.5 * s, y - 27 * s, x + 0 * s, y - 29 * s, x - 3 * s, y - 24 * s]), Color("#f4f6f5"), 0.8)
	Brush.fill_stroke(self, Brush.poly([x + 9 * s, y - 27 * s, x + 13 * s, y - 30 * s, x + 16 * s, y - 25 * s, x + 12 * s, y - 26 * s]), Color("#e3e8e8"), 0.6)
