extends SceneTree
## Campaign simulator runner (docs/modules/ai/DESIGN.md §7.2). Headless, without the player:
##   godot --headless --path godot --script res://tests/performance/campaign_sim.gd -- --days=200 --seeds=11,22,33 --out=<dir>
## Per seed: campaign_sim_<seed>.json (full report) and PNG heat maps of lords, fights, sieges and the final threat map.
## All seeds: summary.json and summary.md (the short table, also printed). Output defaults to user://campaign_sim.
const Simulator = preload("res://tests/performance/campaign_simulator.gd")

const DEFAULT_DAYS := 200
const DEFAULT_SEEDS := [11, 22, 33]
const SCALE := 6  # pixels per heat cell in the PNGs
const SEA := Color(0.16, 0.2, 0.26)
const LAND := Color(0.86, 0.83, 0.74)

func _initialize() -> void:
	var days := DEFAULT_DAYS
	var seeds: Array = DEFAULT_SEEDS.duplicate()
	var out := "user://campaign_sim"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--days="):
			days = maxi(1, int(arg.trim_prefix("--days=")))
		elif arg.begins_with("--seeds="):
			seeds = Array(arg.trim_prefix("--seeds=").split(",", false)).map(func(s): return int(s))
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var rows: Array = []
	for seed_value in seeds:
		print("campaign sim: seed %d, %d days..." % [seed_value, days])
		var result := Simulator.run(int(seed_value), days)
		if result.is_empty():
			push_error("campaign sim: world for seed %d was not created" % seed_value)
			quit(1)
			return
		var report: Dictionary = result.report
		_write(out.path_join("campaign_sim_%d.json" % seed_value), JSON.stringify(report, "\t"))
		_heat_png(report, "lords", Color(0.85, 0.1, 0.05)).save_png(out.path_join("heat_lords_%d.png" % seed_value))
		_heat_png(report, "fights", Color(0.6, 0.0, 0.5)).save_png(out.path_join("heat_fights_%d.png" % seed_value))
		_heat_png(report, "sieges", Color(0.1, 0.1, 0.1)).save_png(out.path_join("heat_sieges_%d.png" % seed_value))
		_threat_png(report).save_png(out.path_join("threat_final_%d.png" % seed_value))
		rows.append(report.summary)
		result.world.dispose()
		print(JSON.stringify(report.summary))
	var meta := {"engine": Engine.get_version_info().string, "debug": OS.is_debug_build(), "cpu": OS.get_processor_name(), "days": days, "seeds": seeds}
	_write(out.path_join("summary.json"), JSON.stringify({"meta": meta, "runs": rows}, "\t"))
	var table := _table(rows, meta)
	_write(out.path_join("summary.md"), table)
	print(table)
	print("campaign sim: written to %s" % ProjectSettings.globalize_path(out))
	quit(0)

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _base(report: Dictionary, cols: int, rows: int) -> Image:
	var heat: Dictionary = report.heat
	var img := Image.create(cols * SCALE, rows * SCALE, false, Image.FORMAT_RGB8)
	for i in cols * rows:
		var land: bool = int(heat.land[i]) == 1
		img.fill_rect(Rect2i((i % cols) * SCALE, (i / cols) * SCALE, SCALE, SCALE), LAND if land else SEA)
	return img

func _dots(img: Image, report: Dictionary, cell: float) -> void:
	for s in report.settlements:
		var c := Color.html(report.colors.get(s.fac, "#444444"))
		var px := int(float(s.x) / cell * SCALE)
		var py := int(float(s.y) / cell * SCALE)
		var r := 3 if s.kind == "town" else 2
		img.fill_rect(Rect2i(px - r, py - r, r * 2 + 1, r * 2 + 1), Color.BLACK)
		img.fill_rect(Rect2i(px - r + 1, py - r + 1, r * 2 - 1, r * 2 - 1), c)

