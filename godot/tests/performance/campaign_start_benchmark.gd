extends Node
## Windowed startup diagnostics. Uses the normal menu request and waits for the
## first rendered frame after both map baking and campaign input are ready.
const Options = preload("res://apps/godot/composition/game_options.gd")
const SEED := 4242
const TIMEOUT_US := 30_000_000

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Campaign startup benchmark requires a window")
		get_tree().quit(1)
		return
	call_deferred("_run")

func _run() -> void:
	var coordinator := get_parent()
	var samples: Array[Dictionary] = []
	for attempt in 2:
		Options.seed_value = SEED
		var menu: Node = coordinator._mode
		menu._create()
		await get_tree().process_frame
		var start := Time.get_ticks_usec()
		menu._start()
		while true:
			await get_tree().process_frame
			var active: Node = coordinator._mode
			if active != menu and active.startup_marks_us.has("map_painted") and active._ready_to_play:
				await RenderingServer.frame_post_draw
				var marks := {}
				for stage in active.startup_marks_us:
					marks[stage] = (int(active.startup_marks_us[stage]) - start) / 1000.0
				samples.append({
					"attempt": "first_in_process" if attempt == 0 else "repeat_in_process",
					"ready_ms": (Time.get_ticks_usec() - start) / 1000.0,
					"marks_ms_since_start": marks,
					"parties": active.state.roster.parties.size(),
				})
				break
			if Time.get_ticks_usec() - start >= TIMEOUT_US:
				push_error("Campaign did not reach a rendered playable map")
				get_tree().quit(1)
				return
		if attempt == 0:
			var campaign: Node = coordinator._mode
			coordinator._request_menu()
			while coordinator._mode == campaign:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
	print(JSON.stringify({
		"benchmark": "campaign_start", "seed": SEED, "debug": OS.is_debug_build(),
		"engine": Engine.get_version_info().string, "samples": samples,
	}))
	get_tree().quit(0)
