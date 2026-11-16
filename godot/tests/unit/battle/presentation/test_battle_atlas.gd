extends SceneTree
const Atlas = preload("res://apps/godot/presentation/battle/battle_atlas.gd")
func _initialize() -> void:
	var source := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8: source.set_pixel(x, y, Color(float(x) / 8, float(y) / 8, 0.5, 1))
	var sheet := ImageTexture.create_from_image(source)
	var crop := AtlasTexture.new()
	crop.atlas = sheet
	crop.region = Rect2(2, 3, 3, 4)
	var atlas := Atlas.new()
	atlas.begin_prepare()
	var packed := atlas.resolve(crop)
	assert(atlas.resolve(crop) == packed)
	atlas.end_prepare()
	# Headless DummyRenderer does not implement texture update/readback. Check CPU packing here;
	# verify_sprite_batch.gd separately checks the actual GPU-rendered result.
	var pixels: Image = atlas._pages[0].image.get_region(Rect2i(packed.region))
	assert(pixels.get_size() == Vector2i(3, 4))
	for y in 4:
		for x in 3: assert(pixels.get_pixel(x, y) == source.get_pixel(x + 2, y + 3), "%s %s: %s vs %s" % [x,y,pixels.get_pixel(x,y),source.get_pixel(x+2,y+3)])
	assert(packed.get_size() == crop.get_size())
	var other := Atlas.new()
	assert(other.resolve(crop) != packed, "Atlas lifetimes belong to independent views")
	print("Battle atlas tests passed")
	quit(0)
