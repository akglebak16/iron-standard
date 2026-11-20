extends SceneTree
const Art = preload("res://apps/godot/visuals/original_art.gd")
const Skins = preload("res://apps/godot/visuals/dominion_heraldic_art.gd")
const Motion = preload("res://apps/godot/presentation/battle/unit_motion.gd")

func _initialize() -> void:
	for troop in Skins.IDS + Skins.NORD_IDS + Skins.EMP_IDS + Skins.KHAN_IDS + Skins.UNDEAD_IDS:
		var old: Dictionary = Art.MANIFEST.troops[troop + "|" + Skins.home_of(troop)]
		var look: Dictionary = old.look.duplicate(true)
		var unit := {"id": 1, "look": look, "faction": Skins.home_of(troop), "hero": false, "companion": false, "mounted": false, "side": 0}
		for variant in 4:
			var entry := Art.layers_for(unit, troop, variant)
			assert(entry.anchor == Vector2(76, 158))
			assert(entry.head_center.x == 76 and entry.neck_center == Vector2(76, 78), "heads sit level at the shared neck joint")
			for part in Skins.PARTS:
				var texture: Texture2D = entry[part]
				assert(texture != null and texture.get_size() == Vector2(152, 176), "%s %s" % [troop, part])
				assert(texture.atlas == Skins.pages(troop)[variant], "every state uses the same new skin")
			var body := entry.body.get_image() as Image
			var headless := entry.headless.get_image() as Image
			assert(body.get_pixel(76, 48).a > 0.0 and headless.get_pixel(76, 48).a == 0.0)
			var head_region := entry.head.get_image().get_used_rect() as Rect2i
			assert(head_region.size.x < 95 and head_region.end.y < 95)
			assert(entry.head.get_image().get_pixel(25, 90).a == 0.0, "shoulders remain on the torso")
			assert(head_region.end.y <= 88, "the head ends just below the neck joint, inside the collar")
			assert(_pieces(entry.head.get_image()) == 1, "%s: the cut head is one clean piece" % troop)
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
	# Dominion cavalry: heraldic horse and rider in the old mounted frame and anchor.
	for troop in Skins.CAVALRY_IDS + Skins.NORD_CAVALRY_IDS + Skins.EMP_CAVALRY_IDS + Skins.KHAN_CAVALRY_IDS + Skins.UNDEAD_CAVALRY_IDS:
		var old: Dictionary = Art.MANIFEST.troops[troop + "|" + Skins.home_of(troop)]
		var look: Dictionary = old.look.duplicate(true)
		var unit := {"id": 2, "look": look, "faction": Skins.home_of(troop), "hero": false, "companion": false, "mounted": true, "side": 0}
		for variant in 4:
			var entry := Art.layers_for(unit, troop, variant)
			assert(entry.anchor == Vector2(112, 264), "cavalry keeps its battle placement")
			for part in Skins.PARTS:
				var texture: Texture2D = entry[part]
				assert(texture != null and texture.get_size() == Vector2(240, 244), "%s %s" % [troop, part])
				assert(texture.atlas == Skins.pages(troop)[variant])
			var body := entry.body.get_image() as Image
			var head: Vector2i = Vector2i(entry.head_center)
			assert(body.get_pixelv(head).a > 0.0 and entry.headless.get_image().get_pixelv(head).a == 0.0)
			assert(_pieces(entry.head.get_image()) == 1, "%s: the cut head is one clean piece" % troop)
			assert(entry.weapon.get_image().get_pixelv(Vector2i(entry.pivot)).a > 0.5, "%s: the weapon pivots in the hand" % troop)
			assert(_visible_bytes(entry.corpse) == _visible_bytes(entry.portrait))
			assert(entry.weapon_kind == look.weapon)
			# Riders without a shield (the khanate's horse archer, the dead rider) have nothing to block with.
			var guard := Art.guard_layers(unit, troop, variant)
			if Skins.geometry(troop).has("shield_center"):
				assert(not guard.is_empty() and guard.shield.get_size() == Vector2(240, 244), "%s blocks with its shield" % troop)
			else:
				assert(guard.is_empty(), "%s has no shield to raise" % troop)
		# Cut from the saddle: the rider alone, and the horse lying on its own.
		var foot := unit.duplicate(true)
		foot.mounted = false
		var alone := Art.layers_for(foot, troop, 0)
		var rider := alone.corpse.get_image() as Image
		assert(rider.get_size() == Vector2i(240, 244) and rider.get_pixel(225, 150).a == 0.0, "%s: no horse under the rider" % troop)
		var horse := Art.mount_corpse(unit, Vector2i(240, 244), troop)
		if Skins.FACTIONS[Skins.home_of(troop)].get("mount_row", false):
			assert(Skins.sprite(troop, Skins.MOUNT_PART, 0) != null, "%s: the faction's own horse lies on" % troop)
		assert(horse.get_used_rect().size.x > 200 and horse.get_pixel(80, 60).a == 0.0, "%s: the horse lies without its rider" % troop)
	# Other factions still use the original sheets.
	for pair in [["f2a", "kin"], ["p1", "pact"]]:
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
	# Hired Nordmark troops follow the banner too: the blue cloth takes its colour.
	var blue := Art.sprite("n2", "player").get_image().get_data()
	Art.select_player_banner(0)
	assert(Art.sprite("n2", "player").get_image().get_data() != blue, "Nordmark cloth follows the banner")
	assert(Art.sprite("d2", "player").get_image().get_data() == amber, "banner cache must not go stale")
	print("Heraldic tests passed: Dominion, Nordmark, Empire, Khanate and Undead foot and mounted troops, four variants, all death states and banners")
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

## Separate opaque pieces (8-connected): stray specks around a cut show up as extra pieces.
func _pieces(image: Image) -> int:
	var w := image.get_width()
	var h := image.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var count := 0
	for start in w * h:
		if seen[start] == 1 or image.get_pixel(start % w, start / w).a < 12.0 / 255.0: continue
		count += 1
		var stack := [start]
		seen[start] = 1
		while not stack.is_empty():
			var i: int = stack.pop_back()
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var x := i % w + ox
					var y := i / w + oy
					if x < 0 or y < 0 or x >= w or y >= h: continue
					var j := y * w + x
					if seen[j] == 0 and image.get_pixel(x, y).a >= 12.0 / 255.0:
						seen[j] = 1
						stack.append(j)
	return count
