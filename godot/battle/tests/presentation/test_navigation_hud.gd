extends SceneTree
const Navigation = preload("res://battle/presentation/hud/navigation_hud.gd")
const Marker = preload("res://battle/presentation/hud/order_marker.gd")
const Config = preload("res://battle/config.gd")
const Event = preload("res://battle/combat_event.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Session = preload("res://battle/application/session.gd")
const SCREEN := Vector2(960, 650)
const STEP := 1.0 / 60.0

func _initialize() -> void:
	_check_navigation_geometry()
	_check_enemy_projection()
	_check_hold_marker()
	print("Navigation HUD tests passed")
	quit(0)

func _check_navigation_geometry() -> void:
	assert(Navigation.arrow_layout(Vector2.INF, SCREEN).is_empty())
	assert(Navigation.arrow_layout(SCREEN * 0.5, SCREEN).is_empty())
	var right := Navigation.arrow_layout(Vector2(SCREEN.x + 1, SCREEN.y * 0.5), SCREEN)
	assert(right.point == Vector2(SCREEN.x - Navigation.ARROW_MARGIN.x, SCREEN.y * 0.5))
	assert(right.direction == Vector2.RIGHT)
	var up := Navigation.arrow_layout(Vector2(SCREEN.x * 0.5, -1), SCREEN)
	assert(up.point == Vector2(SCREEN.x * 0.5, Navigation.ARROW_MARGIN.y))
	assert(up.direction == Vector2.UP)
	var diagonal := Navigation.arrow_layout(Vector2(SCREEN.x * 2, SCREEN.y * 2), SCREEN)
	assert(Vector2(diagonal.point).y <= SCREEN.y - Navigation.ARROW_MARGIN.y)
	assert(Vector2(diagonal.direction).x > 0 and Vector2(diagonal.direction).y > 0)
	var map := Rect2(Vector2(700, 500), Vector2(190, 125))
	var arena := Vector2(2600, 1700)
	var camera := Rect2(arena * -0.1, arena * 0.5)
	var clipped := Navigation.map_camera_rect(camera, map, arena)
	assert(clipped.position == map.position)
	assert(clipped.size.is_equal_approx(map.size * 0.4))
	assert(not Navigation.map_camera_rect(Rect2(arena * 2.0, arena), map, arena).has_area())

func _check_enemy_projection() -> void:
	var state := State.new()
	var hero := Unit.new(0, 0, Vector2.ZERO, 100, 0, 1)
	hero.hero = true
	state.add_unit(hero)
	var first := Unit.new(1, 1, Vector2(100, 200), 100, 0, 1)
	var second := Unit.new(2, 1, Vector2(300, 400), 100, 0, 1)
	first.weight = 4
	second.weight = 2
	state.add_unit(first)
	state.add_unit(second)
	var session := Session.new(state, hero, RandomNumberGenerator.new())
	var frame := session.snapshot()
	assert(frame.enemy_center == Vector2(200, 300) and frame.enemy_strength == 6 and not frame.decided)
	first.fleeing = true
	frame = session.snapshot()
	assert(frame.enemy_center == second.position and frame.enemy_strength == 2)
	second.dead = true
	frame = session.snapshot()
	assert(frame.enemy_center == Vector2.INF and frame.enemy_strength == 0)

func _check_hold_marker() -> void:
	var marker := Marker.new()
	var state := State.new()
	state.setup_groups()
	var hero := Unit.new(0, 0, Vector2(730, 850), 100, 0, 1)
	hero.hero = true
	state.add_unit(hero)
	var ally := Unit.new(1, 0, Vector2(620, 850), 100, 0, 1)
	state.add_grouped_unit(ally, Config.GROUP_INFANTRY)
	var session := Session.new(state, hero, RandomNumberGenerator.new())
	var point := Vector2(900, 880)
	assert(session.issue_order(Config.ORDER_HOLD, point, Config.GROUP_ARCHERS))
	session.advance(STEP)
	marker.advance(STEP, session.take_events())
	assert(not marker.is_visible())
	assert(session.issue_order(Config.ORDER_HOLD, point, Config.GROUP_INFANTRY))
	session.advance(STEP)
	marker.advance(STEP, session.take_events())
	assert(marker.is_visible() and marker._point == point)
	marker.advance(Marker.LIFETIME, [{"kind": Event.Kind.ORDER_APPLIED, "order": Config.ORDER_CHARGE, "point": Vector2.ZERO}])
	assert(not marker.is_visible())
