extends SceneTree
const Swing = preload("res://apps/godot/presentation/battle/hero_swing.gd")
const Session = preload("res://core/battle/application/session.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")

func _initialize() -> void:
	var samples: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/unit/battle/fixtures/hero_swing.json"))
	for sample in samples:
		var action: Dictionary = sample.action
		action.position = Vector2(action.position[0], action.position[1])
		var actual := Swing.pose(action)
		assert(actual.center.distance_to(Vector2(sample.circle[0], sample.circle[1])) < 0.0001)
		assert(absf(actual.radius - float(sample.circle[2])) < 0.0001)
		assert(absf(actual.start - float(sample.circle[3])) < 0.0001)
		assert(absf(actual.end - float(sample.circle[4])) < 0.0001)
		assert(absf(actual.color.a - float(sample.color[3])) < 0.0001)
		assert(sample.width == Swing.WIDTH and sample.cap == "round")
	assert(Swing.pose({}).is_empty())
	assert(Swing.pose({"dead":false, "remaining":0}).is_empty())
	assert(Swing.pose({"dead":true, "remaining":0.2}).is_empty())
	var state := State.new()
	var hero := Unit.new(0, 0, Vector2(10,20), 100, 0, 1)
	hero.hero = true
	state.add_unit(hero)
	hero.swing_timer = 0.13
	var session := Session.new(state, hero, RandomNumberGenerator.new())
	var values := session.hero_swing_state()
	values.position = Vector2(-100,-200)
	values.remaining = 100
	assert(session.hero_swing_state().position == Vector2(10,20))
	assert(session.hero_swing_state().remaining == 0.13)
	print("Hero swing tests passed")
	quit()
