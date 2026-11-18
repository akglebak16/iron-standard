extends Camera2D
## Pan with the right/middle mouse button or WASD/arrows, zoom with the wheel or +/-.
## Fold the visual projection into zoom to keep navigation and cached ground in simulation coordinates.
const MAP_SCALE := 2.0
const REGIONAL_ZOOM := 0.84 * MAP_SCALE
const PROJECTION := Vector2(1.0, 0.83)
const MARKER_SCALE := 1.0 / MAP_SCALE
const MAX_ZOOM := 2.5 * MAP_SCALE
const PAN_SPEED := 900.0

var bounds := Rect2(0, 0, 5200, 3400)
var detached := false              ## true once the player moved the view; C returns to the party
var _dragging := false
var _press_pos := Vector2.ZERO
var _moved := false

signal map_clicked(world_pos: Vector2)
signal map_hovered(world_pos: Vector2, screen_pos: Vector2)

func _ready() -> void:
	position_smoothing_enabled = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_at(1.15, button.position)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_at(1.0 / 1.15, button.position)
		elif button.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT]:
			if button.pressed:
				_press_pos = button.position
				_moved = false
			elif button.button_index == MOUSE_BUTTON_LEFT and not _moved:
				map_clicked.emit(_screen_to_world(button.position))
			_dragging = button.pressed
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging:
			if not _moved and motion.position.distance_to(_press_pos) > 6.0:
				_moved = true
			if _moved:
				detached = true
				position -= motion.relative / zoom
				_clamp()
		map_hovered.emit(_screen_to_world(motion.position), motion.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_C:
			detached = false
			zoom = PROJECTION * REGIONAL_ZOOM
		elif key == KEY_EQUAL or key == KEY_KP_ADD:
			_zoom_at(1.25, get_viewport().get_visible_rect().size / 2.0)
		elif key == KEY_MINUS or key == KEY_KP_SUBTRACT:
			_zoom_at(0.8, get_viewport().get_visible_rect().size / 2.0)

func _process(delta: float) -> void:
	var move := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	for pair in [[KEY_A, Vector2.LEFT], [KEY_D, Vector2.RIGHT], [KEY_W, Vector2.UP], [KEY_S, Vector2.DOWN]]:
		if Input.is_key_pressed(pair[0]):
			move += pair[1]
	if move != Vector2.ZERO:
		detached = true
		position += move.normalized() * PAN_SPEED * delta / zoom
		_clamp()

func _zoom_at(factor: float, screen_point: Vector2) -> void:
	var before := _screen_to_world(screen_point)
	var view := get_viewport_rect().size
	var overview_zoom := minf(view.x / bounds.size.x, view.y / (bounds.size.y * PROJECTION.y))
	var z := clampf(zoom.x * factor, overview_zoom, MAX_ZOOM)
	zoom = PROJECTION * z
	position += before - _screen_to_world(screen_point)
	_clamp()

func _screen_to_world(p: Vector2) -> Vector2:
	return position + (p - get_viewport().get_visible_rect().size / 2.0) / zoom

func fit_all() -> void:
	var view := get_viewport().get_visible_rect().size
	var z := minf(view.x / bounds.size.x, view.y / (bounds.size.y * PROJECTION.y))
	zoom = PROJECTION * z
	position = bounds.get_center()

func _clamp() -> void:
	var margin := (get_viewport_rect().size / (2.0 * zoom)).min(bounds.size / 2.0)
	position = position.clamp(bounds.position + margin, bounds.end - margin)

func follow_party(at: Vector2) -> void:
	position = at
	_clamp()