## Log-scaled heat over a land/sea background; settlements as dots in their final owners' colours.
func _heat_png(report: Dictionary, key: String, hot: Color) -> Image:
	var heat: Dictionary = report.heat
	var cols: int = heat.cols
	var rows: int = heat.rows
	var img := _base(report, cols, rows)
	var top := 0
	for v in heat[key]:
		top = maxi(top, int(v))
	if top > 0:
		for i in cols * rows:
			var v := int(heat[key][i])
			if v <= 0:
				continue
			var k := clampf(log(1.0 + v) / log(1.0 + top), 0.0, 1.0)
			var base: Color = LAND if int(heat.land[i]) == 1 else SEA
			var c := base.lerp(Color(1.0, 0.85, 0.2).lerp(hot, k), 0.25 + 0.75 * k)
			img.fill_rect(Rect2i((i % cols) * SCALE, (i / cols) * SCALE, SCALE, SCALE), c)
	_dots(img, report, float(heat.cell))
	return img

## Dominant faction of every threat cell, brightness by its strength.
func _threat_png(report: Dictionary) -> Image:
	var heat: Dictionary = report.heat
	var t: Dictionary = report.threat_final
	var img := _base(report, heat.cols, heat.rows)
	var top := 0.0
	for v in t.value:
		top = maxf(top, float(v))
	var cell: float = t.cell
	var scale := cell / float(heat.cell) * SCALE
	for i in int(t.cols) * int(t.rows):
		var j := int(t.dominant[i])
		if j < 0 or top <= 0.0:
			continue
		var k := clampf(log(1.0 + float(t.value[i])) / log(1.0 + top), 0.0, 1.0)
		var c := Color.html(report.colors.get(t.factions[j], "#888888"))
		var x := int((i % int(t.cols)) * scale)
		var y := int((i / int(t.cols)) * scale)
		var r := Rect2i(x, y, int(scale), int(scale)).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
		for py in range(r.position.y, r.end.y):
			for px in range(r.position.x, r.end.x):
				img.set_pixel(px, py, img.get_pixel(px, py).lerp(c, 0.2 + 0.7 * k))
	_dots(img, report, float(heat.cell))
	return img

func _f(v: Variant, digits := 2) -> String:
	return ("%." + str(digits) + "f") % float(v)

