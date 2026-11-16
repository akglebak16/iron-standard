extends Control
## Entirely cosmetic, disposable menu scene. Local RNG never touches the battle.
const GameSkin = preload("res://apps/godot/visuals/game_theme.gd")
const Art = preload("res://apps/godot/visuals/original_art.gd")
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Companions = preload("res://core/characters/data/companion_catalog.gd")
const Gear = preload("res://core/equipment/data/gear_catalog.gd")
const HeroGear = preload("res://core/equipment/rules/hero_gear.gd")
const Profiles = preload("res://core/campaign/world/world_companions.gd")
const SONG = preload("res://apps/godot/presentation/birthday/happy_birthday.wav")
const COLORS := [Color("eab85e"), Color("e78c90"), Color("a2c9af"), Color("aaa4de"), Color("f5e7c6")]
const CONFETTI_COUNT := 110
var menu_center: CenterContainer
var preferences: RefCounted
var ordinary_music: Node
var _portrait: Texture2D
var _friends: Dictionary = {}
var _confetti: Array[Dictionary] = []
var _time := 0.0
var _poll := 0.0
var _song: AudioStreamPlayer
var _mute: Button
var _greeting: Label
var _wish: Label

func _ready() -> void:
	var catalog := Companions.new()
	var gear := Gear.new()
	if Loader.populate(catalog) and Loader.populate(gear):
		var profiles := Profiles.new(null, catalog, RandomNumberGenerator.new())
		for id in ["vikenty", "glebio", "zahariy"]:
			var look: Dictionary = HeroGear.resolve(profiles.new_profile(id), gear).look
			look.weapon = null
			look.shield = null
			var portrait: Texture2D = Art.compose(look).body
			if id == "vikenty": _portrait = portrait
			else: _friends[id] = portrait
	var rng := RandomNumberGenerator.new()
	rng.seed = 16112026
	for i in CONFETTI_COUNT:
		_confetti.append({"x":rng.randf(), "y":rng.randf(), "speed":rng.randf_range(0.045, 0.10), "phase":rng.randf_range(0, TAU), "color":COLORS[i % COLORS.size()], "length":rng.randf_range(5, 11)})
	_greeting = _label("Викентий Де Будетон,\nс днём рождения, дорогой!", GameSkin.DISPLAY, GameSkin.PARCH)
	_wish = _label("Ты нашёл своё счастье.\nПусть оно всегда будет с тобой!", GameSkin.BODY, Color("decfa9"))
	_song = AudioStreamPlayer.new()
	_song.stream = SONG
	_song.volume_db = -12
	add_child(_song)
	_song.finished.connect(_song.play)
	_mute = Button.new()
	_mute.pressed.connect(_toggle_music)
	_mute.mouse_filter = Control.MOUSE_FILTER_STOP
	_mute.add_theme_font_size_override("font_size", 15)
	add_child(_mute)
	resize_layout()
	resized.connect(resize_layout)
	_sync_music()

func _label(text: String, font: Font, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color("080b10"))
	label.add_theme_constant_override("shadow_offset_y", 3)
	add_child(label)
	return label

func resize_layout() -> void:
	if not is_instance_valid(_greeting): return
	var narrow := size.x < 900
	_greeting.position = Vector2(24, 22)
	_greeting.size = Vector2(maxf(100, size.x - 48), 120)
	_greeting.add_theme_font_size_override("font_size", 25 if narrow else 43)
	_wish.add_theme_font_size_override("font_size", 18 if narrow else 22)
	_wish.position = Vector2(20, size.y * 0.49 if narrow else size.y * 0.79)
	_wish.size = Vector2(size.x - 40 if narrow else size.x * 0.51, 65)
	if is_instance_valid(menu_center):
		menu_center.anchor_left = 0 if narrow else 0.54
		menu_center.anchor_top = 0.58 if narrow else 0.24
		menu_center.anchor_bottom = 0.94 if narrow else 0.91
		menu_center.offset_left = 0
		menu_center.offset_top = 0
		menu_center.offset_bottom = 0
	_mute.position = Vector2(size.x - 186, size.y - 46)
	_mute.size = Vector2(166, 32)
	queue_redraw()

