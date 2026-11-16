extends RefCounted
## Per-view atlas: original pixels, transparent gutters, no change to depth order or animation.
## Only presentation owns these textures; dropping the view releases its pages.
const PAGE_SIZE := 2048
const GUTTER := 2
var _pages: Array[Dictionary] = []
var _textures := {}
var _sources := {}
var _deferred := false
func begin_prepare() -> void: _deferred = true
func end_prepare() -> void:
	_deferred = false
	flush()
	_sources.clear()
func flush() -> void:
	for page in _pages:
		if page.dirty:
			page.texture.update(page.image)
			page.dirty = false
func resolve(texture: Texture2D) -> Texture2D:
	if texture == null: return null
	var key := texture.get_instance_id()
	if _textures.has(key): return _textures[key]
	var source := texture
	var region := Rect2i(Vector2i.ZERO, texture.get_size())
	if texture is AtlasTexture:
		source = texture.atlas
		region = Rect2i(texture.region)
	var source_key := source.get_instance_id()
	if not _sources.has(source_key):
		var image := source.get_image()
		if image.is_compressed(): image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		_sources[source_key] = image
	var size := region.size
	if size.x + GUTTER * 2 > PAGE_SIZE or size.y + GUTTER * 2 > PAGE_SIZE: return texture
	var page: Dictionary
	if not _pages.is_empty(): page = _pages.back()
	if not page.is_empty() and page.x + size.x + GUTTER > PAGE_SIZE:
		page.x = GUTTER
		page.y += page.row_height + GUTTER * 2
		page.row_height = 0
	if page.is_empty() or page.y + size.y + GUTTER > PAGE_SIZE:
		var image := Image.create(PAGE_SIZE, PAGE_SIZE, false, Image.FORMAT_RGBA8)
		page = {"image": image, "texture": ImageTexture.create_from_image(image), "x": GUTTER, "y": GUTTER, "row_height": 0, "dirty": false}
		_pages.append(page)
	var at := Vector2i(page.x, page.y)
	page.image.blit_rect(_sources[source_key], region, at)
	page.dirty = true
	var result := AtlasTexture.new()
	result.atlas = page.texture
	result.region = Rect2(at, size)
	result.filter_clip = true
	page.x += size.x + GUTTER * 2
	page.row_height = maxi(page.row_height, size.y)
	_textures[key] = result
	if not _deferred:
		flush()
		_sources.clear()
	return result
