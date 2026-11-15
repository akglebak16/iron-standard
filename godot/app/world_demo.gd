extends Node
## Demo of the world map: generates the continent for a seed and lets you pan and zoom.
## Seed: `-- --seed=123` on the command line.
const MapView = preload("res://campaign/presentation/world_map_view.gd")
const WorldCamera = preload("res://campaign/presentation/world_camera.gd")

var map_view: Node2D
var camera: Camera2D

func _ready() -> void:
	var label := Label.new()
	label.text = "Строю карту…"
	label.position = Vector2(24, 24)
	var layer := CanvasLayer.new()
	layer.add_child(label)
	add_child(layer)
	await get_tree().process_frame
	var seed_value := 12345
	var focus := PackedFloat64Array()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.substr(7))
		elif arg.begins_with("--focus="):
			for part in arg.substr(8).split(","):
				focus.append(float(part))
	map_view = MapView.new()
	add_child(map_view)
	camera = WorldCamera.new()
	add_child(camera)
	camera.make_current()
	camera.fit_all()
	if focus.size() == 3:
		camera.position = Vector2(focus[0], focus[1])
		camera.zoom = Vector2(focus[2], focus[2])
	map_view.ready_to_show.connect(func(): label.text = "Колесо — масштаб, ПКМ/ЛКМ — двигать, WASD — стрелки  (зерно %d)" % seed_value)
	map_view.build(seed_value)
