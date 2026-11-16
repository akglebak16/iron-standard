extends CanvasLayer
## Frames-per-second counter in the top right corner, switched in the pause menu ("Счётчик FPS").
## One instance lives under the GameTheme autoload, so it stays across menu, map and battle.
const REFRESH_SECONDS := 0.25

static var instance: CanvasLayer

var _label := Label.new()
var _left := 0.0

static func set_enabled(on: bool) -> void:
	if instance != null and is_instance_valid(instance):
		instance.visible = on

func _init() -> void:
	name = "FpsOverlay"
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -110.0
	_label.offset_right = -8.0
	_label.offset_top = 6.0
	_label.offset_bottom = 30.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("#f1e3b0"))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _process(delta: float) -> void:
	if not visible:
		return
	_left -= delta
	if _left <= 0.0:
		_left = REFRESH_SECONDS
		_label.text = "FPS %d" % roundi(Engine.get_frames_per_second())

func text() -> String:
	return _label.text
