extends SceneTree
## Block with a shield: the figure without its resting shield plus the shield must repaint the troop
## sheet, the pose must match the native renderer, and blocks must raise and lower the shield.
const Art = preload("res://apps/godot/visuals/original_art.gd")
const UnitArt = preload("res://apps/godot/presentation/battle/unit_art.gd")
const UnitView = preload("res://apps/godot/presentation/battle/unit_view.gd")
const Motion = preload("res://apps/godot/presentation/battle/unit_motion.gd")
const Event = preload("res://core/battle/combat_event.gd")
## Foot and mounted, every shield shape and the undead.
const TROOPS := ["n1|nord", "e2|emp", "k1|khan", "n3c|nord", "e3c|emp", "k2c|khan", "s3|undead", "f2|player"]
## Foot figures repaint exactly. On horseback the sheet draws the horse a little differently from its
## component, so the 2 px rim around the old shield may differ (all mounted troops: at most 113 px).
const MAX_MOUNTED_DIFFERENT_PIXELS := 120

func _initialize() -> void:
	for key in TROOPS:
		for variant in 4:
			_check_repaint(key, variant)
	_check_composed_hero()
	_check_pose()
	_check_reactions()
	print("Shield guard tests passed")
	quit()

func _unit(key: String, id := 1) -> Dictionary:
	var definition: Dictionary = Art.MANIFEST.troops[key]
	return {"id": id, "look": definition.look, "faction": key.get_slice("|", 1), "hero": false, "companion": false,
		"mounted": definition.look.get("horse") != null, "side": 0}

static func _image(texture: Texture2D) -> Image:
	var image := texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image

func _check_repaint(key: String, variant: int) -> void:
	var unit := _unit(key)
	var troop := key.get_slice("|", 0)
	var parts := Art.guard_layers(unit, troop, variant)
	assert(not parts.is_empty(), "guard layers " + key)
	var body := _image(Art.layers_for(unit, troop, variant).body)
	var repaint := Image.create(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8)
	for layer: Array in parts.layers:
		var image := _image(layer[0])
		repaint.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(layer[1]))
	var shield := _image(parts.shield)
	repaint.blend_rect(shield, Rect2i(Vector2i.ZERO, shield.get_size()), Vector2i(parts.shield_origin))
	var different := 0
	for y in body.get_height():
		for x in body.get_width():
			# Premultiplied: the import bleeds colour into fully transparent pixels.
			var a := body.get_pixel(x, y)
			var b := repaint.get_pixel(x, y)
			var delta := Color(a.r * a.a - b.r * b.a, a.g * a.a - b.g * b.a, a.b * a.a - b.b * b.a, a.a - b.a)
			if maxf(maxf(absf(delta.r), absf(delta.g)), maxf(absf(delta.b), absf(delta.a))) > 0.1:
				different += 1
	assert(different <= (MAX_MOUNTED_DIFFERENT_PIXELS if unit.mounted else 0), "%s v%d repaints %d pixels differently" % [key, variant, different])
	assert(Rect2(Vector2.ZERO, body.get_size()).has_point(parts.shield_center))

func _check_composed_hero() -> void:
	var hero := {"id": 1, "look": {"helm": "nasal", "armor": "mail", "weapon": "sword", "shield": "kite"},
		"faction": "player", "hero": true, "companion": false, "mounted": false, "side": 0}
	var parts := Art.guard_layers(hero)
	assert(parts.layers.size() == 1 and parts.shield != null)
	var unarmed := hero.duplicate(true)
	unarmed.look.erase("shield")
	assert(Art.guard_layers(unarmed).is_empty(), "no shield, no raised shield")
	assert(Art.guard_layers(_unit("n2a|nord")).is_empty(), "archers carry no shield")
	# Heraldic Dominion figures bring their own rows: the shield lies where the figure painted it.
	for troop in ["d1", "d2", "d3", "d2s"]:
		for faction in ["dom", "player"]:
			var heraldic := _unit(troop + "|dom")
			heraldic.faction = faction
			var heraldic_parts := Art.guard_layers(heraldic, troop, 2)
			assert(heraldic_parts.layers.size() == 1 and heraldic_parts.shield != null, "heraldic shield " + troop)
			var painted := _image(Art.layers_for(heraldic, troop, 2).body)
			var repaint := _image(heraldic_parts.layers[0][0])
			var raised := _image(heraldic_parts.shield)
			repaint.blend_rect(raised, Rect2i(Vector2i.ZERO, raised.get_size()), Vector2i.ZERO)
			var different := 0
			for y in painted.get_height():
				for x in painted.get_width():
					var a := painted.get_pixel(x, y)
					var b := repaint.get_pixel(x, y)
					if absf(a.r * a.a - b.r * b.a) + absf(a.g * a.a - b.g * b.a) + absf(a.b * a.a - b.b * b.a) > 0.3: different += 1
			# Only the 2 px band cleared around the shield may differ from the painted figure.
			assert(different < 400, "%s %s: bare figure + shield repaint the figure (%d px off)" % [troop, faction, different])
			assert(_image(heraldic_parts.shield).get_pixelv(Vector2i(heraldic_parts.shield_center)).a > 0.9, "shield centre lies on the shield")
	for troop in ["d3s", "d2x", "d3x"]:
		assert(Art.guard_layers(_unit(troop + "|dom"), troop, 0).is_empty(), "no shield, nothing to raise")

