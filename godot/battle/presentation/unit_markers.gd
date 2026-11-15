extends RefCounted

const Config = preload("res://battle/config.gd")
const Art = preload("res://battle/presentation/unit_art.gd")
const BannerArt = preload("res://ui/banner_art.gd")
const HERO_RING := Color("#ffd86a")
const COMPANION_RING := Color("#7fd6c8")
const ALLY_SELECTED_RING := Color(0.98, 0.87, 0.51, 0.85)
const ALLY_IDLE_RING := Color(0.43, 0.65, 0.92, 0.75)
const ENEMY_RING := Color(0.84, 0.20, 0.15, 0.75)
const RING_FLATTEN := 0.42
const RING_SEGMENTS := 20
const RING_PADDING := 3.0
const HERO_RING_PADDING := 5.0
const STANDARD_WIDTH := 1.5
const HERO_WIDTH := 2.2
const LEADER_WIDTH := 2.6
const BLOCK_RADIUS := 24.0
const BLOCK_ORIGIN := Vector2(0, -12)
const BLOCK_HALF_ANGLE := 1.1
const BLOCK_COLOR := Color(0.83, 0.90, 1.0, 0.85)
const BLOCK_WIDTH := 3.5

const HEALTH_WIDTH_PER_RADIUS := 1.9
const HEALTH_HEIGHT := 3.0
const HEALTH_FRAME := 1.0
const HEALTH_FRAME_COLOR := Color(0.06, 0.04, 0.02, 0.8)
const ALLY_HEALTH := Color("#7fb04a")
const ENEMY_HEALTH := Color("#c23a2c")
const FOOT_HEALTH_Y := 52.0
const MOUNT_HEALTH_Y := 70.0
const NAME_ABOVE_HEALTH := 6.0
const NAME_FONT_SIZE := 12
const NAME_COLOR := Color("#9fe3d6")
const NAME_SHADOW := Color(0.0, 0.0, 0.0, 0.8)
const FLEE_FLAG_OFFSET := Vector2(-1, -66)
const FLEE_FLAG_SIZE := Vector2(9, 6)
const FLEE_FLAG_POLE := Vector2(1.5, 14)
const FLEE_FLAG_COLOR := Color("#f4f0e0")
const POLE_COLOR := Color("#3a2a18")
const BANNER_POLE_LENGTH := 27.0
const BANNER_POLE_WIDTH := 2.0
const BANNER_BASE_OFFSET := Vector2(10, -2)
const BANNER_CLOTH := [Vector2(0, -26), Vector2(17, -25),
	Vector2(13, -19), Vector2(17, -13), Vector2(0, -12)]
const BANNER_MARK := [Vector2(7, -23), Vector2(10, -19), Vector2(7, -15), Vector2(4, -19)]

var _rings: Dictionary = {}
var _fills: Dictionary = {}
var _ring_textures: Dictionary = {}

## The flattened ring the polyline used to draw, rasterised once with a soft edge.
static func _ring_texture(radius: float, width: float, color: Color, dashed := false) -> ImageTexture:
	var a := radius
	var b := radius * RING_FLATTEN
	var w := ceili(2.0 * (a + width) + 4.0)
	var h := ceili(2.0 * (b + width) + 4.0)
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var center := Vector2(w, h) * 0.5
	var arc := PackedFloat32Array([0.0])
	var previous := Vector2(a, 0)
	for i in range(1, 513):
		var point := Vector2(a * cos(TAU * i / 512), b * sin(TAU * i / 512))
		arc.append(arc[-1] + point.distance_to(previous))
		previous = point
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var f := (p.x * p.x) / (a * a) + (p.y * p.y) / (b * b) - 1.0
			var grad := Vector2(2.0 * p.x / (a * a), 2.0 * p.y / (b * b)).length()
			var distance := absf(f) / maxf(grad, 0.0001)
			var alpha := clampf(width * 0.5 + 0.5 - distance, 0.0, 1.0)
			if dashed and alpha > 0:
				var angle := fposmod(atan2(p.y / b, p.x / a), TAU)
				var index := angle / TAU * 512
				var along := lerpf(arc[floori(index)], arc[mini(512, floori(index) + 1)], fposmod(index, 1.0))
				var dash := fposmod(along, 8.0)
				alpha *= clampf(minf(dash, 5.0 - dash) + 0.5, 0, 1)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha))
	return ImageTexture.create_from_image(image)
var _banner_cloth := PackedVector2Array(BANNER_CLOTH)
var _banner_mark := PackedVector2Array(BANNER_MARK)

static func ring_style(unit: Dictionary, selection: int) -> Color:
	if unit.hero:
		return HERO_RING
	if unit.companion:
		return COMPANION_RING
	if unit.side != 0:
		return ENEMY_RING
	return ALLY_SELECTED_RING if selection == Config.ALL_GROUPS or unit.group_kind == selection else ALLY_IDLE_RING