func _table(rows: Array, meta: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Симулятор кампании: %d дн., seed %s, %s%s" % [meta.days, ", ".join(meta.seeds.map(func(s): return str(s))), meta.engine, " (debug)" if meta.debug else ""])
	lines.append("")
	var cols := [["seed", "seed"], ["войн объявлено", "wars_declared"], ["миров", "wars_peace"], ["дней войны ср.", "war_days_mean"],
		["войн одновременно ср.", "wars_at_once_mean"], ["макс.", "wars_at_once_max"], ["в день 1", "wars_day1"], ["в день 50", "wars_day50"],
		["доля пар соседей в войне ср.", "neighbour_war_share"], ["первые 30 дней", "neighbour_war_share_first30"], ["день 50", "neighbour_war_share_day50"],
		["дней, когда кто-то воюет со всеми соседями", "all_neighbours_days"], ["больше всего войн у одной", "most_fronts"],
		["дней, когда у кого-то 3+ войны", "three_fronts_days"], ["последняя стартовая война кончилась, день", "initial_wars_end_day"],
		["дней мира до новой войны той же пары, ср.", "peace_days_mean"], ["усталость, макс.", "weary_max"],
		["часовой тик, мкс", "hour_tick_usec"], ["p95", "hour_tick_p95_usec"], ["дневной тик, мкс", "day_tick_usec"], ["p95", "day_tick_p95_usec"],
		["смен владельца", "owner_changes"], ["из них нежити", "owner_changes_to_undead"], ["пали", "fallen"],
		["нежить: начало", "undead_start_day"], ["конец", "undead_end_day"], ["пик войск", "undead_peak_troops"],
		["армий нежити за прогон", "undead_armies"], ["разъездов", "undead_raids"],
		["первый город или замок пал, дней от начала", "undead_first_capture_after"],
		["городов и замков взято нежитью", "undead_captures"], ["из них к дню 100", "undead_captures_by_day100"],
		["штурмов нежити", "undead_storms"], ["удачных", "undead_storms_won"], ["деревень сожгла нежить", "undead_burns"],
		["отбито у нежити живыми", "undead_retaken"], ["походов на руины", "undead_ruin_campaigns"], ["удачных", "undead_ruin_campaigns_won"],
		["армии нежити от кургана, ср.", "undead_reach_mean"], ["самая дальняя руина от кургана", "undead_front_max"],
		["доля городов и замков у нежити: пик", "undead_peak_core_share"], ["в конце", "undead_final_core_share"],
		["войск нежити в конце", "undead_final_troops"], ["армии нежити кончились, день", "undead_armies_gone_day"],
		["живых государств в конце", "factions_alive_end"],
		["нежить стоит без дела, доля", "undead_idle_share"], ["копит силы", "undead_gather_share"], ["бродит без цели", "undead_roam_share"],
		["нежить застряла ≥12 ч", "undead_stuck_12h"], ["дольше всех стояла, ч", "undead_max_stand_hours"],
		["целей волн выбрано", "undead_targets"], ["смен цели армии нежити/день", "dead_goal_changes_per_day"], ["разъезда/день", "raid_goal_changes_per_day"],
		["лордов погибло", "lords_died"], ["новых (после 1-го дня)", "lords_new"],
		["смен цели лорда/день", "lord_goal_changes_per_day"], ["p95", "lord_goal_changes_p95"], ["смен состояния/день", "lord_state_changes_per_day"],
		["туда-обратно/день", "lord_flipflops_per_day"], ["дёрганых партий", "parties_over_jitter_limit"],
		["макс. доля земель", "max_share"], ["у кого", "max_share_leader"], ["доля в конце", "final_share"],
		["осад", "sieges"], ["с выручкой", "sieges_with_relief"], ["без выручки, свой лорд рядом ≥12 ч", "sieges_no_relief_with_helper"],
		["с защитой (цель «защита»)", "sieges_defended"], ["без выручки и защиты, свой лорд рядом", "sieges_no_help_with_helper"],
		["из них: выручка занята другой осадой", "no_relief_busy"], ["из них: выручка безнадёжна", "no_relief_weak"],
		["походов", "campaigns"], ["лордов в походе ср.", "campaign_lords"], ["оставлено дома ср.", "campaign_kept"],
		["отходов: войско ослабло", "retreats_weak"], ["отходов: на выручку домой", "retreats_home"], ["выручек отправлено", "relief_sent"],
		["доля войска у маршала на марше", "march_with_marshal"],
		["поджогов деревень", "villages_burnt"], ["время лордов по целям", "lord_goals"],
		["у края без цели, партия·ч", "edge_idle_party_hours"], ["застряли ≥6 ч", "edge_stuck_6h"],
		["бегств", "flees_measured"], ["бег в большую угрозу", "flees_into_more_threat"], ["угроза в конце бегства", "flee_threat_ratio"],
		["угроза в клетке карты угроз", "threat_safe_cell_ratio"], ["перестройка карты, мкс", "threat_rebuild_usec"], ["секунд", "wall_seconds"]]
	lines.append("| Показатель | " + " | ".join(rows.map(func(r): return "seed %d" % r.seed)) + " |")
	lines.append("|---|" + "---|".repeat(rows.size()))
	for c in cols.slice(1):
		var cells: Array = []
		for r in rows:
			var v: Variant = r.get(c[1])
			if v is float:
				cells.append(_f(v))
			elif v is Array:
				cells.append(", ".join(v) if not v.is_empty() else "—")
			else:
				cells.append(str(v))
		lines.append("| %s | %s |" % [c[0], " | ".join(cells)])
	lines.append("")
	lines.append("Доли угрозы — отношение к угрозе в точке начала бегства (меньше 1 — безопаснее).")
	return "\n".join(lines)
