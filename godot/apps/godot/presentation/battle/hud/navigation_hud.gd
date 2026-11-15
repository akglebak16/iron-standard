extends Control
const GameSkin = preload("res://ui/game_theme.gd")
const RenderSnapshot = preload("res://battle/application/render_snapshot.gd")

const MAP_SIZE := Vector2(190, 125)
const SMALL_MAP_SIZE := Vector2(120, 80)
const COMPACT_WIDTH := 760.0
const MAP_MARGIN := Vector2(15, 15)
const MAP_SHADE := 0.675
const MAP_BORDER := Color("#8a7951")
const MAP_WALL := Color("#4e4235")
const MAP_CAMERA := Color(1.0, 1.0, 1.0, 0.72)
const MAP_ALLY := Color("#5fa8f5")
const MAP_ENEMY := Color("#e0432f")
const MAP_HERO_DOT := 5.0
const MAP_MOUNT_DOT := 4.0
const MAP_FOOT_DOT := 3.0
const ARROW_COLOR := Color("#e0432f")
const ARROW_TEXT := "Враг · %d"
const ARROW_TEXT_COLOR := Color("#ffb3a6")
const ARROW_OUTLINE := Color("#221208")
const ARROW_MARGIN := Vector2(70, 110)
const COMPACT_ARROW_MARGIN := Vector2(48, 58)
const ARROW_PULSE_SPEED := 5.0
const ARROW_PULSE_BASE := 0.75
const ARROW_PULSE_RANGE := 0.25
const ARROW_LABEL_UP := -26.0
const ARROW_LABEL_DOWN := 34.0
const DOWNWARD_THRESHOLD := 0.3
const ARROW_FONT_SIZE := 15
const ARROW_OUTLINE_WIDTH := 4
const ARROW_SHAPE := [Vector2(22, 0), Vector2(-10, -15), Vector2(-4, 0), Vector2(-10, 15)]

@onready var _ground: ColorRect = $MapGround
var _frame: Dictionary = {}
var _map := Rect2()
var _time := 0.0
var _arrow := PackedVector2Array(ARROW_SHAPE)
var _arrow_outline := PackedVector2Array(ARROW_SHAPE + [ARROW_SHAPE[0]])
var _map_frame := GameSkin.box("plank", 0)
var _frame_panel := Panel.new()

func _ready() -> void:
	_frame_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_panel.show_behind_parent = true
	_frame_panel.add_theme_stylebox_override("panel", _map_frame)
	add_child(_frame_panel)
	move_child(_frame_panel, 0)
	resized.connect(_layout_map)

func configure(ground: ShaderMaterial) -> void:
	_ground.material = ground.duplicate()
	_ground.material.set_shader_parameter("map_shade", MAP_SHADE)
	_layout_map()

func update_frame(frame: Dictionary, dt: float) -> void:
	_frame = frame
	_time += dt
	queue_redraw()

func _layout_map() -> void:
	if _ground.material == null:
		return
	var map_size := SMALL_MAP_SIZE if size.x < COMPACT_WIDTH else MAP_SIZE
	map_size = map_size.min((size - MAP_MARGIN * 2.0).max(Vector2.ONE))
	_map = Rect2(size - MAP_MARGIN - map_size, map_size)
	_frame_panel.position = _map.position - Vector2(7, 7)
	_frame_panel.size = _map.size + Vector2(14, 14)
	_ground.position = _map.position
	_ground.size = _map.size
	var arena_size: Vector2 = _ground.material.get_shader_parameter("arena_size")
	_ground.material.set_shader_parameter("world_scale", arena_size / _map.size)
	queue_redraw()

func _draw() -> void:
	if _frame.is_empty():
		return
	var world_to_screen := get_viewport().get_canvas_transform()
	_draw_minimap(world_to_screen.affine_inverse() * Rect2(Vector2.ZERO, size))
	if not _frame.decided and _frame.enemy_strength > 0:
		_draw_enemy_arrow(world_to_screen * Vector2(_frame.enemy_center))

