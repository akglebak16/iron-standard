extends SceneTree
const Art = preload("res://apps/godot/visuals/original_art.gd")
const Skins = preload("res://apps/godot/visuals/dominion_heraldic_art.gd")
const Motion = preload("res://apps/godot/presentation/battle/unit_motion.gd")

func _initialize() -> void:
	for troop in Skins.IDS:
		var old: Dictionary = Art.MANIFEST.troops[troop + "|dom"]
		var look: Dictionary = old.look.duplicate(true)
		var unit := {"id": 1, "look": look, "faction": "dom", "hero": false, "companion": false, "mounted": false, "side": 0}
		for variant in 4:
			var entry := Art.layers_for(unit, troop, variant)
			assert(entry.anchor == Vector2(76, 158))
			assert(entry.head_center.x == 76 and entry.neck_center == Vector2(76, 78), "heads sit level at the shared neck joint")
			for part in Skins.PARTS:
				var texture: Texture2D = entry[part]
				assert(texture != null and texture.get_size() == Vector2(152, 176), "%s %s" % [troop, part])
				assert(texture.atlas == Skins.PAGES[variant], "every state uses the same new skin")
			var body := entry.body.get_image() as Image
			var headless := entry.headless.get_image() as Image
			assert(body.get_pixel(76, 48).a > 0.0 and headless.get_pixel(76, 48).a == 0.0)
			var head_region := entry.head.get_image().get_used_rect() as Rect2i
			assert(head_region.size.x < 95 and head_region.end.y < 95)
			assert(entry.head.get_image().get_pixel(25, 90).a == 0.0, "shoulders remain on the torso")
			assert(entry.body.get_image().get_data() != entry.portrait.get_image().get_data(), "weapons animate separately")
			var grip: Color = entry.weapon.get_image().get_pixelv(Vector2i(entry.pivot))
			assert(grip.a > 0.5, "the animation pivots through the gripping glove")
			if look.armor in ["mail", "mailtab"]:
				assert(grip.b >= grip.r * 0.8, "armoured troops wear steel-coloured gloves")
			assert(_visible_bytes(entry.corpse) == _visible_bytes(entry.portrait), "death retains the selected skin")
			if look.weapon == "xbow":
				assert(entry.weapon_kind == "heraldic_xbow" and Motion.weapon_kind(entry.weapon_kind) == 4)
				assert(look.weapon == "xbow", "pose keys never mutate gameplay equipment")
			else: assert(entry.weapon_kind == look.weapon)
	# Other factions and Dominion cavalry still use the original sheets.
	for pair in [["n3", "nord"], ["e2a", "emp"], ["d2c", "dom"], ["d3c", "dom"]]:
		assert(not Skins.supports(pair[0], pair[1]))
		assert(Art.sprite(pair[0], pair[1]).atlas == Art.SHEETS.portrait[0])
	# Hired Dominion troops use new silhouettes and the player's chosen banner.
	Art.select_player_banner(0)
	var amber := Art.sprite("d2", "player").get_image().get_data()
	Art.select_player_banner(1)
	var green := Art.sprite("d2", "player").get_image().get_data()
	assert(amber != green, "banner changes still recolour hired troops")
	var hand := Vector2i(125, 116)
	var ui_glove := Art.sprite("d2", "player", "portrait").get_image().get_pixelv(hand)
	var battle_glove := Art.sprite("d2", "player", "weapon").get_image().get_pixelv(hand)
	# Alpha blending can round an antialiased colour channel by one byte.
	for channel in 4:
		assert(absf(ui_glove[channel] - battle_glove[channel]) <= 2.0 / 255.0, "banner dye preserves glove materials in both UI and battle")
	assert(Art.sprite("d2", "player").get_image().get_pixel(76, 48) == Art.sprite("d2", "dom").get_image().get_pixel(76, 48), "dye preserves faces and helmets")
	Art.select_player_banner(0)
	assert(Art.sprite("d2", "player").get_image().get_data() == amber, "banner cache must not go stale")
	print("Dominion heraldic tests passed: seven troops, four variants, all death states and banners")
	quit()

func _visible_bytes(texture: Texture2D) -> PackedByteArray:
	var bytes := texture.get_image().get_data()
	# Godot's import alpha-border fix copies neighbour RGB into fully transparent pixels.
	for p in range(0, bytes.size(), 4):
		if bytes[p + 3] == 0:
			bytes[p] = 0
			bytes[p + 1] = 0
			bytes[p + 2] = 0
	return bytes
