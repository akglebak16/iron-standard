extends SceneTree
## QA of the actual UnitView and DetachedParts at matching scales, in both directions.
const Figures = preload("res://tools/battle/dominion_preview.gd")
const View = preload("res://apps/godot/presentation/battle/unit_view.gd")
const Parts = preload("res://apps/godot/presentation/battle/detached_parts.gd")
const Art = preload("res://apps/godot/visuals/original_art.gd")
const Skins = preload("res://apps/godot/visuals/dominion_heraldic_art.gd")
const Fonts = preload("res://apps/godot/visuals/game_theme.gd")
const NAMES := ["Ополченец", "Щитник", "Страж доминиона", "Рогатинник", "Алебардист", "Арбалетчик", "Лесной стрелок"]
var stage: HeadStage
var frame := 0
var waiting := false
var capture := false
var out := "user://dominion-head-preview"

class CutFigure extends Node2D:
	var troop := "d1"
	var renderer := View.new()
	var parts := Parts.new(RandomNumberGenerator.new())
	var time := 0.0
	var previous := 0.0
	var cut := false
	var unit := {}
	func _ready() -> void:
		renderer.configure_identities({1: troop}, 4017, 2)
		parts.use_unit_art(renderer.art_source())
		unit = {"id": 1, "look": Art.MANIFEST.troops[troop + "|dom"].look, "faction": "dom", "hero": false, "companion": false,
			"mounted": false, "position": Vector2.ZERO, "speed": 0.0, "facing": 0.0, "fleeing": false, "visual_phase": 0.73, "side": 0}
	func sample(value: float) -> void:
		var cycle := fmod(value, 3.0)
		if cycle < previous:
			parts.clear()
			cut = false
		if cycle >= 0.6 and not cut:
			cut = true
			renderer._falls[1] = value
			renderer._fall_positions[1] = Vector2.ZERO
			renderer._fall_rotations[1] = 1.35
			parts._rng.seed = 7
			parts.emit(Parts.Part.HEAD, {"position": Vector2.ZERO, "target_visual": unit}, -PI * 0.48, Color("#71343a"))
		if cut: parts.advance(maxf(0, cycle - previous), [])
		previous = cycle
		time = value
		queue_redraw()
	func _draw() -> void:
		renderer._time = time
		parts.draw_ground(self, Rect2(-1000, -1000, 2000, 2000))
		renderer._draw_unit(self, unit, cut, cut)
		parts.draw_air(self)

class HeadStage extends Node2D:
	var figures: Array = []
	var cuts: Array = []
	var time := 0.0
	func _ready() -> void:
		for i in Skins.IDS.size():
			for row in 2:
				var figure = Figures.Figure.new()
				figure.troop = Skins.IDS[i]
				figure.attacking = false
				figure.moving = false
				figure.position = Vector2(113 + i * 225, 300 if row == 0 else 545)
				figure.scale = Vector2.ONE * 3.2
				figure.facing = 0.0 if row == 0 else PI
				figures.append(figure)
				add_child(figure)
		for i in 3:
			var figure := CutFigure.new()
			figure.troop = ["d1", "d3", "d3x"][i]
			figure.position = Vector2(280 + i * 520, 1080)
			figure.scale = Vector2.ONE * 2.7
			cuts.append(figure)
			add_child(figure)
	func sample(value: float) -> void:
		time = value
		for figure in figures:
			figure.time = time
			figure.queue_redraw()
		for figure in cuts: figure.sample(time)
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1600, 1200), Color("#172735"))
		draw_string(Fonts.BODY_BOLD, Vector2(35, 48), "Доминион · направление и отделение головы", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color("#d7b05b"))
		draw_string(Fonts.BODY_BOLD, Vector2(35, 85), "Реальные UnitView и DetachedParts · размер головы при отделении сохраняется", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#e8dfc8"))
		draw_string(Fonts.BODY_BOLD, Vector2(35, 135), "Вправо →", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#d7b05b"))
		draw_string(Fonts.BODY_BOLD, Vector2(35, 385), "Влево ←", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#d7b05b"))
		for i in Skins.IDS.size():
			var width := Fonts.BODY_BOLD.get_string_size(NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			for y in [337, 582]: draw_string(Fonts.BODY_BOLD, Vector2(113 + i * 225 - width / 2, y), NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#e8dfc8"))
		draw_line(Vector2(35, 615), Vector2(1565, 615), Color("#405460"), 1)
		draw_string(Fonts.BODY_BOLD, Vector2(35, 655), "Отделение · та же голова, шлем, вариант внешности и масштаб", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("#d7b05b"))
		for i in 3: draw_string(Fonts.BODY_BOLD, Vector2(185 + i * 520, 1146), ["Ополченец", "Страж доминиона", "Лесной стрелок"][i], HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("#e8dfc8"))
		draw_string(Fonts.BODY_BOLD, Vector2(35, 1170), "Проверка позы и эффекта. Правила боя и вероятность отсечения не менялись.", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("#b4beb7"))

func _initialize() -> void:
	root.size = Vector2i(1600, 1200)
	for arg in OS.get_cmdline_user_args():
		if arg == "--capture": capture = true
		if arg.begins_with("--out="): out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	stage = HeadStage.new()
	root.add_child(stage)

func _process(dt: float) -> bool:
	if waiting: return false
	stage.sample(float(frame) / 30.0 if capture else stage.time + dt)
	if capture:
		waiting = true
		_capture.call_deferred()
	return false

func _capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("frame_%03d.png" % frame))
	frame += 1
	waiting = false
	if frame >= 90: quit()
