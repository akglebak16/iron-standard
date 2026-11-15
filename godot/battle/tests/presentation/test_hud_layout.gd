extends SceneTree
const Controls = preload("res://apps/godot/presentation/battle/hud/battle_controls.gd")
const GameSkin = preload("res://ui/game_theme.gd")
const EPSILON := 0.04 # Chrome rounds layout to 1/64 px.

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://battle/tests/fixtures/hud_layout.json"))
	var controls := Controls.new()
	controls.theme = GameSkin.build()
	root.add_child(controls)
	for resolution: String in fixture:
		var dims := resolution.split("x")
		root.size = Vector2i(int(dims[0]), int(dims[1]))
		await process_frame
		await process_frame
		controls._layout_controls()
		var expected: Dictionary = fixture[resolution]
		for pair in [[controls._hero, "#bhero"], [controls._commands, "#borders"], [controls._orders_row, "#bords"],
			[controls._groups, "#bgroups"], [controls._order_buttons[0], ".ord"], [controls._group_buttons[0], ".grp"],
			[controls._score, "#btop"], [controls._clock, "#btimer"], [controls._playback, "#bbtns"],
			[controls._stamina, "#bhero .bar"], [controls._weapons, "#bhero .wsw"]]:
			var rect: Rect2 = pair[0].get_global_rect()
			var source: Dictionary = expected[pair[1]]
			# Font hinting rounds the two digit advances by 0.19 px in the narrow score plaque.
			var size_tolerance := 0.25 if pair[1] == "#btop" and root.size.x <= 760 else EPSILON
			assert(rect.position.distance_to(Vector2(source.x, source.y)) < size_tolerance, resolution + " " + pair[1] + " position " + str(rect))
			assert(rect.size.distance_to(Vector2(source.w, source.h)) < size_tolerance, resolution + " " + pair[1] + " size " + str(rect))
	controls.free()
	print("HUD layout tests passed")
	quit()