func _process(dt: float) -> void:
	_time += minf(dt, 0.1)
	_poll += dt
	if _poll >= 0.5:
		_poll = 0
		_sync_music()
	queue_redraw()

func _sync_music() -> void:
	var audio: Dictionary = preferences.read() if preferences != null else {"effects":true, "music":true}
	var enabled: bool = audio.effects and audio.music
	if is_instance_valid(ordinary_music): ordinary_music.enabled = false
	_song.stream_paused = not enabled
	if enabled and not _song.playing: _song.play()
	_mute.text = "Музыка: " + ("вкл" if audio.music else "выкл")
	_mute.tooltip_text = "Happy Birthday to You · учитывает общий переключатель звука"

func _toggle_music() -> void:
	if preferences != null:
		var audio: Dictionary = preferences.read()
		preferences.save(audio.effects, not audio.music)
	_sync_music()

func _exit_tree() -> void:
	if is_instance_valid(_song): _song.stop()

func _draw() -> void:
	var narrow := size.x < 900
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.045, 0.06, 0.75))
	var c := Vector2(size.x * (0.5 if narrow else 0.27), size.y * (0.36 if narrow else 0.52))
	var scale := minf(size.y / 768.0, size.x / 900.0) * (0.56 if narrow else 1.0)
	# Soft concentric halo, cheap bounded draw calls, no particle nodes or texture allocations per frame.
	for i in range(16, 0, -1):
		draw_circle(c, (80 + i * 8) * scale, Color(0.96, 0.68, 0.25, 0.006))
	for i in 12:
		var a := i * TAU / 12.0 - PI / 2
		var from := c + Vector2.from_angle(a) * 160 * scale
		draw_line(from, c + Vector2.from_angle(a) * 186 * scale, Color("b18b4b"), 2, true)
	var bounce := sin(_time * 2.6) * 4 * scale
	_draw_friend("glebio", -1, c, scale, bounce)
	_draw_friend("zahariy", 1, c, scale, bounce)
	draw_set_transform(c + Vector2(0, bounce), 0, Vector2.ONE * scale)
	draw_circle(Vector2(0, 130), 74, Color(0,0,0,0.2))
	if _portrait != null:
		draw_texture_rect(_portrait, Rect2(-167, -180, 334, 387), false)
	# A joyous face over the ordinary sad expression; hood and costume remain the actual companion's.
	var face := PackedVector2Array()
	for i in 32:
		var angle := i * TAU / 32.0
		face.append(Vector2(6, -34) + Vector2(cos(angle) * 34, sin(angle) * 29))
	draw_colored_polygon(face, Color("d8a477"))
	draw_arc(Vector2(-5, -39), 5, PI, TAU, 12, Color("392b27"), 2.4, true)
	draw_arc(Vector2(17, -39), 5, PI, TAU, 12, Color("392b27"), 2.4, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-6,-26),Vector2(19,-26),Vector2(15,-17),Vector2(7,-14),Vector2(0,-17)]), Color("633530"))
	draw_line(Vector2(-3,-25), Vector2(17,-25), Color("fff0d0"), 3, true)
	draw_circle(Vector2(-13,-28), 5, Color("da8b77"))
	draw_circle(Vector2(26,-28), 5, Color("da8b77"))
	# Paper birthday hat, tassel and raised hands.
	draw_colored_polygon(PackedVector2Array([Vector2(-32,-92),Vector2(0,-175),Vector2(40,-92)]), Color("a6bca1"))
	draw_polyline(PackedVector2Array([Vector2(-32,-92),Vector2(0,-175),Vector2(40,-92),Vector2(-32,-92)]), Color("252e30"), 3, true)
	draw_line(Vector2(-22,-116), Vector2(27,-116), Color("d6b36c"), 10, true)
	draw_circle(Vector2(0,-175), 11, Color("f0d18a"))
	draw_line(Vector2(-43,50),Vector2(-92,-3),Color("514633"),24,true)
	draw_circle(Vector2(-94,-9),14,Color("deb084"))
	draw_line(Vector2(43,50),Vector2(135,70),Color("514633"),24,true)
	draw_circle(Vector2(140,65),14,Color("deb084"))
	# The long-awaited fantasy prop, not a change to inventory or healing rules.
	draw_set_transform(c + Vector2(60 * scale, bounce + 75 * scale), 0, Vector2.ONE * scale)
	draw_style_box(_bottle_style(), Rect2(75,-63,70,83))
	draw_rect(Rect2(72,-72,76,17), Color("bf9554"))
	draw_rect(Rect2(81,-40,58,34), Color("f1dfb0"))
	draw_string(GameSkin.DISPLAY, Vector2(85,-17), "Счастье", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("3e392b"))
	draw_circle(Vector2(110,-29), 4, Color("c79147"))
	for pill in [Vector2(94,6), Vector2(119,7)]:
		draw_line(pill - Vector2(6,2), pill + Vector2(6,-2), Color("eee3bb"), 7, true)
		draw_line(pill - Vector2(6,2), pill, Color("df9b9b"), 7, true)
	draw_set_transform(c + Vector2(0, bounce), 0, Vector2.ONE * scale)
	# Little kisses at both cheeks, with hearts rising gently above the three friends.
	for side in [-1, 1]:
		var kiss := Vector2(side * 40 + 6, -31)
		draw_circle(kiss + Vector2(-2,-2), 3.5, Color("d87880"))
		draw_circle(kiss + Vector2(2,2), 3.5, Color("d87880"))
		var rise := fposmod(_time * 0.3 + (0.5 if side == 1 else 0.0), 1.0)
		_heart(Vector2(side * 85, -105 - rise * 70), 9 + rise * 4, Color(0.91,0.48,0.54,1.0-rise))
	draw_string(GameSkin.DISPLAY, Vector2(-208,160), "Глебио", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("eadfc2"))
	draw_string(GameSkin.DISPLAY, Vector2(150,160), "Захарий", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("eadfc2"))
	draw_set_transform(Vector2.ZERO)
	for p in _confetti:
		var y: float = fposmod(p.y + _time * p.speed, 1.12) * (size.y + 30) - 30
		var x: float = p.x * size.x + sin(_time * 1.7 + p.phase) * 20
		var direction := Vector2.from_angle(_time * 2 + p.phase)
		draw_line(Vector2(x,y), Vector2(x,y) + direction * p.length, p.color, 3, true)

