extends SceneTree
const Motion = preload("res://battle/presentation/unit_motion.gd")
const UnitView = preload("res://battle/presentation/unit_view.gd")
const Event = preload("res://battle/combat_event.gd")
const EPSILON := 0.0001

func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://battle/tests/fixtures/unit_motion.json"))
	for sample in fixture.poses:
		var actual := Motion.swing_pose(int(sample.kind), sample.bump)
		var expected: Array = sample.result
		assert(actual.distance_to(Vector3(expected[0], expected[1], expected[2])) < EPSILON, "original swingPose")
	for sample in fixture.bodies:
		var body := Motion.body_transform(_vec(sample.at), sample.time, sample.phase, sample.speed, sample.mounted, sample.facing, sample.bump)
		_check_transform(body, sample.calls[0].transform)
		var anchor := _vec(sample.anchor)
		assert((-anchor).distance_to(_vec(sample.calls[0].offset)) < EPSILON)
		if sample.bump > 0 and sample.kind > 0:
			var pose := Motion.swing_pose(int(sample.kind), sample.bump)
			var weapon := Motion.weapon_transform(body, anchor, _vec(sample.pivot), pose)
			_check_transform(weapon, sample.calls[1].transform)
			if sample.calls.size() == 3:
				_check_transform(weapon.rotated_local(-0.28), sample.calls[2].transform)
		else:
			_check_transform(body, sample.calls[1].transform)
	for sample in fixture.falls:
		_check_transform(Motion.fall_transform(_vec(sample.at), sample.elapsed, sample.rotation), sample.call.transform)
		assert(Motion.fall_offset(_vec(sample.anchor), sample.elapsed).distance_to(_vec(sample.call.offset)) < EPSILON)
		assert(absf(Motion.fall_alpha(sample.elapsed) - float(sample.call.alpha)) < EPSILON)
	assert(Motion.weapon_kind("throw") == 1 and Motion.weapon_kind("lance") == 2 and Motion.weapon_kind("xbow") == 3)
	_check_animation_events()
	print("Unit motion tests passed")
	quit()

func _check_animation_events() -> void:
	var view := UnitView.new()
	view.observe_units([{"id": 5, "windup": 0.2, "dead": false}])
	assert(view._bumps[5] == 1.0)
	view.advance(0.1, [])
	assert(absf(view._bumps[5] - 0.58) < EPSILON)
	view.observe_units([{"id": 5, "windup": 0.1, "dead": false}])
	assert(absf(view._bumps[5] - 0.58) < EPSILON, "decreasing windup must not restart the swing")
	view.advance(0, [{"kind": Event.Kind.HIT, "target_id": 5}])
	assert(absf(view._bumps[5] - 0.58) < EPSILON, "impact flash must not restart the attack")
	assert(view._flashes.has(5))
	view.advance(0, [{"kind": Event.Kind.SHOT, "target_id": 5}])
	assert(view._bumps[5] == 0.5)
	view.advance(0.14, [])
	assert(not view._bumps.has(5) and not view._flashes.has(5))

func _check_transform(actual: Transform2D, expected: Array) -> void:
	var values := [actual.x.x, actual.x.y, actual.y.x, actual.y.y, actual.origin.x, actual.origin.y]
	for i in values.size():
		assert(absf(float(values[i]) - float(expected[i])) < EPSILON, "original Canvas transform component %d: %s != %s" % [i, str(values[i]), str(expected[i])])

func _vec(a: Array) -> Vector2:
	return Vector2(a[0], a[1])
