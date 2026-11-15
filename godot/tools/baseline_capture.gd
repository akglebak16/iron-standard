extends SceneTree
## Reference frames and timing for a whole app scene. Informational, not a pass/fail test.
## Run with rendering (not --headless) and a fixed frame rate so the simulation repeats exactly:
##   godot --path godot --fixed-fps 60 --disable-vsync --audio-driver Dummy --resolution 1280x720 \
##     --script res://tools/baseline_capture.gd -- --scene=res://apps/godot/composition/main.tscn --out=<dir> [--reference=<dir>] [--wall-code]
## Frames are saved as <name>_<frame>.png. With --reference the frames are compared to the same files there.
const TerrainView = preload("res://apps/godot/presentation/battle/terrain/terrain_view.gd")
const DEFAULT_SCENE := "res://apps/godot/composition/main.tscn"
const DEFAULT_OUT := "user://baseline"
const CAPTURE_FRAMES: Array[int] = [2, 300, 900, 1500]
## Scripted player input: zoom the camera out, then order the whole army to charge.
const INPUT_FRAME := 5
const ZOOM_OUT_STEPS := 4
const TIMING_FROM_FRAME := 30
## A pixel differs when any channel differs by more than this (0..1).
const CHANNEL_TOLERANCE := 0.04
const MICROSECONDS_PER_MILLISECOND := 1000.0

var _scene_path := DEFAULT_SCENE
var _out := DEFAULT_OUT
var _reference := ""
var _name := ""
var _frame := 0
var _init_msec := 0
var _last_usec := 0
var _frame_usec: Array[int] = []
var _report: Array[String] = []
var _finishing := false

func _initialize() -> void:
	_init_msec = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			_scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--wall-code":
			TerrainView.use_wall_scenes = false
		elif arg.begins_with("--reference="):
			_reference = arg.trim_prefix("--reference=")
	_name = _scene_path.get_file().get_basename()
	DirAccess.make_dir_recursive_absolute(_out)
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		push_error("Cannot load scene " + _scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())

func _process(_delta: float) -> bool:
	if _finishing: return false
	_frame += 1
	var now := Time.get_ticks_usec()
	if _frame == 1:
		_report.append("%s: startup %d ms (engine start to first frame), scene ready %d ms after script init" % [_name, Time.get_ticks_msec(), Time.get_ticks_msec() - _init_msec])
	elif _frame > TIMING_FROM_FRAME:
		_frame_usec.append(now - _last_usec)
	_last_usec = now
	if _frame == INPUT_FRAME:
		_send_scripted_input()
	if _frame in CAPTURE_FRAMES:
		_capture()
	if _frame >= CAPTURE_FRAMES.back():
		_finish()
		_finishing = true
		_stop_capture.call_deferred()
	return false

func _stop_capture() -> void:
	for child in root.get_children(): child.queue_free()
	# Release playback/viewport queues while the engine is still running.
	await process_frame
	await process_frame
	# The Dummy audio driver mixes on its own wall-clock thread; --fixed-fps can
	# execute two rendered frames before that thread has consumed stop requests.
	OS.delay_msec(100)
	quit(0)

func _send_scripted_input() -> void:
	for step in ZOOM_OUT_STEPS:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = root.get_visible_rect().size * 0.5
		Input.parse_input_event(wheel)
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_R
		key.pressed = pressed
		Input.parse_input_event(key)

func _capture() -> void:
	var image := root.get_texture().get_image()
	var file := "%s_%04d.png" % [_name, _frame]
	image.save_png(_out.path_join(file))
	if _reference.is_empty():
		return
	var expected := Image.load_from_file(_reference.path_join(file))
	if expected == null or expected.get_size() != image.get_size():
		_report.append("%s: no matching reference" % file)
		return
	_report.append("%s: %.2f%% pixels differ" % [file, _different_share(expected, image) * 100.0])

static func _different_share(a: Image, b: Image) -> float:
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	var differing := 0
	var size := a.get_size()
	for y in size.y:
		for x in size.x:
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if absf(p.r - q.r) > CHANNEL_TOLERANCE or absf(p.g - q.g) > CHANNEL_TOLERANCE or absf(p.b - q.b) > CHANNEL_TOLERANCE:
				differing += 1
	return float(differing) / float(size.x * size.y)

func _finish() -> void:
	var sorted := _frame_usec.duplicate()
	sorted.sort()
	var total := 0
	for value in sorted:
		total += value
	var count := maxi(sorted.size(), 1)
	_report.append("%s: frame time over %d frames: mean %.2f ms, p95 %.2f ms, max %.2f ms" % [_name, sorted.size(), total / float(count) / MICROSECONDS_PER_MILLISECOND, sorted[int(count * 0.95)] / MICROSECONDS_PER_MILLISECOND, sorted.back() / MICROSECONDS_PER_MILLISECOND])
	var text := "\n".join(_report)
	print(text)
	var log := FileAccess.open(_out.path_join("%s_timing.txt" % _name), FileAccess.WRITE)
	if log:
		log.store_string(text + "\n")