func draw_ring(canvas: CanvasItem, unit: Dictionary, selection: int) -> void:
	var radius: float = unit.radius + (HERO_RING_PADDING if unit.hero else RING_PADDING)
	if not _rings.has(radius):
		var points := PackedVector2Array()
		for i in range(RING_SEGMENTS + 1):
			points.append(Vector2.from_angle(TAU * i / RING_SEGMENTS) * Vector2(radius, radius * RING_FLATTEN))
		_rings[radius] = points
	var selected: bool = unit.side == 0 and not unit.hero and (selection == Config.ALL_GROUPS or unit.group_kind == selection)
	if selected:
		var selected_radius: float = unit.radius + 5.0
		if not _fills.has(selected_radius):
			var fill_points := PackedVector2Array()
			for i in range(40): fill_points.append(Vector2.from_angle(TAU * i / 40.0) * Vector2(selected_radius, selected_radius * RING_FLATTEN))
			_fills[selected_radius] = fill_points
		canvas.draw_set_transform(unit.position)
		canvas.draw_colored_polygon(_fills[selected_radius], Color(241 / 255.0, 210 / 255.0, 122 / 255.0, 0.15))
		canvas.draw_set_transform(Vector2.ZERO)
	var width := 2.3 if selected else (HERO_WIDTH if unit.hero or unit.companion else (LEADER_WIDTH if unit.leader else STANDARD_WIDTH))
	# One pre-rendered antialiased ring per look: a texture draw instead of a polyline with two transforms.
	var color := ring_style(unit, selection)
	var key := Vector3(radius, width, color.to_rgba32())
	var texture: Texture2D = _ring_textures.get(key)
	if texture == null:
		texture = _ring_texture(radius, width, color, unit.side != 0)
		_ring_textures[key] = texture
	canvas.draw_texture(texture, Vector2(unit.position) - texture.get_size() * 0.5)
	if unit.hero and unit.blocking:
		canvas.draw_arc(Vector2(unit.position) + BLOCK_ORIGIN, BLOCK_RADIUS, unit.facing - BLOCK_HALF_ANGLE,
			unit.facing + BLOCK_HALF_ANGLE, RING_SEGMENTS, BLOCK_COLOR, BLOCK_WIDTH, true)

static func health_bar(unit: Dictionary) -> Rect2:
	if unit.health_fraction >= 1.0:
		return Rect2()
	var width: float = unit.radius * HEALTH_WIDTH_PER_RADIUS
	var y := MOUNT_HEALTH_Y if unit.mounted else FOOT_HEALTH_Y
	return Rect2(Vector2(unit.position) - Vector2(width * 0.5, y), Vector2(width, HEALTH_HEIGHT))

func draw_status(canvas: CanvasItem, unit: Dictionary, battle_time := -1.0) -> void:
	var bar := health_bar(unit)
	if bar.has_area():
		canvas.draw_rect(bar.grow(HEALTH_FRAME), HEALTH_FRAME_COLOR)
		var fill := Rect2(bar.position, Vector2(bar.size.x * unit.health_fraction, HEALTH_HEIGHT))
		canvas.draw_rect(fill, ALLY_HEALTH if unit.side == 0 else ENEMY_HEALTH)
	if not unit.companion_name.is_empty():
		_draw_name(canvas, unit)
	if unit.leader:
		_draw_banner(canvas, unit, battle_time)
	if unit.fleeing:
		var flag := Vector2(unit.position) + FLEE_FLAG_OFFSET
		canvas.draw_rect(Rect2(Vector2(unit.position) + Vector2(-2, -67), FLEE_FLAG_POLE), POLE_COLOR)
		canvas.draw_rect(Rect2(flag, FLEE_FLAG_SIZE), FLEE_FLAG_COLOR)

static func _draw_name(canvas: CanvasItem, unit: Dictionary) -> void:
	var font := preload("res://ui/game_theme.gd").BODY_BOLD
	var text: String = unit.companion_name
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x
	var y := MOUNT_HEALTH_Y if unit.mounted else FOOT_HEALTH_Y
	var point := Vector2(unit.position) - Vector2(width * 0.5, y + NAME_ABOVE_HEALTH)
	canvas.draw_string(font, point + Vector2.ONE, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE, NAME_SHADOW)
	canvas.draw_string(font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE, NAME_COLOR)

func _draw_banner(canvas: CanvasItem, unit: Dictionary, battle_time: float) -> void:
	var direction := -1.0 if cos(unit.facing) < 0.0 else 1.0
	var point := Vector2(unit.position) + BANNER_BASE_OFFSET * Vector2(-direction, 1)
	BannerArt.draw_banner(canvas, point.x, point.y, Art.OriginalArt.palette(unit.faction), 17.0, battle_time)
