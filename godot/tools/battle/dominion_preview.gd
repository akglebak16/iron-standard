extends SceneTree
## A reproducible capture of the real UnitView, not a separate concept renderer.
const View = preload("res://apps/godot/presentation/battle/unit_view.gd")
const Art = preload("res://apps/godot/visuals/original_art.gd")
const Skins = preload("res://apps/godot/visuals/dominion_heraldic_art.gd")
const Fonts = preload("res://apps/godot/visuals/game_theme.gd")
const NAMES := ["Ополченец", "Щитник", "Страж доминиона", "Рогатинник", "Алебардист", "Арбалетчик", "Лесной стрелок"]
var stage: Preview
var frame := 0
var capture := false
var out := "user://dominion-preview"
var waiting := false

class Figure extends Node2D:
	var renderer := View.new()
	var troop := "d1"
	var time := 0.0
	var moving := false
	var attacking := true
	var facing := 0.0
	func _draw() -> void:
		var look: Dictionary = Art.MANIFEST.troops[troop + "|dom"].look
		renderer.configure_identities({1: troop}, 4017, 0)
		renderer._time = time
		var cycle := fmod(time, 1.8)
		var bump := maxf(0, 1.0 - cycle * 4.2) if attacking else 0.0
		if look.weapon == "xbow" and cycle >= 0.12 and cycle < 0.24: bump = maxf(0, 0.5 - (cycle - 0.12) * 4.2)
		renderer._bumps[1] = bump
		var unit := {"id": 1, "look": look, "faction": "dom", "hero": false, "companion": false, "mounted": false,
			"position": Vector2.ZERO, "speed": 60.0 if moving else 0.0, "facing": facing, "fleeing": false, "visual_phase": 0.73, "side": 0}
		renderer._draw_unit(self, unit, false)

class Preview extends Node2D:
	var time := 0.0
	var figures: Array[Figure] = []
	func _ready() -> void:
		for i in Skins.IDS.size():
			for row in 3:
				var figure := Figure.new()
				figure.troop = Skins.IDS[i]
				figure.position = Vector2(113 + i * 225, [340, 500, 755][row])
				figure.scale = Vector2.ONE * (4.1 if row == 0 else 1.0 if row == 1 else 2.3)
				figure.attacking = row == 2
				figure.moving = row == 1
				if row == 2 and i % 2 == 1: figure.facing = PI
				figures.append(figure)
				add_child(figure)
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1600, 900), Color("#172735"))
		draw_string(Fonts.BODY_BOLD, Vector2(35, 48), "Мядельский доминион · геральдические скины", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color("#d7b05b"))
		draw_string(Fonts.BODY_BOLD, Vector2(35, 85), "Реальный UnitView игры · увеличенный вид", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#e8dfc8"))
		for i in Skins.IDS.size():
			var width := Fonts.BODY_BOLD.get_string_size(NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
			draw_string(Fonts.BODY_BOLD, Vector2(113 + i * 225 - width / 2, 382), NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("#e8dfc8"))
		draw_line(Vector2(35, 415), Vector2(1565, 415), Color("#405460"), 1)
		draw_string(Fonts.BODY_BOLD, Vector2(35, 450), "Игровой размер · движение", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#d7b05b"))
		draw_line(Vector2(35, 545), Vector2(1565, 545), Color("#405460"), 1)
		draw_string(Fonts.BODY_BOLD, Vector2(35, 585), "Атаки и стрельба · оба направления", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#d7b05b"))
		draw_string(Fonts.BODY_BOLD, Vector2(35, 840), "Баланс и оружие сохранены. Обновлены слои, портреты, состояния смерти и визуальная отдача арбалета.", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("#b4beb7"))

func _initialize() -> void:
	root.size = Vector2i(1600, 900)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.substr(6)
		if arg == "--capture": capture = true
	DirAccess.make_dir_recursive_absolute(out)
	stage = Preview.new()
	root.add_child(stage)

func _process(dt: float) -> bool:
	if waiting: return false
	stage.time = float(frame) / 30.0 if capture else stage.time + dt
	for figure in stage.figures:
		figure.time = stage.time
		figure.queue_redraw()
	stage.queue_redraw()
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