func _check_pose() -> void:
	var body := Motion.body_transform(Vector2(40, 60), 1.3, 0.4, 0.0, false, 0.2, 0.0)
	var native = ClassDB.instantiate("IronBattleSprites") if ClassDB.class_exists("IronBattleSprites") else null
	for raise in [0.0, 0.3, 1.0]:
		for recoil in [0.0, 0.7]:
			var pose := Motion.guard_transform(body, Vector2(76, 158), Vector2(50, 120), raise, recoil)
			if native != null:
				var expected: Transform2D = native.sample_guard(body, Vector2(76, 158), Vector2(50, 120), raise, recoil)
				for i in 3: assert(pose[i].distance_to(expected[i]) < 0.0001, "native guard pose")
	var rest := Motion.guard_transform(body, Vector2(76, 158), Vector2(50, 120), 0.0, 0.0)
	assert(rest.origin.distance_to(body * Vector2(50 - 76, 120 - 158)) < 0.0001, "resting shield stays in place")
	var raised := Motion.guard_transform(body, Vector2(76, 158), Vector2(50, 120), 1.0, 0.0)
	assert((body.affine_inverse() * raised.origin).x > (body.affine_inverse() * rest.origin).x, "raised shield moves to the front")
	assert(Motion.guard_hit(0.0).x == 0.0 and Motion.guard_hit(0.3).x == 1.0 and Motion.guard_hit(1.0).x == 0.0)
	assert(Motion.guard_hit(0.21).y > 0.9 and Motion.guard_hit(0.5).y == 0.0)

func _check_reactions() -> void:
	var view := UnitView.new()
	var block := {"kind": Event.Kind.BLOCK, "target_id": 7}
	view.advance(0.0, [block])
	view.advance(0.05, [])
	assert(view.guard_pose(7).x > 0.0, "a block raises the shield")
	view.advance(0.1, [])
	assert(view.guard_pose(7).x == 1.0)
	view.advance(Motion.GUARD_HIT_SECONDS, [])
	assert(view.guard_pose(7) == Vector2.ZERO, "the shield comes down after the blow")
	var hero := {"id": 3, "blocking": true, "dead": false, "hero": true, "look": {"helm": "nasal", "armor": "mail", "weapon": "sword", "shield": "kite"},
		"faction": "player", "companion": false, "mounted": false, "side": 0}
	view._mark_guard(hero)
	view.advance(0.05, [])
	view.advance(0.1, [])
	assert(view.guard_pose(3).x == 1.0, "held block keeps the shield up")
	view._mark_guard(hero)
	assert(hero.block_hold == 1.0 and hero.block_flash == 0.0, "the arc shows the held block")
	view.advance(0.0, [{"kind": Event.Kind.BLOCK, "target_id": 3}])
	view.advance(0.05, [])
	view._mark_guard(hero)
	assert(hero.block_flash > 0.5, "a blow taken makes the arc flare")
	view.advance(Motion.BLOCK_FLASH_SECONDS, [])
	view._mark_guard(hero)
	assert(hero.block_flash == 0.0)
	hero.blocking = false
	view._mark_guard(hero)
	view.advance(Motion.GUARD_HOLD_LOWER_SECONDS + 0.01, [])
	view.advance(Motion.GUARD_HIT_SECONDS, [])
	assert(view.guard_pose(3) == Vector2.ZERO)
