extends SceneTree
## The hero and companions in the heraldic style (#232): every armour, helmet, weapon and shield the
## hero can wear is drawn, and banner, skin and hair repaint the figure.
const Art = preload("res://apps/godot/visuals/original_art.gd")
const Hero = preload("res://apps/godot/visuals/hero_heraldic_art.gd")
const FaceVariant = preload("res://apps/godot/visuals/face_variant.gd")

const FACE := {"skin": "#e2b48c", "hair": "#4a3020", "beard": 1, "stache": 0, "bald": false, "scar": false}

func _initialize() -> void:
	Art.select_player_banner(0)
	var look := {"helm": "none", "armor": "tunic", "weapon": "sword", "shield": "kite", "horse": null, "seed": 1, "face": FACE}
	var figure := Art.compose(look)
	assert(figure.body.get_size() == Vector2(152, 176))
	assert(figure.anchor == Vector2(76, 158))
	assert(figure.has("guard_source"), "a shield can be raised in battle")
	assert(_opaque(figure.head) > 300, "the head is drawn")
	assert(_opaque(figure.weapon) > 100, "the weapon is drawn")
	# Old saves and troops without a face keep the original components.
	assert(Art.compose({"helm": "none", "armor": "tunic", "undead": "skel", "seed": 1}).body.get_size() == Vector2(152, 176))

	# Every armour, helmet and weapon the hero can get, on foot and on horseback.
	for armor in ["tunic", "fur", "mailfur", "padded", "mail", "mailtab", "scale", "goldscale", "lamellar", "goldlam", "plate", "habit"]:
		assert(Hero.supports({"armor": armor, "helm": "none"}), armor)
	for helm in ["none", "nasal", "spectacle", "cap", "hood", "flat", "crest", "kettle", "mask", "furcap", "pointed", "great", "coif", "turban", "turbanm"]:
		assert(_opaque(Art.compose(look.merged({"helm": helm}, true)).head) > 300, helm)
	for weapon in ["sword", "axe", "spear", "halberd", "sabre", "club", "mace", "xbow", "lance", "bow"]:
		assert(_opaque(Art.compose(look.merged({"weapon": weapon}, true)).weapon) > 50, weapon)
	var rider := Art.compose(look.merged({"horse": "bay", "weapon": "lance"}, true))
	assert(rider.body.get_size() == Vector2(240, 244))
	assert(rider.anchor == Vector2(112, 264))
	assert(rider.head_center.y < rider.anchor.y)

	# The banner repaints cloth and shield; skin and hair repaint the head.
	var banner_0: PackedByteArray = figure.portrait.get_image().get_data()
	Art.select_player_banner(2)
	assert(Art.compose(look).portrait.get_image().get_data() != banner_0, "the banner colours the hero")
	Art.select_player_banner(0)
	assert(Art.compose(look).portrait.get_image().get_data() == banner_0)
	var darker := look.duplicate()
	darker.face = FACE.merged({"skin": "#b97d58"}, true)
	assert(Art.compose(darker).head.get_image().get_data() != figure.head.get_image().get_data())
	var grey := look.duplicate()
	grey.face = FACE.merged({"hair": "#b9b2a5"}, true)
	assert(Art.compose(grey).head.get_image().get_data() != figure.head.get_image().get_data())
	# A closed helmet hides the beard and the hair.
	var closed := look.merged({"helm": "great"}, true)
	var shaved_closed := closed.duplicate()
	shaved_closed.face = FACE.merged({"beard": 0, "bald": true}, true)
	assert(Art.compose(closed).head.get_image().get_data() == Art.compose(shaved_closed).head.get_image().get_data())
	# Every face the start screen offers is drawn.
	for skin in FaceVariant.SKINS:
		for hair in FaceVariant.HAIR_CHOICES:
			var face := FACE.merged({"skin": skin, "hair": hair}, true)
			assert(_opaque(Hero.compose(look, face, Art.BANNERS[0]).head) > 300)
	print("Hero heraldic tests passed")
	quit(0)

func _opaque(texture: Texture2D) -> int:
	var image := texture.get_image()
	var count := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			if image.get_pixel(x, y).a > 0.5: count += 1
	return count
