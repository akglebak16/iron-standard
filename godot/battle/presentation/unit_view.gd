extends RefCounted
const Art = preload("res://battle/presentation/unit_art.gd")
const Event = preload("res://battle/combat_event.gd")
const Config = preload("res://battle/config.gd")
const UnitMarkers = preload("res://battle/presentation/unit_markers.gd")
const VIEW_MARGIN := 50.0
const MOUNT_WEAPON_OFFSET := Vector2(0, -Art.MOUNT_RIDER_RISE)
const BREATH_RATE := 2.1
const BREATH_SCALE := 0.012
const PHASE_STEP := 0.618
const WALK_RATE := 8.0
const WALK_BOB := 1.4
const GALLOP_BOB := 2.6
const MOVING_SPEED := 12.0
const LEAN := 0.055
const ATTACK_SPRING_SECONDS := 0.23
const FLASH_SECONDS := 0.13
const FLASH_BRIGHTNESS := 0.45
const WINDUP_ANGLE := -0.65
const SWING_ANGLE := 0.75
const BLOCK_ANGLE := -0.85
const WEAPON_THRUST := 12.0
const FALL_SECONDS := 0.34
const FALL_TILT := 1.28
const FALL_SINK := 12.0
const CORPSE_TINT := Color(0.66, 0.61, 0.57, 0.89)
const SHADOW := Color(0.12, 0.09, 0.06, 0.29)
const FLEEING_OPACITY := 0.75
const THRUST_KINDS := {"spear": true, "halberd": true, "lance": true, "bow": true, "xbow": true, "throw": true}

var _art := Art.new()
var _markers := UnitMarkers.new()
var _time := 0.0
var _falls: Dictionary = {}
var _flashes: Dictionary = {}
var _attacks: Dictionary = {}
## Set by the view: a corpse that has finished falling is painted once into the ground bake.
var on_settled := Callable()
var _baked: Dictionary = {} # unit id -> [unit, headless]

func _init() -> void:
	if native_painter:
		UnitPainter.forget() # unit ids start over in every battle

func advance(dt: float, events: Array[Dictionary]) -> void:
	_time += dt
	for id in _flashes.keys():
		if _flashes[id] <= _time:
			_flashes.erase(id)
	for id in _attacks.keys():
		if _attacks[id] <= _time:
			_attacks.erase(id)
	for event in events:
		match event.kind:
			Event.Kind.HIT, Event.Kind.BLOCK:
				if event.kind == Event.Kind.HIT:
					_flashes[event.target_id] = _time + FLASH_SECONDS
				if event.attack == Event.Attack.MELEE and event.source_id >= 0 and not event.source_hero:
					_attacks[event.source_id] = _time + ATTACK_SPRING_SECONDS
			Event.Kind.SHOT, Event.Kind.SWING: _attacks[event.target_id] = _time + ATTACK_SPRING_SECONDS
			Event.Kind.WEAPON_SWAPPED: _attacks.erase(event.target_id)
			Event.Kind.DOWN:
				if not event.target_hero and not event.target_companion:
					_falls[event.target_id] = _time

func baked_corpses() -> Array:
	return _baked.values()

## Paints a settled corpse (used by the ground bake).
func draw_corpse(canvas: CanvasItem, unit: Dictionary, headless: bool) -> void:
	_draw_unit(canvas, unit, true, headless)

func has_falling_units() -> bool:
	for started in _falls.values():
		if _time - started < FALL_SECONDS:
			return true
	return false

func draw(canvas: CanvasItem, frame: Array[Dictionary], visible: Rect2, headless_units: Dictionary,
		vegetation: Array[Dictionary] = [], selection: int = Config.ALL_GROUPS, render := PackedFloat64Array()) -> void:
	if native_painter and render.size() == frame.size() * RENDER_STRIDE and not frame.is_empty():
		# Native: sorting the frame, ordinary fighters and plants in depth order (godot/native/src/unit_painter.cpp).
		# Corpses still falling are drawn first, heroes, companions and leaders on top.
		if not _painter_ready:
			UnitPainter.configure(_painter_config())
			_painter_ready = true
		var lists: Array = UnitPainter.prepare(render, frame, visible, _art)
		for i in lists[0]:
			var unit: Dictionary = frame[i]
			var headless: bool = headless_units.has(unit.id)
			_draw_unit(canvas, unit, true, headless)
			if on_settled.is_valid() and _time - float(_falls.get(unit.id, _time - FALL_SECONDS)) >= FALL_SECONDS:
				_baked[unit.id] = [unit, headless]
				UnitPainter.mark_baked(unit.id)
				on_settled.call(unit, headless)
		UnitPainter.draw_ordinary(canvas.get_canvas_item(), vegetation, visible, selection, _time, _flashes, _attacks)
		var special: Array[Dictionary] = []
		for i in lists[1]:
			special.append(frame[i])
		special.sort_custom(func(a: Dictionary, b: Dictionary): return a.position.y < b.position.y)
		for unit in special:
			_markers.draw_ring(canvas, unit, selection)
			_draw_unit(canvas, unit, false)
			_markers.draw_status(canvas, unit)
		return
	var living: Array[Dictionary] = []
	for unit in frame:
		if unit.gone or not visible.has_point(unit.position):
			continue
		if unit.dead:
			if not unit.hero and not unit.companion and not _baked.has(unit.id):
				var headless: bool = headless_units.has(unit.id)
				_draw_unit(canvas, unit, true, headless)
				if on_settled.is_valid() and _time - float(_falls.get(unit.id, _time - FALL_SECONDS)) >= FALL_SECONDS:
					_baked[unit.id] = [unit, headless]
					on_settled.call(unit, headless)
		else:
			living.append(unit)
	# Depth order by y with a native sort of packed keys (y in 1/16 px, then the list position).
	var keys := PackedInt64Array()
	keys.resize(living.size())
	for i in living.size():
		keys[i] = (int(floorf(living[i].position.y * 16.0)) + 1048576) * 65536 + i
	keys.sort()
	var ordered: Array[Dictionary] = []
	ordered.resize(living.size())
	for i in keys.size():
		ordered[i] = living[keys[i] % 65536]
	living = ordered
	var plant_index := 0
	for unit in living:
		while plant_index < vegetation.size() and vegetation[plant_index].position.y < unit.position.y:
			_draw_plant(canvas, vegetation[plant_index], visible)
			plant_index += 1
		_markers.draw_ring(canvas, unit, selection)
		_draw_unit(canvas, unit, false)
		_markers.draw_status(canvas, unit)
	for i in range(plant_index, vegetation.size()):
		_draw_plant(canvas, vegetation[i], visible)

