extends SceneTree
const FaceVariant = preload("res://apps/godot/visuals/face_variant.gd")
const Art = preload("res://apps/godot/visuals/original_art.gd")

func _initialize() -> void:
	# the same draws as makeVariant(mulberry(seed)) in the browser (values taken from src/02_art.js under Node)
	assert(is_equal_approx(FaceVariant.next([1]), 0.6270739405881613))
	assert(is_equal_approx(FaceVariant.next([7]), 0.011704753153026104))
	var cases := [[1, 1.0, {"skin": "#c98f66", "hair": "#7a2e16", "beard": 2, "bald": false, "scar": false}],
		[12345, 1.0, {"skin": "#c98f66", "hair": "#1a1a1a", "beard": 2, "bald": false, "scar": false}],
		[99999, 0.0, {"skin": "#c98f66", "hair": "#a8672e", "beard": 0, "bald": false, "scar": true}],
		[2024, 1.0, {"skin": "#b97d58", "hair": "#b9b2a5", "beard": 1, "bald": false, "scar": false}]]
	for c in cases:
		var v := FaceVariant.variant(c[0], c[1])
		for field in c[2]:
			assert(v[field] == c[2][field], "seed %d: %s" % [c[0], field])
	# a companion's fixed hair wins over the drawn one; a moustache only without a beard
	assert(FaceVariant.variant(5, 1.0, "#dcb860").hair == "#dcb860")
	assert(FaceVariant.variant(99999, 0.0, null, true).stache == 1)
	assert(FaceVariant.of_look({"helm": "none"}).is_empty(), "troops keep their atlas faces")
	# every face, helm and stump the hero can get is in the generated atlas
	for skin in FaceVariant.SKINS:
		assert(Art.FACES.frames.has("stump|" + skin))
		for hair in FaceVariant.HAIRS:
			for shape in [[0, 0], [0, 1], [1, 0], [2, 0]]:
				for scar in [0, 1]:
					assert(Art.FACES.frames.has("face|%s|%s|%d|%d|%d" % [skin, hair, shape[0], shape[1], scar]))
	# two heroes with different seeds get different heads, the same seed the same head
	var a := Art.compose({"helm": "none", "armor": "tunic", "weapon": "sword", "seed": 1, "beard": 1})
	var b := Art.compose({"helm": "none", "armor": "tunic", "weapon": "sword", "seed": 99999, "beard": 0})
	var a2 := Art.compose({"helm": "none", "armor": "tunic", "weapon": "sword", "seed": 1, "beard": 1})
	assert(a.head.get_image().get_data() != b.head.get_image().get_data())
	assert(a.head.get_image().get_data() == a2.head.get_image().get_data())
	print("Face variant tests passed")
	quit(0)
