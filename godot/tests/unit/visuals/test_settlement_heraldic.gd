extends SceneTree
## Heraldic settlements of the campaign map (#254): every kind and culture has a picture standing on
## its anchor, and the owner's banner pole is inside the picture.
const Settlements = preload("res://apps/godot/visuals/settlement_heraldic_art.gd")

func _initialize() -> void:
	for kind in ["town", "castle", "village"]:
		for culture in ["nord", "emp", "khan", "kin", "emi", "dom", "pact"]:
			var texture := Settlements.texture(kind, culture)
			assert(texture != null, kind + " " + culture)
			var image := texture.get_image()
			assert(image.get_size() == Vector2i(Settlements.FRAME))
			assert(image.get_pixelv(Vector2i(Settlements.ANCHOR)).a > 0.5, "the anchor stands on the ground patch: " + kind + " " + culture)
			var pole := Settlements.ANCHOR + Settlements.flag(kind, culture)
			assert(Rect2(Vector2.ZERO, Settlements.FRAME).has_point(pole), "banner pole inside the frame: " + kind + " " + culture)
	assert(Settlements.texture("camp", "") != null, "the bandit lair")
	assert(Settlements.texture("town", "undead") == Settlements.texture("town", "emp"), "a culture without drawings borrows one")
	print("Settlement heraldic tests passed")
	quit(0)