## Native drawing of ordinary fighters (godot/native/src/unit_painter.cpp); the GDScript path above is the reference.
static var native_painter := true
const RENDER_STRIDE := 12 # BattleCore.render_data
static var _painter_ready := false

func _painter_config() -> Dictionary:
	var d := {}
	for map in [(get_script() as Script).get_script_constant_map(), (UnitMarkers as Script).get_script_constant_map(), (Art as Script).get_script_constant_map()]:
		for k in map:
			if not (map[k] is Script):
				d[k] = map[k]
	d["ALL_GROUPS"] = Config.ALL_GROUPS
	return d

static func _draw_plant(canvas: CanvasItem, plant: Dictionary, visible: Rect2) -> void:
	if visible.intersects(plant.bounds):
		canvas.draw_texture(plant.texture, plant.bounds.position)

func _draw_unit(canvas: CanvasItem, unit: Dictionary, fallen: bool, headless: bool = false) -> void:
	var appearance := _art.layers(unit, headless)
	var position: Vector2 = unit.position
	var direction := -1.0 if cos(unit.facing) < 0.0 else 1.0
	var phase: float = unit.id * PHASE_STEP
	var rotation := 0.0
	var scale := Vector2(direction, 1.0) * Art.SPRITE_SCALE
	var tint := Color.WHITE
	if fallen:
		var progress := clampf((_time - float(_falls.get(unit.id, _time - FALL_SECONDS))) / FALL_SECONDS, 0.0, 1.0)
		rotation = direction * FALL_TILT * progress * progress
		position.y += FALL_SINK * progress * progress
		tint = Color.WHITE.lerp(CORPSE_TINT, progress)
	else:
		canvas.draw_circle(position, unit.radius, SHADOW)
		scale.y *= 1.0 + sin(_time * BREATH_RATE + phase) * BREATH_SCALE
		if unit.speed > MOVING_SPEED:
			var bob := GALLOP_BOB if unit.mounted else WALK_BOB
			position.y -= absf(sin(_time * WALK_RATE + phase)) * bob
			rotation = direction * LEAN
		if _flashes.has(unit.id):
			tint = Color(1.0 + FLASH_BRIGHTNESS, 1.0 + FLASH_BRIGHTNESS, 1.0 + FLASH_BRIGHTNESS)
		if unit.fleeing:
			tint.a = FLEEING_OPACITY
	canvas.draw_set_transform(position, rotation, scale)
	var body: Texture2D = appearance.headless if headless else appearance.body
	if body != null:
		canvas.draw_texture(body, -Art.ANCHOR, tint)
	if appearance.weapon != null:
		var offset := MOUNT_WEAPON_OFFSET if unit.mounted else Vector2.ZERO
		var weapon_rotation := 0.0
		if not fallen:
			var motion := 0.0
			if unit.windup >= 0.0:
				motion = WINDUP_ANGLE
			elif _attacks.has(unit.id):
				motion = SWING_ANGLE * clampf((float(_attacks[unit.id]) - _time) / ATTACK_SPRING_SECONDS, 0.0, 1.0)
			if unit.blocking:
				motion = BLOCK_ANGLE
			if THRUST_KINDS.has(appearance.weapon_kind):
				offset.x += absf(motion) * WEAPON_THRUST
			else:
				weapon_rotation = motion
		var pivot := (Art.PIVOT - Art.ANCHOR + offset) * scale
		canvas.draw_set_transform(position + pivot.rotated(rotation), rotation + direction * weapon_rotation, scale)
		canvas.draw_texture(appearance.weapon, -Art.PIVOT, tint)
	canvas.draw_set_transform(Vector2.ZERO)
