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
	menu._start()
	assert(Options.culture == "khan" and Options.hero_name == "Проверка" and Options.banner == 2)
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
