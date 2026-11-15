extends SceneTree
## Windowed layer isolation diagnostic. Hidden layers are never an acceptance result.
const World = preload("res://apps/godot/composition/world_demo.tscn")
const Options = preload("res://apps/godot/composition/game_options.gd")
const Stats = preload("res://tests/performance/battle_benchmark.gd")
var world: Node
var output := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	Options.seed_value = 4242
	Options.continue_game = false
	world = World.instantiate()
	world.cache_static_artwork = false
	root.add_child(world)
	await process_frame
	await process_frame
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var results: Array[Dictionary] = []
	for phase in ["baseline", "paused", "no_map", "no_relief", "no_farms", "no_roads", "no_rivers", "no_settlements", "no_hud"]:
		world.state.clock.paused = phase != "baseline"
		world.map_view.visible = phase != "no_map"
		world.hud.visible = phase != "no_hud"
		for child in world.map_view.get_children():
			if child is CanvasItem:
				var script: Script = child.get_script()
				var file := script.resource_path.get_file() if script != null else ""
				child.visible = not ((phase == "no_relief" and file == "relief_layer.gd") or (phase == "no_farms" and file == "farm_layer.gd") or (phase == "no_roads" and file == "road_layer.gd") or (phase == "no_rivers" and file == "river_layer.gd") or (phase == "no_settlements" and file == "settlement_layer.gd"))
		var frames: Array[int] = []
		var cpu: Array[int] = []
		var gpu: Array[int] = []
		var setup: Array[int] = []
		var draws := 0.0
		for i in 180:
			var start := Time.get_ticks_usec()
			await process_frame
			if i < 60: continue
			frames.append(Time.get_ticks_usec() - start)
			cpu.append(roundi(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) * 1000.0))
			gpu.append(roundi(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()) * 1000.0))
			setup.append(roundi(RenderingServer.get_frame_setup_time_cpu() * 1000.0))
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var report := {"phase":phase,"frame":Stats.stats(frames),"render_cpu":Stats.stats(cpu),"render_gpu":Stats.stats(gpu),"render_setup":Stats.stats(setup),"draw_calls_mean":draws / 120.0}
		results.append(report)
		print(JSON.stringify(report))
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify({"seed":4242,"viewport":str(root.size),"debug":OS.is_debug_build(),"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"diagnostics_only":true,"phases":results}, "\t"))
	world.queue_free()
	await process_frame
	quit(0)
