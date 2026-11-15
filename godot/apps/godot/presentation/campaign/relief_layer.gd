extends Node2D
## Relief icons (trees, hills, mountains, bushes) and faint water glints on top of the ground texture.
## Placement follows paintTerrain() in src/05b_worldart.js with the same random sequence.
const Generator = preload("res://campaign/world/terrain_generator.gd")
const WorldNoise = preload("res://campaign/world/noise.gd")
const IconSheet = preload("res://apps/godot/presentation/campaign/icon_sheet.gd")
const Brush = preload("res://apps/godot/presentation/campaign/map_brush.gd")

var _sheet: SubViewport
var _icons: Array = []    # {key, x, y, sx, sy}
var _glints: Array = []   # {pts, color}

func build(world: Generator) -> void:
	_sheet = SubViewport.new()
	_sheet.size = IconSheet.SHEET
	_sheet.transparent_bg = true
	_sheet.disable_3d = true
	_sheet.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sheet.add_child(IconSheet.new())
	add_child(_sheet)
	_place_icons(world)
	_place_glints(world)
	queue_redraw()

func _place_icons(world: Generator) -> void:
	var rng := WorldNoise.Mulberry.new(world.seed_value + 3)
	var gc := float(Generator.GC)
	for j in Generator.GH:
		for i in Generator.GW:
			var k := j * Generator.GW + i
			var t: int = world.cells[k]
			var bio: int = world.bio[k]
			var x := i * gc
			var y := j * gc
			if t == 2:
				for q in 3:
					var px := x + rng.next() * gc
					var py := y + rng.next() * gc
					_add_tree(px, py, bio)
			elif t == 3:
				var px := x + rng.next() * gc
				var py := y + rng.next() * gc
				_icons.append({"key": "hill:%d" % bio, "x": px, "y": py, "sx": 1.0, "sy": 1.0})
			elif t == 4:
				var px := x + rng.next() * gc
				var py := y + rng.next() * gc
				var s := (0.8 + rng.next() * 0.6) * 1.5 / IconSheet.MOUNT_REF
				_icons.append({"key": "mount:0", "x": px, "y": py, "sx": s, "sy": s})
			elif t == 1 and rng.next() < 0.05:
				var px := x + rng.next() * gc
				var py := y + rng.next() * gc
				_icons.append({"key": "bush:%d" % bio, "x": px, "y": py, "sx": 1.0, "sy": 1.0})
	_icons.sort_custom(func(a, b): return a.y < b.y)

func _add_tree(x: float, y: float, bio: int) -> void:
	# Size and silhouette depend on the place only, so the world's random sequence is not touched.
	var v := sin(x * 12.9898 + y * 78.233) * 43758.5453
	var q := v - floorf(v)
	var kind := IconSheet.PINE if bio == 1 else IconSheet.TREE_STEPPE if bio == 2 else IconSheet.TREE_GRASS
	var leaf := 1 if q > 0.66 and kind != IconSheet.PINE else 0
	_icons.append({"key": "tree:%d" % (kind * 2 + leaf), "x": x, "y": y, "sx": 0.82 + q * 0.36, "sy": 0.88 + (1.0 - q) * 0.28})

func _place_glints(world: Generator) -> void:
	var y := 18
	while y < Generator.WH - 18:
		var x := 18
		while x < Generator.WW - 18:
			var wave := sin(x * 0.13 + y * 0.19)
			var xx := x + wave * 12.0
			var yy := y + cos(x * 0.07) * 6.0
			if world.cells[world.cell_of(xx - 10.0, yy)] == 0 and world.cells[world.cell_of(xx + 10.0, yy)] == 0:
				_glints.append({"pts": Brush.quad(Vector2(xx - 5, yy), Vector2(xx, yy + 1.6), Vector2(xx + 6, yy), 5), "a": 0.045 + (wave + 1.0) * 0.025})
			x += 41
		y += 26

func _draw() -> void:
	for g in _glints:
		draw_polyline(g.pts, Color(184.0 / 255.0, 217.0 / 255.0, 218.0 / 255.0, g.a), 0.8, true)
	if _sheet == null:
		return
	var tex := _sheet.get_texture()
	for ic in _icons:
		var region := IconSheet.region_of(ic.key)
		var anchor := IconSheet.anchor_of(ic.key)
		var size := Vector2(region.size) / IconSheet.SCALE * Vector2(ic.sx, ic.sy)
		var origin := Vector2(ic.x, ic.y) - anchor / IconSheet.SCALE * Vector2(ic.sx, ic.sy)
		draw_texture_rect_region(tex, Rect2(origin, size), Rect2(region))

