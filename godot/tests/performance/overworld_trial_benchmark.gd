extends Node
## Run with a window and -- --overworld-benchmark <output stem>. Writes .json and .png.

const TRIAL := preload("res://apps/godot/presentation/overworld/overworld_trial.tscn")
const DURATION_MS := 12000


func _ready() -> void:
	call_deferred("_measure")


func _measure() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "--overworld-benchmark" or DisplayServer.get_name() == "headless":
		push_error("Run in a window and pass one output path stem after --")
		get_tree().quit(1)
		return
	var tree := get_tree()
	var root := tree.root
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var scene := TRIAL.instantiate()
	root.add_child(scene)
	var camera := scene.get_node("Camera2D") as Camera2D
	var renderer := scene.get_node("WorldMap") as IronWorldMapRenderer
	var bridge := scene.get_node("%Bridge") as CheckButton
	var frame_times: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	var first_upload_ms := -1.0
	var ready_ms := -1.0
	var edited := false
	var reloaded := false
	while true:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var elapsed_ms := (now - started) / 1000.0
		frame_times.append((now - previous) / 1000.0)
		previous = now
		if elapsed_ms >= DURATION_MS:
			break
		if ready_ms < 0:
			var status := renderer.trial_status()
			if first_upload_ms < 0 and status.uploaded > 0:
				first_upload_ms = elapsed_ms
			if status.uploaded > 0 and not status.busy:
				ready_ms = elapsed_ms
		var travel := smoothstep(0.6, 3.0, elapsed_ms / 1000.0)
		travel -= smoothstep(3.2, 5.0, elapsed_ms / 1000.0)
		travel -= 0.9 * smoothstep(6.2, 7.5, elapsed_ms / 1000.0)
		travel += 0.9 * smoothstep(8.0, 9.3, elapsed_ms / 1000.0)
		camera.position = Vector2(1280 + travel * 580, 760 + travel * 220)
		camera.zoom = Vector2.ONE * (1.35 + 0.32 * sin(elapsed_ms * TAU / 4000.0))
		if elapsed_ms >= 5100 and not edited:
			bridge.button_pressed = true
			edited = true
		if elapsed_ms >= 9300 and not reloaded:
			renderer.reload_trial()
			reloaded = true

	frame_times.sort()
	var report := {
		"resolution": [root.size.x, root.size.y],
		"frames": frame_times.size(),
		"p50_ms": _percentile(frame_times, 0.50),
		"p95_ms": _percentile(frame_times, 0.95),
		"p99_ms": _percentile(frame_times, 0.99),
		"max_ms": frame_times.back(),
		"first_upload_ms": first_upload_ms,
		"initial_queue_drained_ms": ready_ms,
		"chunks": renderer.trial_status(),
	}
	var file := FileAccess.open(args[1] + ".json", FileAccess.WRITE)
	if file == null:
		push_error("Could not write the benchmark report")
		tree.quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	await RenderingServer.frame_post_draw
	tree.quit(root.get_texture().get_image().save_png(args[1] + ".png"))


func _percentile(values: Array[float], fraction: float) -> float:
	return values[ceili(values.size() * fraction) - 1]
