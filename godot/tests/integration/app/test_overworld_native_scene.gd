extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://apps/godot/presentation/overworld/render_probe.tscn") as PackedScene
	assert(packed != null)
	var scene := packed.instantiate()
	assert(scene.get_class() == "IronOverworldRenderProbe", "The native class must load in the scene")
	root.add_child(scene)
	await process_frame
	assert(root.get_camera_2d() == scene.get_node("Camera2D"))
	scene.free()
	print("Overworld native scene tests passed")
	quit()
