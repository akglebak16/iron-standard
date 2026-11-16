extends SceneTree
const Report = preload("res://apps/godot/composition/battle_result_window.gd")
const Controls = preload("res://apps/godot/presentation/battle/hud/battle_controls.gd")
const Fps = preload("res://apps/godot/composition/fps_overlay.gd")

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var result := {"dead":{"n1":4,"n2":2}, "wounded":{"n1":1}, "left":{"n1":3,"n2":2}, "enemyDead":10,"enemyTotal":15,"heroKills":8,"heroDown":true,"heroHp":0.0}
	var resolved := {"summary":{"win":false,"lost":6,"wounded":1,"lost_gold":151,"xp":83,"drops":[],"comps":{"vikenty":{"down":true,"xp":42,"kills":2,"levels_gained":1}}},
		"party":{"hero":{"lvl":3},"comps":[{"id":"vikenty","name":"Викентий","lvl":2}]}}
	var rows := Report.campaign_rows(result, resolved, null, null, null)
	var troop_rows := rows.filter(func(r): return r.size() > 3 and r[3] == "loss")
	assert(troop_rows.size() == 2 and troop_rows[0][4] == [4,1,3] and troop_rows[1][4] == [2,0,2])
	var values := {}
	for row in rows: values[row[0]] = row[1]
	assert(values["Состояние героя"] == "Ранен" and values["Бойцы в строю"] == "5")
	assert("Ранен" in values["Викентий"] and "42" in values["Викентий"] and "уровень 2" in values["Викентий"])
	assert(Report.quick_rows(result).any(func(r): return r[0] == "Раненые выжили" and r[1] == "1"))
	var report := Report.new()
	root.add_child(report)
	var controls := Controls.new()
	root.add_child(controls)
	for dims in [Vector2i(2546,1369),Vector2i(1366,768),Vector2i(960,650),Vector2i(480,800),Vector2i(640,480)]:
		root.size = dims
		report.show_report(false, Report.duration(37), rows, [], [["Продолжить","continue"]])
		for i in 12: await process_frame
		var rect: Rect2 = report._panel.get_global_rect()
		assert(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= dims.x and rect.end.y <= dims.y)
		assert(rect.size.y < 800, "short result must not fill a tall monitor")
		var button: Button = report._footer.get_child(0)
		assert(button.get_global_rect().end.y <= dims.y, "Continue stays reachable")
		for action: Button in [controls._pause, controls._speed, controls._retreat, controls._menu]:
			assert(action.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER and action.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER)
			for state in ["normal","hover","pressed","hover_pressed","disabled"]:
				var style := action.get_theme_stylebox(state)
				assert(style.content_margin_left == style.content_margin_right, "icon must not shift between button states")
		var fps_rect: Rect2 = Fps.instance._label.get_global_rect()
		assert(not fps_rect.intersects(controls._playback.get_global_rect()), "FPS must not cover playback icons")
	# Long content scrolls, while the actions stay outside the scrolling body.
	root.size = Vector2i(960,650)
	var long_rows := rows.duplicate(true)
	for i in 80: long_rows.append(["Длинная строка отчёта %d" % i, "Подробности награды и опыта"])
	report.show_report(true,"Долгая битва",long_rows,[],[["В меню","menu"],["Ещё бой","again"]])
	for i in 12: await process_frame
	assert(report._scroll.get_v_scroll_bar().visible)
	assert(report._footer.get_global_rect().end.y < 650)
	report.show_report(true,"Короткая битва",[["Погибли","0"]],[],[["Продолжить","continue"]])
	for i in 12: await process_frame
	assert(report._panel.size.y < 300, "reopening a short report must release the old height")
	var chosen := []
	report.action_chosen.connect(func(action: String): chosen.append(action))
	report._footer.get_child(0).pressed.emit()
	assert(chosen == ["continue"] and not report.visible)
	controls.free()
	report.free()
	print("Battle report layout tests passed")
	quit()
