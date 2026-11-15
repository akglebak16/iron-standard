extends SceneTree
const World = preload("res://campaign/world/world_state.gd")
const Europe = preload("res://campaign/data/europe_data.gd")

func _initialize() -> void:
	var data := Europe.new()
	assert(data.load_data())
	var world = World.create(4242, data)
	var reference: WeakRef = weakref(world)
	var wars_reference: WeakRef = weakref(world.wars)
	world.dispose()
	world.dispose() # Closing a context twice is harmless.
	world = null
	assert(reference.get_ref() == null)
	assert(wars_reference.get_ref() == null)
	print("World disposal tests passed")
	quit(0)
