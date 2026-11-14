extends SceneTree
const Camera = preload("res://battle/presentation/battle_camera.gd")
const Event = preload("res://battle/combat_event.gd")
const ARENA := Vector2(2600, 1700)
const VIEWPORT := Vector2i(900, 700)
const HERO := Vector2(1050, 850)

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT
	root.add_child(viewport)
	var camera := Camera.new()
	viewport.add_child(camera)
	camera.configure(ARENA, HERO)
	assert(camera.position == HERO + Camera.INITIAL_LEAD and camera.zoom == Vector2.ONE)
	_check_follow(camera)
	_check_zoom_and_bounds(camera, viewport)
	_check_shake(camera)
	viewport.free()
	print("Battle camera tests passed")
	quit(0)

func _check_follow(camera: Camera) -> void:
	assert(Camera.pointer_lead(HERO, HERO + Vector2(100, 50)).is_equal_approx(Vector2(22, 11)))
	assert(Camera.pointer_lead(HERO, HERO + ARENA) == Camera.MAX_POINTER_LEAD)
	assert(Camera.pointer_lead(HERO, HERO - ARENA) == -Camera.MAX_POINTER_LEAD)
	var pointer := Vector2(VIEWPORT) * 0.5 + Vector2(150, -150)
	var expected := HERO + Camera.pointer_lead(HERO, camera.screen_to_world(pointer))
	var before := camera.position
	camera.advance(0.5 / Camera.FOLLOW_RATE, HERO, false, pointer, [])
	assert(camera.position.is_equal_approx(before.lerp(expected, 0.5)))
	var surviving_center := Vector2(1800, 1000)
	before = camera.position
	camera.advance(0.5 / Camera.FOLLOW_RATE, surviving_center, true, pointer, [])
	assert(camera.position.is_equal_approx(before.lerp(surviving_center, 0.5)))
	before = camera.position
	camera.advance(1.0, Vector2.INF, true, pointer, [])
	assert(camera.position == before)

func _check_zoom_and_bounds(camera: Camera, viewport: SubViewport) -> void:
	assert(Camera.initial_zoom(100) == Camera.INITIAL_ZOOM_RANGE.x)
	assert(Camera.initial_zoom(2000) == Camera.INITIAL_ZOOM_RANGE.y)
	for i in 30:
		camera.change_zoom(true)
	assert(is_equal_approx(camera.zoom.x, Camera.MANUAL_ZOOM_RANGE.y))
	camera.advance(1.0, Vector2.ZERO, true, Vector2.ZERO, [])
	var half_view := Vector2(VIEWPORT) / camera.zoom * 0.5
	assert(camera.position == half_view)
	camera.advance(1.0, ARENA, true, Vector2.ZERO, [])
	assert(camera.position == ARENA - half_view)
	for i in 30:
		camera.change_zoom(false)
	assert(is_equal_approx(camera.zoom.x, Camera.MANUAL_ZOOM_RANGE.x))
	viewport.size = Vector2i(1800, 1100)
	camera.fit_viewport()
	assert(camera.position == ARENA * 0.5)

func _check_shake(camera: Camera) -> void:
	var before := camera.screen_to_world(Vector2(300, 250))
	camera.advance_shake(0.0, [{"kind": Event.Kind.HIT, "target_hero": false}])
	assert(camera.offset == Vector2.ZERO and not camera.is_shaking())
	camera.advance_shake(0.0, [{"kind": Event.Kind.HIT, "target_hero": true}])
	assert(camera.is_shaking() and camera.offset != Vector2.ZERO)
	assert((camera.offset * camera.zoom).abs() <= Vector2.ONE * Camera.HIT_SHAKE_SCREEN_PIXELS)
	assert(camera.screen_to_world(Vector2(300, 250)) == before)
	camera.advance_shake(Camera.HIT_SHAKE_SECONDS, [])
	assert(camera.offset == Vector2.ZERO and not camera.is_shaking())
