extends SceneTree
const Art = preload("res://apps/godot/visuals/original_art.gd")
const REFERENCES := [
	preload("res://tests/unit/visuals/fixtures/banner_1_f3.png"),
	preload("res://tests/unit/visuals/fixtures/banner_2_f3.png"),
	preload("res://tests/unit/visuals/fixtures/banner_3_f3.png"),
	preload("res://tests/unit/visuals/fixtures/banner_4_f3.png"),
	preload("res://tests/unit/visuals/fixtures/banner_5_f3.png"),
]

func _initialize() -> void:
	Art.select_player_banner(0)
	var baseline := _sprite_image()
	var enemy: AtlasTexture = Art.sprite("e1", "emp")
	var enemy_data := enemy.atlas.get_image().get_region(Rect2i(enemy.region)).get_data()
	var look: Dictionary = Art.MANIFEST.troops["f3|player"].look
	var original_hero: PackedByteArray = Art.compose(look).portrait.get_image().get_data()
	for index in range(1, 6):
		Art.select_player_banner(index)
		var actual := _sprite_image()
		var expected: Image = REFERENCES[index - 1].get_image()
		assert(actual.get_size() == expected.get_size())
		var a := actual.get_data()
		var b := expected.get_data()
		var maximum_error := 0.0
		for i in range(0, a.size(), 4):
			assert(a[i + 3] == b[i + 3], "palette must preserve silhouette")
			for channel in 3:
				maximum_error = maxf(maximum_error, absf(float(a[i + channel]) - b[i + channel]) * b[i + 3] / 255.0)
		assert(maximum_error <= 3, "original Canvas banner %d: weighted colour error %s" % [index, str(maximum_error)])
		assert(actual.get_data() != baseline.get_data())
		assert(Art.palette("player").c1 == Art.BANNERS[index].c1)
		var hero: PackedByteArray = Art.compose(look).portrait.get_image().get_data()
		assert(hero != original_hero, "equipment components must also use the selected palette")
		var current_enemy: AtlasTexture = Art.sprite("e1", "emp")
		assert(current_enemy.atlas.get_image().get_region(Rect2i(current_enemy.region)).get_data() == enemy_data)
	Art.select_player_banner(0)
	assert(_sprite_image().get_data() == baseline.get_data(), "reset must not retain a recoloured cache")
	assert(Art.compose(look).portrait.get_image().get_data() == original_hero)
	print("Banner palettes tests passed")
	quit()

func _sprite_image() -> Image:
	# A troop still drawn from the original sheets (Dominion, Nordmark and Empire use heraldic skins).
	var texture: AtlasTexture = Art.sprite("f3", "player")
	return texture.atlas.get_image().get_region(Rect2i(texture.region))
