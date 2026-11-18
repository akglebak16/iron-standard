extends SceneTree
const Menu = preload("res://apps/godot/composition/main_menu.tscn")
const QuickSetup = preload("res://apps/godot/composition/quick_battle_setup.gd")
const Options = preload("res://apps/godot/composition/game_options.gd")
const Art = preload("res://apps/godot/visuals/original_art.gd")
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Troops = preload("res://core/troops/data/catalog.gd")

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	root.size = Vector2i(1366, 768)
	var menu := Menu.instantiate()
	root.add_child(menu)
	menu._create()
	for i in 10: await process_frame
	menu._name.text = "Проверка"
	_click(menu._banner_buttons[2])
	assert(Options.banner == 2 and Art.palette("player").c1 == Art.BANNERS[2].c1)
	_click(menu._buttons["khan"])
	assert(menu._picked == "khan" and menu._name.text == "Проверка")
	# the look editor (#151): every choice redraws the figure and is kept for the new game
	var before: PackedByteArray = menu._preview.texture.get_image().get_data()
	_click(menu._face_buttons.skin["#b97d58"])
	_click(menu._face_buttons.hair["#dcb860"])
	_click(menu._face_buttons.beard[2])
	assert(menu._face_buttons.stache.disabled, "no moustache with a beard")
	_click(menu._face_buttons.beard[0])
	assert(not menu._face_buttons.stache.disabled)
	_click(menu._face_buttons.stache)
	if not Options.hero_face.scar: _click(menu._face_buttons.scar)
	if Options.hero_face.bald: _click(menu._face_buttons.bald)
	assert(Options.hero_face == {"skin": "#b97d58", "hair": "#dcb860", "beard": 0, "stache": 1, "bald": false, "scar": true})
	assert(menu._face_buttons.skin["#b97d58"].button_pressed and not menu._face_buttons.skin["#e8c3a0"].button_pressed)
	assert(menu._preview.texture.get_image().get_data() != before)
	var shown: PackedByteArray = menu._preview.texture.get_image().get_data()
	_click(menu._face_buttons.bald)
	assert(Options.hero_face.bald and menu._preview.texture.get_image().get_data() != shown)
	var dice: Button = menu._dialog.find_child("RandomLook", true, false)
	var seen := {}
	for i in 12:
		_click(dice)
		seen[str(Options.hero_face)] = true
	assert(seen.size() > 1, "«Случайно» changes the look")
	# background (#152): it only places the start points, the card says where
	menu._dialog._scroll.ensure_control_visible(menu._origin_buttons["merchant"])
	for i in 3: await process_frame
	_click(menu._origin_buttons["retainer"])
	assert(Options.origin == "retainer" and menu._origin_buttons["retainer"].button_pressed and not menu._origin_buttons["smith"].button_pressed)
	assert(menu._origin_note.text.contains("Сила +1, Стойкость +1"))
	assert(menu._dialog.find_child("StartPoints", true, false) == null, "no separate point split")
	menu._start()
	assert(Options.culture == "khan" and Options.hero_name == "Проверка" and Options.banner == 2)
	# the screen in two columns: the hero on the left, the factions with their crests on the right (#175)
	var crest: TextureRect = menu._buttons["khan"].find_child("Crest", true, false)
	assert(crest != null and crest.texture == Art.crest("khan"))
	for id in menu._buttons:
		assert(menu._buttons[id].find_child("Crest", true, false).texture != null, id)
	# reopening the screen keeps the last look
	var kept: Dictionary = Options.hero_face.duplicate()
	menu._create()
	for i in 5: await process_frame
	assert(menu._face == kept)
	menu._quick()
	for i in 10: await process_frame
	_click(menu._quick_buttons.me["emi"])
	_click(menu._quick_buttons.foe["bandit"])
	_click(menu._quick_buttons.size[200])
	var setup = QuickSetup.build(menu._quick_options, 1819)
	assert(setup != null and setup.quick and setup.player_faction == "player" and setup.enemy_faction == "bandit")
	assert(not setup.enemy_leader_name.is_empty(), "the original quick battle includes an enemy leader")
	assert(_count(setup.player_army) == 200 and _count(setup.enemy_army) == 204)
	assert(setup.companion_profiles.is_empty() and setup.hero_position == Vector2(730, 850))
	assert(setup.hero_profile.eq.horse == null)
	var troops := Troops.new()
	assert(ContentLoader.populate(troops))
	for stack in setup.player_army: assert(troops.get_troop(stack.type).fac == "emi")
	for stack in setup.enemy_army: assert(troops.get_troop(stack.type).fac == "bandit")
	assert(QuickSetup.build(menu._quick_options, 1819).player_army == setup.player_army)
	for count in QuickSetup.SIZES:
		var mounted = QuickSetup.build({"me":"khan", "foe":"emp", "size":count}, 1820)
		assert(_count(mounted.player_army) == count and _count(mounted.enemy_army) == count + 4)
		assert(mounted.hero_profile.eq.horse == "horse_riding")
	assert(QuickSetup.build({"me":"invalid", "size":50}) == null)
	assert(QuickSetup.build({"me":"nord", "size":-1}) == null)
	assert(QuickSetup.build({"size":{}}) == null)
	menu.free()
	Options.banner = 0
	Options.hero_face = {}
	Options.origin = "smith"
	Art.select_player_banner(0)
	print("Start options tests passed")
	quit()

func _count(stacks: Array) -> int:
	var count := 0
	for stack in stacks: count += int(stack.n)
	return count

func _click(button: Button) -> void:
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
