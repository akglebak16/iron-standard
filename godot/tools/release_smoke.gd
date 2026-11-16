extends Node
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
const Columns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
## Explicit checks: assert expressions do not run in exported release builds.
const Europe = preload("res://core/campaign/data/europe_data.gd")
const World = preload("res://core/campaign/world/world_state.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const Bridge = preload("res://core/campaign/application/battle_encounter.gd")
const SaveStore = preload("res://adapters/persistence/save_store.gd")
const CameraTransition = preload("res://tests/integration/app/camera_transition_check.gd")

func _ready() -> void:
	var data := Europe.new()
	if not ContentLoader.populate(data):
		fail("Europe content")
		return
	var world = World.create(4242, data, "emp", ContentLoader.registry())
	if world == null or world.roster.parties.is_empty() or world.player.troops.is_empty():
		fail("Campaign initialization")
		return
	if not SaveStore.save(world, "user://release-smoke-save.json"):
		fail("Checkpoint publication")
		return
	var restored = SaveStore.load_state(data, "user://release-smoke-save.json")
	if restored == null or restored.roster.rng.state != world.roster.rng.state:
		fail("Checkpoint restoration")
		return
	restored.dispose()
	restored = null
	var menu = load("res://apps/godot/composition/main_menu.tscn").instantiate()
	menu.set_meta("release_smoke_child", true)
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	if menu.get_child_count() == 0:
		fail("Main menu initialization")
		return
	var bridge := Bridge.new(ContentLoader.registry(), RandomNumberGenerator.new())
	var opponent: Dictionary = world.roster.parties[0]
	var setup = bridge.make_setup(world, opponent)
	var solver := Contacts.create()
	if not solver.is_valid():
		fail("Native contact adapter unavailable")
		return
	var movement := Movement.create()
	var columns := Columns.create()
	if not movement.is_valid() or columns == null or not ClassDB.class_exists("IronBattleSprites") or not ClassDB.class_exists("IronBattleEffects"):
		fail("Native battle adapters unavailable")
		return
	var session = Factory.create(setup, bridge.troops, bridge.gear, bridge.perks, bridge.companions, solver, movement, columns)
	if session == null:
		fail("Battle initialization")
		return
	if session._state.add_unit(session._state.units[0]):
		fail("Duplicate battle insertion accepted in release")
		return
	for i in 60: session.advance(1.0 / 60.0)
	if session.snapshot().tick != 60:
		fail("Battle did not advance")
		return
	if session._state.native_movement_steps != 60 or session._state.native_movement_failures != 0 or session.snapshot(true).render.size() == 0:
		fail("Native movement/snapshot failed")
		return
	if session._state.native_contact_failures != 0:
		fail("Native contact adapter rejected valid battle")
		return
	world.dispose()
	world = null
	menu.queue_free()
	session = null
	bridge = null
	await get_tree().process_frame
	var camera_error := await CameraTransition.run(get_tree())
	if not camera_error.is_empty():
		fail(camera_error)
		return
	print("Release smoke passed; debug=%s" % OS.is_debug_build())
	get_tree().quit(0)

func fail(stage: String) -> void:
	push_error("Release smoke failed: " + stage)
	get_tree().quit(1)
