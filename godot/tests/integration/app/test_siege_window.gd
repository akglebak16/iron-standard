extends SceneTree
const WorldState = preload("res://campaign/world/world_state.gd")
const EuropeData = preload("res://campaign/data/europe_data.gd")
const SiegeWindow = preload("res://apps/godot/presentation/campaign/siege_window.gd")
const TownWindow = preload("res://apps/godot/presentation/campaign/town_window.gd")

func _initialize() -> void:
	var data := EuropeData.new()
	assert(data.load_data())
	var s := WorldState.create(5, data, "emp")
	var town: Dictionary = {}
	for t in s.map.settles:
		if t.kind == "town" and t.fac == "nord":
			town = t
			break
	var w := SiegeWindow.new()
	root.add_child(w)
	await process_frame
	var seen := []
	w.assault.connect(func(t, calc): seen.append(calc))
	w.open_for(s, town)
	assert(w.visible and w.body.get_child_count() > 6, "defenders are listed")
	w.mode = "talk"
	w.render()
	assert(w.body.get_child_count() >= 3)
	w.mode = "main"
	w.render()
	for h in w.body.get_children():
		for b in h.find_children("*", "Button", true, false):
			if b.text == "Рассчитать":
				b.pressed.emit()
	print("SEEN ", seen)
	assert(seen.size() >= 1 and seen[0] == true, "calculate emits the assault")
	w.open_loot(s, town)
	assert(w.body.get_child_count() >= 3)
	# own holding gets the Владение tab
	s.siege.capture(s.player, town)
	var tw := TownWindow.new()
	root.add_child(tw)
	await process_frame
	tw.open_for(s, town)
	tw.current_tab = "hold"
	tw.render()
	assert(tw.body.get_child_count() > 3, "holding tab lists the garrison")
	print("Siege window tests passed")
	quit(0)
