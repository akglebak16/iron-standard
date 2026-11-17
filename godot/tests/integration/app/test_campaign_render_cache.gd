extends SceneTree
const MapView = preload("res://apps/godot/presentation/campaign/world_map_view.gd")
const Cache = preload("res://apps/godot/presentation/campaign/static_map_cache.gd")
const WorldMap = preload("res://core/campaign/world/world_map.gd")
const Europe = preload("res://core/campaign/data/europe_data.gd")
const Content = preload("res://adapters/content/catalog_loader.gd")
const Parties = preload("res://apps/godot/presentation/campaign/world_parties_layer.gd")
const Troops = preload("res://core/troops/data/catalog.gd")

class FixtureRoster extends RefCounted:
	var catalog := Troops.new()
	var parties: Array = []

class FixturePlayer extends RefCounted:
	var rel := {"emp": -100}

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var layer := preload("res://apps/godot/presentation/campaign/settlement_layer.gd").new()
	root.add_child(layer)
	var places := ["Бельмон", "Вентум", "Кастра Нигра", "Остра"]
	var sites := []
	for i in places.size():
		sites.append({"id": i + 1, "name": places[i], "x": 200 * i + 100, "y": 160,
			"kind": ["town", "town", "castle", "village"][i], "fac": "emp"})
	layer.build(sites)
	for site in sites:
		assert(layer.landmark_at(Vector2(site.x, site.y - 12)) == site.id)
	assert(layer.landmark_at(Vector2(100, 66)) == -1, "Transparent sky beside the spires")
	layer.queue_free()
	var small := Cache.new()
	root.add_child(small)
	small.configure(Vector2i(100, 80))
	assert(small.viewport.size == Vector2i(200, 160))
	assert(small.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	assert(small.artwork.get_viewport() == small.viewport)
	assert(small.sprite.get_viewport() == root)
	assert(small.viewport.canvas_transform * Vector2(10, 20) == Vector2(20, 40))
	small.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await _compare_rendered_map()
		await _compare_party_decals()
	print("Campaign render cache tests passed")
	quit(0)

func _compare_rendered_map() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	var data := Europe.new()
	assert(Content.populate(data))
	var world_map := WorldMap.create(4242, data)
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.make_current()
	var original: Array[Image] = []
	var comparisons: Array[Dictionary] = []
	var sizes := [0.25, 0.9, 2.5]
	for cached in [false, true]:
		var map := MapView.new()
		map.cache_static_artwork = cached
		root.add_child(map)
		map.build_from(world_map)
		await map.ready_to_show
		await process_frame
		assert(map._settlement_layer.get_viewport() == root, "Mutable owners/labels remain live")
		if cached:
			assert(map._static_cache.ready_to_show)
			assert(map._static_cache.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
			assert(map._static_cache.artwork == null, "Source geometry released after bake")
		for i in sizes.size():
			camera.position = Vector2(2600, 1700) if i == 0 else Vector2(2880, 1220)
			camera.zoom = Vector2.ONE * sizes[i]
			camera.force_update_scroll()
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			if not out.is_empty():
				assert(image.save_png(out.path_join("%s-%s.png" % ["cached" if cached else "reference", str(sizes[i])])) == OK)
			if not cached:
				original.append(image)
			else:
				var a := original[i].get_data()
				var b := image.get_data()
				var error := 0.0
				for j in a.size(): error += absi(int(a[j]) - int(b[j]))
				var mean := error / a.size() / 255.0
				comparisons.append({"zoom":sizes[i],"normalized_mean_channel_error":mean})
				assert(mean < 0.025, "Cached artwork must preserve the map at wide/default/close zoom")
		map.queue_free()
		await process_frame
	print(JSON.stringify({"visual_comparison":comparisons}))
	if not out.is_empty():
		var file := FileAccess.open(out.path_join("comparison.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(comparisons, "\t"))
	camera.queue_free()
	await process_frame

func _compare_party_decals() -> void:
	var roster := FixtureRoster.new()
	assert(Content.populate(roster.catalog))
	for i in 4:
		roster.parties.append({"id": i, "hide": false, "kind": ["lord", "vassal", "bandit", "caravan"][i],
			"fac": ["emp", "player", "bandit", "emp"][i], "x": 94.0 + 48.0 * (i % 2), "y": 96.0 + 54.0 * (i / 2),
			"troops": [{"type": ["e1", "n1", "z1", "e1"][i], "n": 12}]})
	var player := FixturePlayer.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(240, 220)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var reference: PackedByteArray
	for cached in [false, true]:
		var layer := Parties.new()
		layer.cache_decals = cached
		viewport.add_child(layer)
		layer.build(roster, player)
		for i in 5:
			await process_frame
			await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image().get_data()
		if cached:
			assert(layer._decals.ready_to_draw, "The cached variant must have baked its atlas")
			var error := 0.0
			for i in pixels.size(): error += absi(int(pixels[i]) - int(reference[i]))
			var mean := error / pixels.size() / 255.0
			print("Party decal normalized pixel error: ", mean)
			assert(mean < 0.006, "Atlas must retain the party figures and marker artwork")
		else:
			reference = pixels
		layer.free()
	viewport.queue_free()