func _draw_friend(id: String, side: int, center: Vector2, scale: float, bounce: float) -> void:
	if not _friends.has(id): return
	var lean := -side * (0.18 + sin(_time * 2.6) * 0.025)
	draw_set_transform(center + Vector2(side * 80 * scale, -12 * scale + bounce), lean, Vector2.ONE * scale * 0.88)
	draw_texture_rect(_friends[id], Rect2(-167, -180, 334, 387), false)
	var face := PackedVector2Array()
	for i in 32:
		var a := i * TAU / 32.0
		face.append(Vector2(6,-33) + Vector2(cos(a) * 30, sin(a) * 25))
	draw_colored_polygon(face, Color("d6a279"))
	for eye in [-6, 17]: draw_arc(Vector2(eye,-39), 4, PI, TAU, 12, Color("392b27"), 2.5, true)
	var lips := Vector2(6 - side * 29, -24)
	draw_line(lips + Vector2(side * 6,-4), lips, Color("a9575e"), 4, true)
	draw_line(lips, lips + Vector2(side * 6,4), Color("a9575e"), 4, true)
	draw_set_transform(Vector2.ZERO)

func _heart(at: Vector2, radius: float, color: Color) -> void:
	draw_circle(at + Vector2(-radius * 0.45,0), radius * 0.6, color)
	draw_circle(at + Vector2(radius * 0.45,0), radius * 0.6, color)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-radius,0), at + Vector2(radius,0), at + Vector2(0,radius * 1.3)]), color)

var _bottle: StyleBoxFlat
func _bottle_style() -> StyleBoxFlat:
	if _bottle == null:
		_bottle = StyleBoxFlat.new()
		_bottle.bg_color = Color("668e83")
		_bottle.border_color = Color("273e3a")
		_bottle.set_border_width_all(3)
		_bottle.set_corner_radius_all(9)
	return _bottle
