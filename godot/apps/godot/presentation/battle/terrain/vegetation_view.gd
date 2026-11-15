extends RefCounted

const TREE_SIZE := Vector2i(100, 125)
const BUSH_SIZE := Vector2i(60, 46)
const TREE_ANCHOR := Vector2(51, 116)
const BUSH_ANCHOR := Vector2(30, 38)
const BARK := "#4a3320"
const OUTLINE := "#252819"
const SHADOW_OPACITY := 0.25
const TREE_SHADOW := Vector2(23, 6)
const BUSH_SHADOW := Vector2(23, 5)
const CROWN_BLOBS := 10
const BUSH_BLOBS := 7
const SNOW_LAYERS := 4
const GRASS_PALETTE := ["#25401a", "#3f6124", "#628735"]
const PALETTES := {
	"grass": GRASS_PALETTE,
	"snow": ["#28402f", "#3d5947", "#dfe7e8"],
	"steppe": ["#4a4e1a", "#6f7230", "#a8ab58"],
	"arid": ["#5f6a2c", "#7c8838", "#98a24a"],
}
const CROWN_CENTER := Vector2(50, 53)
const ARID_CROWN_CENTER := Vector2(50, 52)
const CROWN_SPREAD := Vector2(23, 21)
const ARID_CROWN_SPREAD := Vector2(27, 7)
const BUSH_CENTER := Vector2(30, 26)
const BUSH_SPREAD := Vector2(15, 6)
const CROWN_RADIUS := Vector2(14, 23)
const BUSH_RADIUS := Vector2(8, 13)
const HIGHLIGHT_OFFSET := Vector2(-3, -4)
const HIGHLIGHT_SCALE := Vector2(0.72, 0.59)

var entries: Array[Dictionary] = []

func configure(layout: Array[Dictionary], biome: String, seed_value: int) -> void:
	entries.clear()
	var textures := {}
	for plant in layout:
		var key := Vector2i(int(plant.tree), plant.variant)
		if not textures.has(key):
			textures[key] = _texture(plant.tree, biome, seed_value + plant.variant)
		var anchor := TREE_ANCHOR if plant.tree else BUSH_ANCHOR
		var texture: Texture2D = textures[key]
		var bounds := Rect2(Vector2(plant.position) - anchor, Vector2(texture.get_size()))
		entries.append({"position": plant.position, "bounds": bounds, "texture": texture})
	entries.sort_custom(func(a: Dictionary, b: Dictionary): return a.position.y < b.position.y)

static func _texture(tree: bool, biome: String, seed_value: int) -> Texture2D:
	var variants := 3 if tree else 2
	var path := "res://ui/assets/%s_%s_%d.png" % ["tree" if tree else "bush", biome, posmod(seed_value, variants)]
	if ResourceLoader.exists(path):
		var original: Texture2D = load(path)
		var image := original.get_image()
		var size := TREE_SIZE if tree else BUSH_SIZE
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		return ImageTexture.create_from_image(image)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var size := TREE_SIZE if tree else BUSH_SIZE
	var anchor := TREE_ANCHOR if tree else BUSH_ANCHOR
	var palette: Array = PALETTES.get(biome, GRASS_PALETTE)
	var art := _ellipse(anchor, TREE_SHADOW if tree else BUSH_SHADOW, "#15170d", SHADOW_OPACITY)
	if tree:
		art += '<path d="M44 116 Q49 91 45 69 L48 60 L52 78 L61 65 L64 69 L55 87 Q53 101 58 116 Z" fill="%s" stroke="%s"/>' % [BARK, OUTLINE]
	if tree and biome == "snow":
		art += _snow_crown(palette)
	else:
		art += _leaf_crown(rng, tree, biome == "arid", palette)
	var image := Image.new()
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">%s</svg>' % [size.x, size.y, art]
	var error := image.load_svg_from_string(svg)
	assert(error == OK, "Vegetation SVG must rasterize")
	return ImageTexture.create_from_image(image)

static func _leaf_crown(rng: RandomNumberGenerator, tree: bool, arid: bool, palette: Array) -> String:
	var center := BUSH_CENTER if not tree else (ARID_CROWN_CENTER if arid else CROWN_CENTER)
	var spread := BUSH_SPREAD if not tree else (ARID_CROWN_SPREAD if arid else CROWN_SPREAD)
	var interval := CROWN_RADIUS if tree else BUSH_RADIUS
	var aspect := 0.48 if tree and arid else 0.89
	var blobs: Array[Vector3] = []
	for i in (CROWN_BLOBS if tree else BUSH_BLOBS):
		var point := center + Vector2(rng.randf_range(-spread.x, spread.x), rng.randf_range(-spread.y, spread.y))
		blobs.append(Vector3(point.x, point.y, rng.randf_range(interval.x, interval.y)))
	blobs.sort_custom(func(a: Vector3, b: Vector3): return a.y < b.y)
	var art := ""
	for blob in blobs:
		var point := Vector2(blob.x, blob.y)
		var radius := Vector2(1.0, aspect) * blob.z
		art += _ellipse(point, radius + Vector2.ONE, OUTLINE)
	for blob in blobs:
		var point := Vector2(blob.x, blob.y)
		var radius := Vector2(1.0, aspect) * blob.z
		art += _ellipse(point, radius, palette[0])
		art += _ellipse(point + HIGHLIGHT_OFFSET, radius * HIGHLIGHT_SCALE, palette[1])
		art += _ellipse(point + HIGHLIGHT_OFFSET * 2.0, radius * HIGHLIGHT_SCALE * 0.48, palette[2], 0.66)
	return art

static func _snow_crown(palette: Array) -> String:
	var art := ""
	for layer in SNOW_LAYERS:
		var y := 101 - layer * 21
		var width := 36 - layer * 6
		art += '<path d="M%d %d L50 %d L%d %d Q50 %d %d %d Z" fill="%s" stroke="%s"/>' % [
			50 - width, y, y - 34, 50 + width, y, y + 7, 50 - width, y, palette[layer % 2], OUTLINE]
		art += '<path d="M%d %d L50 %d L%d %d Q47 %d %d %d Z" fill="%s"/>' % [
			50 - width * 0.65, y - 7, y - 32, 50 + width * 0.3, y - 13, y - 13,
			50 - width * 0.65, y - 7, palette[2]]
	return art

static func _ellipse(point: Vector2, radius: Vector2, color: String, opacity: float = 1.0) -> String:
	return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s" opacity="%s"/>' % [
		point.x, point.y, radius.x, radius.y, color, opacity]
