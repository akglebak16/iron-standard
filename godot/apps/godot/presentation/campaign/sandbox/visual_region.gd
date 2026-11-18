extends Node2D
## Authored art-study coordinates in pixels of the region plate. No campaign state or saves.
const Art = preload("res://apps/godot/visuals/original_art.gd")
const Style = preload("res://apps/godot/visuals/game_theme.gd")
const DEFAULT_SPEED := 18.0
var route: Curve2D
var army_distance := 0.0
var caravan_distance := 0.0
var playing := true
var magnification := 1.0
var time_button := Button.new()

func _ready() -> void:
	var gates := $Landmarks
	var junction := Vector2(709, 426)
	route = _curve([gates.get_node("Belmont").position, Vector2(378,446), Vector2(422,443), Vector2(500,414),
		Vector2(605,445), junction, Vector2(784,423), Vector2(900,452), Vector2(1020,434),
		Vector2(1108,460), Vector2(1150,514), Vector2(1167,564), Vector2(1248,598),
		Vector2(1243,650), Vector2(1290,672), Vector2(1343,665), gates.get_node("Ventum").position])
	var lanes := [_curve([junction, Vector2(727,402), Vector2(752,378), Vector2(783,352),
		Vector2(780,325), gates.get_node("SaintRemy").position]),
		_curve([gates.get_node("Ventum").position, Vector2(1392,668), Vector2(1395,704),
		Vector2(1432,730), gates.get_node("Ostra").position])]
	for stroke in [[Color("#755136"),11.0,4.4],[Color("#d4a063"),9.0,3.2],[Color("#f3ce92"),5.8,1.8]]:
		for lane in lanes: _stroke(lane, stroke[2], stroke[0])
		_stroke(route, stroke[1], stroke[0])
	_stroke(route, 1.8, Color("#ca9458"))
	_tag(gates.get_node("Belmont").position + Vector2(-24,9), "Бельмон", preload("res://apps/godot/visuals/assets/crest_kin.png"))
	_tag(gates.get_node("Ventum").position + Vector2(12,10), "Вентум", preload("res://apps/godot/visuals/assets/crest_emp.png"))
	_tag(gates.get_node("SaintRemy").position + Vector2(17,-88), "Сен-Реми")
	_tag(gates.get_node("Ostra").position + Vector2(14,9), "Остра")
	_set_marker($Traffic/Army, Art.sprite("d3","dom"), 68)
	_set_marker($Traffic/Caravan, $Traffic/Caravan.texture, 51)
	army_distance = route.get_baked_length() * 0.60
	caravan_distance = route.get_baked_length() * 0.30
	_update_markers()
	time_button.text = "Пауза"
	time_button.position = Vector2(14,14)
	time_button.add_theme_font_override("font", Style.BODY_BOLD)
	time_button.add_theme_stylebox_override("normal", Style.box())
	time_button.focus_mode = Control.FOCUS_NONE
	time_button.pressed.connect(_toggle)
	$Controls.add_child(time_button)
	get_viewport().size_changed.connect(_frame)
	_frame()

func _curve(points: Array) -> Curve2D:
	var curve := Curve2D.new()
	curve.bake_interval = 2.0
	for i in points.size():
		var p: Vector2 = points[i]
		var before: Vector2 = points[maxi(i-1,0)]
		var after: Vector2 = points[mini(i+1,points.size()-1)]
		var direction := before.direction_to(after)
		curve.add_point(p, -direction * p.distance_to(before) / 3.0, direction * p.distance_to(after) / 3.0)
	return curve

func _stroke(curve: Curve2D, width: float, pigment: Color) -> void:
	var line := Line2D.new()
	line.points = curve.get_baked_points()
	line.width = width
	line.antialiased = true
	line.default_color = pigment
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	$Roads.add_child(line)

func _tag(at: Vector2, caption: String, crest: Texture2D = null) -> void:
	var city := crest != null
	var tag := Label.new()
	tag.text = caption
	tag.add_theme_font_override("font", Style.DISPLAY if city else Style.BODY_BOLD)
	tag.add_theme_font_size_override("font_size", 23 if city else 17)
	tag.add_theme_color_override("font_color", Style.PARCH)
	tag.add_theme_constant_override("outline_size", 4)
	tag.add_theme_color_override("font_outline_color", Color("#423624"))
	if city:
		var plaque := StyleBoxFlat.new()
		plaque.bg_color = Color("#283035")
		plaque.border_color = Color("#b69658")
		plaque.set_border_width_all(1)
		plaque.content_margin_left = 29
		plaque.content_margin_right = 10
		tag.add_theme_stylebox_override("normal", plaque)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Labels.add_child(tag)
	tag.position = at - Vector2(tag.get_minimum_size().x * 0.5, 0)
	if city:
		var badge := TextureRect.new()
		badge.texture = crest
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.size = Vector2(21,24)
		badge.position = Vector2(4,(tag.get_minimum_size().y-24)*0.5)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_child(badge)

func _set_marker(marker: Sprite2D, image: Texture2D, width: float) -> void:
	marker.texture = image
	marker.scale = Vector2.ONE * width / image.get_width()
	marker.centered = false
	marker.offset = -image.get_size() * Vector2(0.5,0.94)

func _process(delta: float) -> void:
	if not playing or route == null: return
	var loop := route.get_baked_length() * 2.0
	army_distance = fposmod(army_distance + DEFAULT_SPEED * delta, loop)
	caravan_distance = fposmod(caravan_distance - DEFAULT_SPEED * 0.69 * delta, loop)
	_update_markers()

func _update_markers() -> void:
	var length := route.get_baked_length()
	$Traffic/Army.position = route.sample_baked(pingpong(army_distance,length))
	$Traffic/Caravan.position = route.sample_baked(pingpong(caravan_distance,length))

func _toggle() -> void:
	playing = not playing
	time_button.text = "Пауза" if playing else "Продолжить"

func _frame() -> void:
	var size_in_world: Vector2 = $Terrain.texture.get_size()
	var viewport_size := get_viewport_rect().size
	var fit := minf(viewport_size.x/size_in_world.x, viewport_size.y/size_in_world.y)
	$Camera.zoom = Vector2.ONE * fit * magnification
	if magnification == 1.0: $Camera.position = size_in_world * 0.5
	var margin: Vector2 = (viewport_size / (2.0 * $Camera.zoom)).min(size_in_world * 0.5)
	$Camera.position = $Camera.position.clamp(margin, size_in_world - margin)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var before := get_global_mouse_position()
		magnification = clampf(magnification * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.2), 1.0, 2.4)
		_frame()
		$Camera.force_update_scroll()
		$Camera.position += before - get_global_mouse_position()
		_frame()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		$Camera.position -= event.relative / $Camera.zoom
		_frame()
