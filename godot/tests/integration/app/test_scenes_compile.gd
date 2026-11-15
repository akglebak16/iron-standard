extends SceneTree
## Every app scene and script must compile: a parse error in a scene script is invisible to the logic tests.
const PATHS := ["res://apps/godot/composition/world_demo.tscn", "res://apps/godot/composition/main_menu.tscn", "res://apps/godot/composition/main.tscn", "res://apps/godot/composition/siege_demo.tscn"]

func _initialize() -> void:
	for path in PATHS:
		var scene := load(path) as PackedScene
		assert(scene != null, "cannot load " + path)
		var state := scene.get_state()
		for i in state.get_node_count():
			for j in state.get_node_property_count(i):
				var value: Variant = state.get_node_property_value(i, j)
				if value is GDScript:
					assert((value as GDScript).can_instantiate(), "script does not compile in " + path + ": " + (value as GDScript).resource_path)
	for dir_path in ["res://apps/godot/composition", "res://apps/godot/presentation/campaign", "res://core/campaign/world"]:
		var dir := DirAccess.open(dir_path)
		for f in dir.get_files():
			if f.ends_with(".gd"):
				var script := load(dir_path + "/" + f) as GDScript
				assert(script != null and script.can_instantiate(), "script does not compile: " + dir_path + "/" + f)
	print("Scene compile tests passed")
	quit(0)
