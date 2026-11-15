extends Node
## Explicit checks: assert expressions do not run in exported release builds.
const Europe = preload("res://campaign/data/europe_data.gd")
const World = preload("res://campaign/world/world_state.gd")
const Factory = preload("res://battle/application/factory.gd")
const Bridge = preload("res://apps/godot/composition/world_battle_bridge.gd")
const SaveStore = preload("res://apps/godot/composition/save_store.gd")

func _ready() -> void:
	var data := Europe.new()
	if not data.load_data():
		fail("Europe content")
		return
	var world = World.create(4242, data, "emp")
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
	var bridge := Bridge.new()
	var opponent: Dictionary = world.roster.parties[0]
	var setup = bridge.make_setup(world, opponent)
	var session = Factory.create(setup, bridge.troops, bridge.gear, bridge.perks, bridge.companions)
	if session == null:
		fail("Battle initialization")
		return
	for i in 60: session.advance(1.0 / 60.0)
	if session.snapshot().tick != 60:
		fail("Battle did not advance")
		return
	world.dispose()
	world = null
	menu.queue_free()
	session = null
	bridge = null
	await get_tree().process_frame
	print("Release smoke passed; debug=%s" % OS.is_debug_build())
	get_tree().quit(0)

func fail(stage: String) -> void:
	push_error("Release smoke failed: " + stage)
	get_tree().quit(1)
