extends SceneTree
## CPU-only effect benchmark, not FPS or full-battle acceptance.
## 2000 fatalities over 60 simulated seconds, five repetitions; optional --baseline=res://... --out=...
const Effects = preload("res://apps/godot/presentation/battle/impact_effects.gd")
const Event = preload("res://core/battle/combat_event.gd")
const STEP := 1.0 / 60.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var implementations := {"current": Effects}
	var out := "user://gore-benchmark.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="): implementations.baseline = load(arg.trim_prefix("--baseline="))
		elif arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	var results: Array[Dictionary] = []
	for repeat_index in 5:
		for name in implementations:
			var effects: RefCounted = implementations[name].new()
			effects._rng.seed = 42055 + repeat_index
			var samples: Array[int] = []
			var maximum_active := 0
			var maximum_settled := 0
			var casualties := 0
			# Warm up appearance textures and native adapter before timing.
			for tick in 120:
				var warmup: Array[Dictionary] = [_event(tick)]
				effects.advance(STEP, warmup)
			effects.blood_enabled = false
			effects.blood_enabled = true
			for tick in 3600:
				var events: Array[Dictionary] = []
				if tick < 2000:
					events.append(_event(tick))
					casualties += 1
				var started := Time.get_ticks_usec()
				effects.advance(STEP, events)
				samples.append(Time.get_ticks_usec() - started)
				maximum_active = maxi(maximum_active, effects._parts._active.size())
				maximum_settled = maxi(maximum_settled, effects._parts._settled.size())
			samples.sort()
			var total := 0
			for sample in samples: total += sample
			results.append({"implementation": name, "repeat": repeat_index + 1, "casualties": casualties,
				"mean_us": float(total) / samples.size(), "p95_us": samples[int(samples.size() * 0.95)],
				"p99_us": samples[int(samples.size() * 0.99)], "maximum_active": maximum_active,
				"maximum_settled": maximum_settled, "native": effects._native != null})
	var report := {"method": "CPU effects only; 3600 fixed steps, 2000 fatalities, 120 warmup steps, five repeats",
		"engine": Engine.get_version_info().string, "results": results}
	FileAccess.open(out, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print(JSON.stringify(report))
	quit()

func _event(index: int) -> Dictionary:
	return {"kind": Event.Kind.DOWN, "position": Vector2(index % 50 * 20, index / 50 * 20), "target_id": index,
		"impact_style": Event.ImpactStyle.BLOOD, "attack": Event.Attack.MELEE,
		"melee_impact": Event.MeleeImpact.CUT if index % 3 != 0 else Event.MeleeImpact.BLUNT,
		"damage_fraction": 0.4, "impact_direction": Vector2.RIGHT,
		"source_hero": false, "target_hero": false, "target_companion": false,
		"target_visual": {"side": 1, "faction": "emp", "look": {"helm": "kettle", "armor": "mail", "weapon": "sword", "shield": null},
			"mounted": false, "facing": 0.0, "hero": false, "companion": false}}
