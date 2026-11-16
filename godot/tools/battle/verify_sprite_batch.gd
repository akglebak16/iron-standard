extends SceneTree
## Render both adapters from the identical frozen snapshot; no wall-clock simulation/input.
const Factory = preload("res://core/battle/application/factory.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Impacts = preload("res://apps/godot/presentation/battle/impact_effects.gd")
const Figures = preload("res://apps/godot/presentation/battle/unit_view.gd")
class Minimap extends "res://apps/godot/presentation/battle/hud/navigation_hud.gd":
	func _ready() -> void: _frame_panel.free()
	func _draw() -> void: _draw_minimap(Rect2(30, 50, 400, 300))
class Canvas extends Node2D:
	var figures: RefCounted
	var impacts: RefCounted
	var frame: RefCounted
	var vegetation: Array[Dictionary] = []
	func _draw() -> void:
		impacts.draw_ground(self, Rect2(0, 0, 960, 720))
		figures.draw_compact(self, frame, Rect2(0, 0, 960, 720), {}, vegetation, 3, 0.4)
		impacts.draw_particles(self)
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var catalog := Catalog.new()
	if not Loader.populate(catalog): quit(1); return
	var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
	setup.hero_profile.clear()
	setup.companion_profiles.clear()
	setup.player_army.assign([{"type":"n1", "n":10},{"type":"n2a", "n":8},{"type":"n3c", "n":7}])
	setup.enemy_army.assign([{"type":"e1", "n":10},{"type":"e2a", "n":8},{"type":"e3c", "n":7}])
	var battle := Factory.create(setup, catalog)
	for unit in battle._state.active_units:
		unit.position = Vector2(70 + (unit.id % 10) * 85, 120 + (unit.id / 10) * 105)
		unit.velocity = Vector2(40 + unit.id % 60, 15)
		unit.facing = unit.id * 0.7
		unit.hp *= 0.4 if unit.id % 4 == 0 else 1.0
		unit.fleeing = unit.id % 9 == 0
		unit.ai_windup = 0.2 if unit.id % 5 == 0 else -1.0
		unit.leader = unit.id % 19 == 0
	var frozen: RefCounted = battle.snapshot(true).render
	var viewports: Array[SubViewport] = []
	for native in [false, true]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960, 720)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.world_2d = World2D.new()
		root.add_child(viewport)
		var canvas := Canvas.new()
		canvas.figures = Figures.new()
		canvas.impacts = Impacts.new()
		canvas.impacts.native_enabled = native
		for index in 500:
			canvas.impacts._particles.append({"position": Vector2(20 + index % 50 * 18, 40 + index / 50 * 64),
				"remaining": 0.2 + index % 5 * 0.1, "lifetime": 0.8, "radius": 1.4 + index % 7 * 0.7,
				"color": Color(0.7, 0.2 + index % 3 * 0.2, 0.1)})
		canvas.figures.native_enabled = native
		canvas.figures._visual_rng.seed = 42
		canvas.frame = frozen
		var units: Array[Dictionary] = []
		for index in frozen.size(): units.append(frozen.unit_at(index))
		canvas.figures.configure_identities(battle.unit_appearance_ids(), 71)
		canvas.figures.prepare_art(units)
		for index in 90:
			canvas.impacts._pools.append({"position": Vector2(20 + index % 15 * 60, 30 + index / 15 * 110), "radius": 3.0 + index % 20, "color": Color(0.5, 0.1, 0.1)})
		for index in 80:
			var part := {"position": Vector2(25 + index % 16 * 55, 80 + index / 16 * 130), "height": float(index % 3 * 12),
				"kind": index % 4, "angle": index * 0.3, "mirrored": index % 5 == 0, "scale": 0.43,
				"texture": canvas.figures._art.layers(units[0]).body, "anchor": Vector2(20, 20),
				"bony": index % 3 == 0, "sleeve": Color(0.1, 0.2, 0.7), "skin": Color(0.7, 0.5, 0.3), "size": 4.5, "color": Color(0.6, 0.7, 0.8)}
			if (index / 4) % 2 == 0: canvas.impacts._parts._settled.append(part)
			else: canvas.impacts._parts._active.append(part)
		var no_events: Array[Dictionary] = []
		canvas.figures.advance(2.35, no_events)
		for index in frozen.size():
			if index % 7 == 0: canvas.figures._flashes[frozen.unit_at(index).id] = 2.41
		viewport.add_child(canvas)
		var minimap := Minimap.new()
		var ground := ColorRect.new()
		ground.name = "MapGround"
		minimap.add_child(ground)
		minimap.native_enabled = native
		minimap._frame = {"render": frozen, "walls": [], "arena_size": Vector2(1000, 800)}
		minimap._map = Rect2(740, 560, 190, 125)
		viewport.add_child(minimap)
		viewports.append(viewport)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var left := viewports[0].get_texture().get_image()
	var right := viewports[1].get_texture().get_image()
	left.convert(Image.FORMAT_RGBA8)
	right.convert(Image.FORMAT_RGBA8)
	var a := left.get_data()
	var b := right.get_data()
	var painted := 0
	var differing := 0
	var maximum := 0
	for offset in range(0, a.size(), 4):
		if a[offset] != a[0] or a[offset + 1] != a[1] or a[offset + 2] != a[2]: painted += 1
		var difference := 0
		for channel in 4: difference = maxi(difference, absi(int(a[offset + channel]) - int(b[offset + channel])))
		maximum = maxi(maximum, difference)
		if difference > 3: differing += 1
	var fraction := float(differing) / (left.get_width() * left.get_height())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var prefix := arg.trim_prefix("--out=")
			left.save_png(prefix + "-reference.png")
			right.save_png(prefix + "-native.png")
	print(JSON.stringify({"painted_pixels": painted, "different_pixels_above_3": differing, "fraction": fraction, "maximum_channel_difference": maximum, "size": str(left.get_size())}))
	# Tiny floating-point/raster boundary differences are allowed; missing layers are not.
	if painted < 5000 or fraction > 0.001:
		push_error("Native sprite drawing differs from its frozen-frame reference")
		quit(1)
	else:
		print("Frozen-frame sprite parity passed")
		quit(0)