func _draw_minimap(camera_rect: Rect2) -> void:
	var scale := _map.size / Vector2(_frame.arena_size)
	for wall: Rect2 in _frame.walls:
		draw_rect(Rect2(_map.position + wall.position * scale, wall.size * scale), MAP_WALL)
	if _frame.has("render"):
		var render: RenderSnapshot = _frame.render
		var positions := render.positions()
		var flags := render.flags()
		var sides := render.sides()
		for i in positions.size():
			if flags[i] & (RenderSnapshot.DEAD | RenderSnapshot.GONE): continue
			_draw_dot(positions[i], sides[i], bool(flags[i] & RenderSnapshot.HERO), bool(flags[i] & RenderSnapshot.MOUNTED), scale)
	else:
		for unit: Dictionary in _frame.units:
			if not unit.dead and not unit.gone:
				_draw_dot(unit.position, unit.side, unit.hero, unit.mounted, scale)
	var outline := map_camera_rect(camera_rect, _map, _frame.arena_size)
	if outline.has_area():
		draw_rect(outline, MAP_CAMERA, false, 1.0)
	draw_rect(_map, MAP_BORDER, false, 1.0)

func _draw_dot(position: Vector2, side: int, hero: bool, mounted: bool, scale: Vector2) -> void:
	var point := _map.position + position * scale
	if not _map.has_point(point): return
	var dot := MAP_HERO_DOT if hero else (MAP_MOUNT_DOT if mounted else MAP_FOOT_DOT)
	var color := MAP_ENEMY if side != 0 else (Color.WHITE if hero else MAP_ALLY)
	draw_rect(Rect2(point - Vector2.ONE * dot * 0.5, Vector2.ONE * dot).intersection(_map), color)

func _draw_enemy_arrow(enemy_screen: Vector2) -> void:
	var placement := arrow_layout(enemy_screen, size)
	if placement.is_empty():
		return
	var point: Vector2 = placement.point
	var direction: Vector2 = placement.direction
	var alpha := ARROW_PULSE_BASE + sin(_time * ARROW_PULSE_SPEED) * ARROW_PULSE_RANGE
	draw_set_transform(point, direction.angle())
	draw_colored_polygon(_arrow, Color(ARROW_COLOR, alpha))
	draw_polyline(_arrow_outline, Color(ARROW_OUTLINE, alpha), ARROW_OUTLINE_WIDTH, true)
	draw_set_transform(Vector2.ZERO)
	var font := GameSkin.BODY_BOLD
	var text := ARROW_TEXT % _frame.enemy_strength
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ARROW_FONT_SIZE).x
	var offset := ARROW_LABEL_UP if direction.y > DOWNWARD_THRESHOLD else ARROW_LABEL_DOWN
	var baseline := point + Vector2(-width * 0.5, offset)
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, ARROW_FONT_SIZE, ARROW_OUTLINE_WIDTH, ARROW_OUTLINE)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, ARROW_FONT_SIZE, ARROW_TEXT_COLOR)

static func map_camera_rect(camera_rect: Rect2, minimap: Rect2, arena_size: Vector2) -> Rect2:
	var scale := minimap.size / arena_size
	return Rect2(minimap.position + camera_rect.position * scale, camera_rect.size * scale).intersection(minimap)

static func arrow_layout(enemy_screen: Vector2, screen_size: Vector2) -> Dictionary:
	if not enemy_screen.is_finite() or Rect2(Vector2.ZERO, screen_size).has_point(enemy_screen):
		return {}
	var center := screen_size * 0.5
	var margin := COMPACT_ARROW_MARGIN if screen_size.x < COMPACT_WIDTH else ARROW_MARGIN
	var safe_half := (center - margin).max(Vector2.ZERO)
	if safe_half.x <= 0.0 or safe_half.y <= 0.0:
		return {}
	var direction := (enemy_screen - center).normalized()
	var distance := minf(safe_half.x / absf(direction.x) if direction.x != 0.0 else INF,
		safe_half.y / absf(direction.y) if direction.y != 0.0 else INF)
	return {"point": center + direction * distance, "direction": direction}
