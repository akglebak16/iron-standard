extends VBoxContainer
## «Метание ножей» on screen (#215): the score line, a wooden ringed target drawn in code with a swaying aim and the
## knives that stuck, the hint and, at the end, the result with «Ещё партию» / «Хватит». The rules and the money live in
## core/campaign/rules/tavern_knives.gd; `game` is the window's state of the running game, so a redraw of the tab
## rebuilds this view from it. Per frame only the aim moves and the target redraws itself.
const Knives = preload("res://core/campaign/rules/tavern_knives.gd")
const GameSkin = preload("res://apps/godot/visuals/game_theme.gd")
const UiSounds = preload("res://apps/godot/presentation/campaign/ui_sounds.gd")

signal again_requested
signal quit_requested
signal settled(net: int)

const RADIUS := 150.0
const REGULAR_PAUSE := 0.75

var game: Dictionary
var player
var _board: Control
var _score: Label
var _hint: Label
var _end: HBoxContainer

class Board extends Control:
	var view

	func _draw() -> void:
		var c := size / 2.0
		var r: float = view.RADIUS
		draw_circle(c + Vector2(4, 6), r + 10.0, Color(0, 0, 0, 0.35))
		draw_circle(c, r + 10.0, Color("#4a3220"))
		draw_circle(c, r + 4.0, Color("#6b4a2b"))
		var paint := [Color("#d9c9a0"), Color("#8a2f25"), Color("#d9c9a0"), Color("#8a2f25"), Color("#c9a24a")]
		var rings: Array = view.Knives.RINGS
		for i in range(rings.size() - 1, -1, -1):
			draw_circle(c, float(rings[i][0]) * r, paint[rings.size() - 1 - i])
			draw_arc(c, float(rings[i][0]) * r, 0.0, TAU, 64, Color(0.1, 0.07, 0.04, 0.6), 1.5, true)
		for k in 7:
			var a := float(k) * 0.9 + 0.3
			draw_arc(c, r + 7.0, a, a + 0.5, 12, Color(0.2, 0.13, 0.08, 0.7), 1.0, true)
		for i in view.game.theirs.size():
			_knife(c + view.game.theirs[i] * r, i * 2 + 1, Color("#3b2a1c"))
		for i in view.game.mine.size():
			_knife(c + view.game.mine[i] * r, i * 2, GameSkin.BRASS)
		if view.game.phase == "aim":
			var at: Vector2 = c + view.aim_point() * r
			draw_arc(at, 11.0, 0.0, TAU, 24, Color(1, 1, 1, 0.85), 2.0, true)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_line(at + d * 5.0, at + d * 16.0, Color(1, 1, 1, 0.85), 2.0, true)

	## A knife stuck in the wood: a sliver of blade and the handle leaning out, coloured by the thrower.
	func _knife(at: Vector2, n: int, handle: Color) -> void:
		var dir := Vector2.from_angle(-0.9 - 0.35 * float(n % 3))
		var side := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([at, at + dir * 9.0 + side * 2.5, at + dir * 9.0 - side * 2.5]), Color("#c8ccd2"))
		draw_line(at + dir * 9.0 - side * 6.0, at + dir * 9.0 + side * 6.0, Color("#2a2420"), 3.0, true)
		draw_line(at + dir * 10.0, at + dir * 30.0, handle, 6.0, true)
		draw_circle(at, 2.0, Color(0, 0, 0, 0.6))

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_score = Label.new()
	_score.name = "Score"
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameSkin.title(_score, 19)
	add_child(_score)
	_board = Board.new()
	_board.name = "Target"
	_board.view = self
	_board.custom_minimum_size = Vector2(RADIUS * 2.0 + 40.0, RADIUS * 2.0 + 40.0)
	_board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.gui_input.connect(_on_board_input)
	add_child(_board)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color("#b8a880"))
	_hint.add_theme_font_size_override("font_size", 15)
	add_child(_hint)
	_end = HBoxContainer.new()
	_end.name = "End"
	_end.alignment = BoxContainer.ALIGNMENT_CENTER
	_end.add_theme_constant_override("separation", 10)
	add_child(_end)
	_refresh()

func aim_point() -> Vector2:
	return Knives.aim(float(game.t), Knives.sway(int(player.hero.get("agi", 1))))

func _process(delta: float) -> void:
	if game.is_empty() or not is_visible_in_tree():
		return
	match game.phase:
		"aim":
			game.t = float(game.t) + delta
			_board.queue_redraw()
		"their":
			game.wait = float(game.wait) - delta
			if game.wait <= 0.0:
				_regular_throws()

func _on_board_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		throw()
		accept_event()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or game.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		throw()
		get_viewport().set_input_as_handled()

## The player's throw at the current aim; then the regular's turn.
func throw() -> void:
	if game.phase != "aim":
		return
	game.mine.append(Knives.player_throw(game.rng, aim_point()))
	UiSounds.play(self, "order")
	game.phase = "their"
	game.wait = REGULAR_PAUSE
	_refresh()

func _regular_throws() -> void:
	game.theirs.append(Knives.regular_throw(game.rng, int(game.level)))
	UiSounds.play(self, "order")
	if game.theirs.size() >= Knives.THROWS:
		game.phase = "done"
		game.net = Knives.settle(player, int(game.stake), Knives.total(game.mine), Knives.total(game.theirs))
		if int(game.net) > 0:
			UiSounds.play(self, "coin")
		settled.emit(int(game.net))
	else:
		game.phase = "aim"
	_refresh()

func _line(throws: Array) -> String:
	var parts: PackedStringArray = []
	for i in Knives.THROWS:
		parts.append(str(Knives.score(throws[i])) if i < throws.size() else "—")
	return "%s = %d" % [" + ".join(parts), Knives.total(throws)]

func _refresh() -> void:
	if _score == null:
		return
	var who := String(game.regular)
	_score.text = "Ты:  %s        %s:  %s" % [_line(game.mine), who.left(1).to_upper() + who.substr(1), _line(game.theirs)]
	for c in _end.get_children():
		c.queue_free()
	match game.phase:
		"aim":
			_hint.text = "Бросок %d из %d. Ставка %d. Лови момент: ЛКМ по мишени или Пробел." % [game.mine.size() + 1, Knives.THROWS, int(game.stake)]
		"their":
			_hint.text = "Бросает %s…" % game.regular
		"done":
			var net := int(game.net)
			_hint.text = ("Ты выиграл %d золотых." % net) if net > 0 else ("Ничья: ставка вернулась." if net == 0 else "Ты проиграл %d золотых." % -net)
			_hint.add_theme_color_override("font_color", Color("#a5c77b") if net > 0 else (Color("#b8a880") if net == 0 else Color("#e0705a")))
			var more := Button.new()
			more.name = "Again"
			more.text = "Ещё партию"
			GameSkin.primary(more)
			more.disabled = String(game.get("again_why", "")) != ""
			more.tooltip_text = String(game.get("again_why", ""))
			more.pressed.connect(func(): again_requested.emit())
			_end.add_child(more)
			var stop := Button.new()
			stop.name = "Quit"
			stop.text = "Хватит"
			stop.pressed.connect(func(): quit_requested.emit())
			_end.add_child(stop)
	_board.queue_redraw()
