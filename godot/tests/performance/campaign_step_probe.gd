extends SceneTree
## Step cost of the world through the undead crisis, per day (headless, no player):
##   godot --headless --path godot --script res://tests/performance/campaign_step_probe.gd -- --seed=11 --days=80 --from=50
const Sim = preload("res://tests/performance/campaign_simulator.gd")
func _initialize() -> void:
	var seed_value := 11
	var days := 90
	var from_day := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed_value = int(a.trim_prefix("--seed="))
		if a.begins_with("--days="): days = int(a.trim_prefix("--days="))
		if a.begins_with("--from="): from_day = int(a.trim_prefix("--from="))
	var w: RefCounted = Sim.create_world(seed_value)
	w.threat_map()
	var cur := {"step_us": 0, "step_max": 0, "steps": 0, "hour_max": 0, "over20": 0}
	var all := {"max": 0, "over20": 0, "over40": 0, "steps": 0, "sum": 0}
	var hour_us := [0]
	var step_cb := func(dh: float) -> void:
		var t := Time.get_ticks_usec()
		w.step(dh)
		hour_us[0] = 0
		var d := Time.get_ticks_usec() - t
		cur.step_us += d
		cur.steps += 1
		cur._last = d
	var hour_cb := func() -> void:
		var t := Time.get_ticks_usec()
		w.hour_tick()
		var d := Time.get_ticks_usec() - t
		cur.hour_max = maxi(cur.hour_max, d)
		cur._last = int(cur.get("_last", 0)) + d
	var last_day := -1
	while int(w.hours_passed) < days * 24:
		var dday := int(w.clock.day)
		if dday != last_day:
			if last_day >= from_day: _print(last_day, cur, w)
			last_day = dday
			cur.clear()
			cur.merge({"step_us": 0, "step_max": 0, "steps": 0, "hour_max": 0, "over20": 0})
		cur._last = 0
		var did: bool = w.clock.advance_one(step_cb, hour_cb) if w.clock.backlog() >= 1.0 else false
		if not did:
			w.clock.add_time(0.2)
			continue
		var full: int = cur._last
		cur.step_max = maxi(cur.step_max, full)
		if full > 20000: cur.over20 += 1
		if dday >= from_day:
			all.steps += 1
			all.sum += full
			all.max = maxi(all.max, full)
			if full > 20000: all.over20 += 1
			if full > 40000: all.over40 += 1
	print("TOTAL steps %d avg %.2f ms max %.1f ms, >20ms %d, >40ms %d" % [all.steps, all.sum / 1000.0 / maxi(1, all.steps), all.max / 1000.0, all.over20, all.over40])
	quit(0)

func _print(day: int, c: Dictionary, w) -> void:
	var und := 0
	for p in w.roster.parties:
		if p.get("fac") == "undead" and p.kind != "camp": und += 1
	print("day %3d parties %3d undead %2d | step avg %5.2f max %6.1f ms | hour max %6.1f ms | steps>20ms %d" % [day, w.roster.parties.size(), und,
		c.step_us / 1000.0 / maxi(1, c.steps), c.step_max / 1000.0, c.hour_max / 1000.0, c.over20])
