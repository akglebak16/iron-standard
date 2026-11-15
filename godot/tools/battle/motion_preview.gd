extends SceneTree
## Capture the actual UnitView renderer at 30 fps, using the same inputs as the Canvas reference.
const UnitView = preload("res://apps/godot/presentation/battle/unit_view.gd")
const Art = preload("res://apps/godot/visuals/original_art.gd")
const FontSource = preload("res://apps/godot/visuals/game_theme.gd")
const CASES := [
	["n3", "Покой", 120, 180, 0, 0.3, "idle"],
	["n3", "Шаг", 360, 180, 60, 0.3, "idle"],
	["n3", "Рубящий удар", 600, 180, 0, 0.3, "melee"],
	["n2s", "Укол копьём", 840, 180, 0, 0.3, "melee"],
	["n2a", "Выстрел", 120, 390, 0, 0.3, "bow"],
	["n3c", "Галоп влево", 360, 390, 135, PI + 0.3, "idle"],
	["n3c", "Конный удар", 600, 390, 60, 0.3, "melee"],
	["n3", "Попадание", 840, 390, 0, 0.3, "flash"],
]
var _canvas: MotionCanvas
var _out := "user://motion"
var _frame := 0
var _waiting := false

class MotionCanvas extends Node2D:
	var time := 0.0
	var renderer := UnitView.new()
	func _ready() -> void:
		var identities := {}
		for i in CASES.size(): identities[i] = CASES[i][0]
		renderer.configure_identities(identities, 4017, 0)
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 440), Color("#181510"))
		draw_string(FontSource.BODY_BOLD, Vector2(18, 27), "Godot · тот же размер и время кадра", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#d1a84c"))
		renderer._time = time
		renderer._flashes.clear()
		for i in CASES.size():
			var c: Array = CASES[i]
			var definition: Dictionary = Art.MANIFEST.troops[c[0] + "|player"]
			var look: Dictionary = definition.look
			var bump := 0.0
			if c[6] == "melee": bump = maxf(0, 1.0 - fmod(time, 0.55) * 4.2)
			elif c[6] == "bow": bump = maxf(0, 0.5 - fmod(time, 0.55) * 4.2)
			renderer._bumps[i] = bump
			if c[6] == "flash" and fmod(time, 1.2) < 0.13: renderer._flashes[i] = time + 0.01
			var unit := {"id": i, "look": look, "faction": "player", "hero": false, "companion": false,
				"mounted": look.get("horse") != null, "position": Vector2(c[2], c[3]), "speed": c[4], "facing": c[5],
				"fleeing": false, "visual_phase": 0.73, "side": 0}
			renderer._draw_unit(self, unit, false)
			var label: String = c[1]
			var width := FontSource.BODY_BOLD.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(FontSource.BODY_BOLD, Vector2(c[2] - width / 2.0, c[3] + 29), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#eadfc2"))

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): _out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	root.size = Vector2i(960, 440)
	_canvas = MotionCanvas.new()
	root.add_child(_canvas)

func _process(_dt: float) -> bool:
	if not _waiting:
		_waiting = true
		_canvas.time = float(_frame) / 30.0
		_canvas.queue_redraw()
		_capture.call_deferred()
	return false

func _capture() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().get_region(Rect2i(0, 0, 960, 440)).save_png(_out.path_join("frame_%03d.png" % _frame))
	_frame += 1
	_waiting = false
	if _frame >= 60: quit()
