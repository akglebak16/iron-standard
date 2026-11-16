extends SceneTree
## Reproduce the report from a UI fixture over a paused real battle, without changing saves.
const Report = preload("res://apps/godot/composition/battle_result_window.gd")
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Troops = preload("res://core/troops/data/catalog.gd")
var _out := "user://battle-report.png"
var _size := Vector2i(2546,1369)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.substr(6)
		elif arg.begins_with("--size="):
			var dims := arg.substr(7).split("x")
			_size = Vector2i(int(dims[0]),int(dims[1]))
	call_deferred("_capture")

func _capture() -> void:
	root.size = _size
	var scene := preload("res://apps/godot/composition/main.tscn").instantiate()
	root.add_child(scene)
	var view = scene.get_node("Battle")
	view.set_process(false)
	view._audio.enabled = false
	view._music.enabled = false
	var catalog := Troops.new()
	if not Loader.populate(catalog):
		quit(1)
		return
	var result := {"dead":{"k1":4,"k2a":2,"k2c":2},"wounded":{"k1":1},"left":{},"enemyDead":10,"enemyTotal":15,"heroKills":8,"heroDown":true,"heroHp":0.0}
	var resolved := {"summary":{"win":false,"lost":8,"wounded":1,"lost_gold":151,"xp":83,"drops":[],"comps":{}},"party":{"hero":{"lvl":1},"comps":[]}}
	var report := Report.new()
	root.add_child(report)
	report.show_report(false, Report.duration(37), Report.campaign_rows(result,resolved,catalog,null,null), [], [["Продолжить","continue"]])
	preload("res://apps/godot/composition/fps_overlay.gd").set_enabled(true)
	for i in 15: await process_frame
	await create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out)
	report.free()
	scene.free()
	for i in 3: await process_frame
	quit()
