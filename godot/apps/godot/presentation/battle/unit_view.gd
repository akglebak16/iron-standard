extends RefCounted
const Motion = preload("res://apps/godot/presentation/battle/unit_motion.gd")
const Art = preload("res://apps/godot/presentation/battle/unit_art.gd")
const Event = preload("res://core/battle/combat_event.gd")
const Config = preload("res://core/battle/config.gd")
const RenderSnapshot = preload("res://core/battle/application/render_snapshot.gd")
const UnitMarkers = preload("res://apps/godot/presentation/battle/unit_markers.gd")
const VIEW_MARGIN := 50.0
const PHASE_STEP := 0.618
const FLASH_SECONDS := 0.13
const FALL_SECONDS := Motion.FALL_SECONDS
const SHADOW = preload("res://apps/godot/visuals/assets/contact_shadow.png")
const FLEEING_OPACITY := 0.75

var _art := Art.new()
var _markers := UnitMarkers.new()
var _time := 0.0
var _falls: Dictionary = {}
var _flashes: Dictionary = {}
var _bumps: Dictionary = {}
var _windups: Dictionary = {}
var _fall_rotations: Dictionary = {}
var _fall_positions: Dictionary = {}
var _visual_rng := RandomNumberGenerator.new()
var _appearance_rng := RandomNumberGenerator.new()
var _appearance_seed := -1
var _reference_variant := -1
var _phases := {}
var _variants := {}
var _previous_positions := {}
var _directions := {}
var biome := "grass"

func configure_identities(ids: Dictionary, seed_value := 0, reference_variant := -1) -> void:
	if _appearance_seed != seed_value or _reference_variant != reference_variant:
		_appearance_seed = seed_value
		_reference_variant = reference_variant
		_appearance_rng.seed = seed_value + 9371
		_phases.clear()
		_variants.clear()
	var keys := ids.keys()
	keys.sort()
	for id in keys:
		if _variants.has(id): continue
		_variants[id] = reference_variant if reference_variant >= 0 else _appearance_rng.randi_range(0, 3)
		_phases[id] = _appearance_rng.randf_range(0.0, 6.0)
	_art.configure_identities(ids, _variants)
## Set by the view: a corpse that has finished falling is painted once into the ground bake.
var on_settled := Callable()
var _baked: Dictionary = {} # unit id -> [unit, headless]
var _corpses: Dictionary = {} # Owned death-event values, no simulation references.

func advance(dt: float, events: Array[Dictionary]) -> void:
	_time += dt
	for id in _flashes.keys():
		if _flashes[id] <= _time: _flashes.erase(id)
	for id in _bumps.keys():
		_bumps[id] = maxf(0.0, float(_bumps[id]) - dt * Motion.BUMP_DECAY)
		if _bumps[id] <= 0.0: _bumps.erase(id)
	for event in events:
		match event.kind:
			Event.Kind.HIT:
				_flashes[event.target_id] = _time + FLASH_SECONDS
			Event.Kind.SWING:
				_bumps[event.target_id] = 1.0
			Event.Kind.SHOT:
				_bumps[event.target_id] = 0.5
			Event.Kind.WEAPON_SWAPPED:
				_bumps.erase(event.target_id)
			Event.Kind.DOWN:
				if not event.target_hero and not event.target_companion:
					_falls[event.target_id] = _time
					_fall_positions[event.target_id] = event.position
					_fall_rotations[event.target_id] = _visual_rng.randf_range(1.2, 1.9) * (-1.0 if _visual_rng.randf() < 0.5 else 1.0)
					if event.has("target_visual"):
						_corpses[event.target_id] = event.target_visual.duplicate(true)

## JS starts bump at windup, not at impact. Observe detached snapshots without changing simulation.
func observe_units(units: Array[Dictionary]) -> void:
	for unit in units:
		var position: Vector2 = unit.get("position", Vector2.ZERO)
		var previous_position: Vector2 = _previous_positions.get(unit.id, position)
		if position != previous_position: _directions[unit.id] = previous_position.direction_to(position)
		_previous_positions[unit.id] = position
		var windup: float = unit.windup
		var previous: float = _windups.get(unit.id, -1.0)
		if not unit.dead and windup >= 0.0 and (previous < 0.0 or windup > previous + 0.0001):
			_bumps[unit.id] = 1.0
		_windups[unit.id] = windup

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

func draw_compact(canvas: CanvasItem, frame: RenderSnapshot, visible: Rect2, headless_units: Dictionary,
		vegetation: Array[Dictionary] = [], selection: int = Config.ALL_GROUPS, interpolation: float = 1.0, demo_mode := false) -> void:
	var figures: Array[Dictionary] = []
	var positions := frame.positions()
	var previous := frame.previous_positions()
	for i in positions.size():
		# Cull using the interpolated position before creating dictionaries or resolving art.
		if visible.has_point(previous[i].lerp(positions[i], interpolation)):
			var unit := frame.unit_at(i, interpolation)
			if not demo_mode or (not unit.hero and not unit.companion): figures.append(unit)
	for corpse: Dictionary in _corpses.values():
		if visible.has_point(corpse.position): figures.append(corpse)
	observe_units(figures)
	draw(canvas, figures, visible, headless_units, vegetation, selection, 1.0, true, demo_mode)

func draw(canvas: CanvasItem, frame: Array[Dictionary], visible: Rect2, headless_units: Dictionary,
		vegetation: Array[Dictionary] = [], selection: int = Config.ALL_GROUPS, interpolation: float = 1.0, prepared: bool = false, demo_mode := false) -> void:
	var living: Array[Dictionary] = []
	var falling: Array[Dictionary] = []
	for unit in frame:
		if unit.gone or not visible.has_point(unit.position):
			continue
		if unit.dead:
			if not unit.hero and not unit.companion and not _baked.has(unit.id):
				falling.append(unit)
		else:
			var visual: Dictionary = unit if prepared else unit.duplicate()
			if not prepared:
				visual.position = Vector2(unit.get("previous_position", unit.position)).lerp(unit.position, interpolation)
			living.append(visual)
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
		_draw_shadow(canvas, unit)
		if not demo_mode:
			_markers.draw_ring(canvas, unit, selection)
			_draw_polish(canvas, unit)
		_draw_unit(canvas, unit, false)
		if not demo_mode: _markers.draw_status(canvas, unit, _time)
	for i in range(plant_index, vegetation.size()):
		_draw_plant(canvas, vegetation[i], visible)

	# The browser draws fallDraw after living units/plants, and bakes only settled corpses.
	for unit in falling:
		var headless: bool = headless_units.has(unit.id)
		_draw_unit(canvas, unit, true, headless)
		if on_settled.is_valid() and _time - float(_falls.get(unit.id, _time - FALL_SECONDS)) >= FALL_SECONDS:
			_baked[unit.id] = [unit, headless]
			on_settled.call(unit, headless)
			_corpses.erase(unit.id)
			_falls.erase(unit.id)

func _draw_polish(canvas: CanvasItem, unit: Dictionary) -> void:
	var phase: float = _phases.get(unit.id, float(unit.id) * PHASE_STEP)
	if unit.mounted and unit.speed > 35 and unit.id % 3 == 0:
		var t := fposmod(_time * 2.3 + phase, 1.0)
		var back: Vector2 = -_directions.get(unit.id, Vector2.from_angle(unit.facing))
		var color := Color(241 / 255.0, 246 / 255.0, 247 / 255.0, 0.28) if biome == "snow" else Color(191 / 255.0, 168 / 255.0, 113 / 255.0, 0.24)
		for k in 3:
			var at: Vector2 = unit.position + back * (t * 30 + k * 5) + Vector2(k * 3, 0)
			canvas.draw_set_transform(at, 0, Vector2(3 + t * 5, 1.5 + t * 2))
			canvas.draw_circle(Vector2.ZERO, 1, color, true, -1, true)
		canvas.draw_set_transform(Vector2.ZERO)
	if _flashes.has(unit.id):
		var alpha := clampf((float(_flashes[unit.id]) - _time) / FLASH_SECONDS, 0, 1) * 0.8
		var origin: Vector2 = unit.position + Vector2(-cos(unit.facing) * 7, -22)
		for k in 3:
			var direction := Vector2.from_angle(phase + k * 2.1)
			canvas.draw_line(origin + direction * 4, origin + direction * 10, Color(1, 229 / 255.0, 160 / 255.0, alpha), 1.5, true)

static func _draw_shadow(canvas: CanvasItem, unit: Dictionary) -> void:
	var radius: float = unit.radius
	var extent := Vector2(radius * 1.65, radius * 0.72)
	canvas.draw_texture_rect(SHADOW, Rect2(Vector2(unit.position) + Vector2(4, 3) - extent, extent * 2.0), false)

static func _draw_plant(canvas: CanvasItem, plant: Dictionary, visible: Rect2) -> void:
	if visible.intersects(plant.bounds):
		canvas.draw_texture(plant.texture, plant.bounds.position)

func _draw_unit(canvas: CanvasItem, unit: Dictionary, fallen: bool, headless: bool = false) -> void:
	var appearance := _art.layers(unit, headless)
	var anchor: Vector2 = appearance.get("anchor", Art.ANCHOR)
	var pivot: Vector2 = appearance.get("pivot", Art.PIVOT)
	var sprite_scale: float = appearance.get("scale", Art.SPRITE_SCALE)
	if fallen:
		var elapsed := _time - float(_falls.get(unit.id, _time - FALL_SECONDS))
		var at: Vector2 = _fall_positions.get(unit.id, unit.position)
		var rotation: float = _fall_rotations.get(unit.id, 1.55)
		canvas.draw_set_transform_matrix(Motion.fall_transform(at, elapsed, rotation, sprite_scale))
		var corpse: Texture2D = appearance.get("corpse_headless" if headless else "corpse", appearance.body)
		canvas.draw_texture(corpse, Motion.fall_offset(anchor, elapsed), Color(1, 1, 1, Motion.fall_alpha(elapsed)))
		canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	var phase: float = unit.get("visual_phase", _phases.get(unit.id, float(unit.id) * PHASE_STEP))
	var bump: float = _bumps.get(unit.id, 0.0)
	var body := Motion.body_transform(unit.position, _time, phase, unit.speed, unit.mounted, unit.facing, bump, sprite_scale)
	var tint := Color(1, 1, 1, FLEEING_OPACITY if unit.fleeing else 1.0)
	canvas.draw_set_transform_matrix(body)
	if _flashes.has(unit.id) and appearance.has("flash"):
		canvas.draw_texture(appearance.flash, -anchor, tint)
	else:
		canvas.draw_texture(appearance.body, -anchor, tint)
		if appearance.weapon != null:
			var kind := Motion.weapon_kind(appearance.weapon_kind)
			if bump > 0.0 and kind > 0:
				var pose := Motion.swing_pose(kind, bump)
				var weapon := Motion.weapon_transform(body, anchor, pivot, pose)
				canvas.draw_set_transform_matrix(weapon)
				canvas.draw_texture(appearance.weapon, -pivot, tint)
				if kind == 1 and pose.x > 0.1:
					canvas.draw_set_transform_matrix(weapon.rotated_local(-0.28))
					canvas.draw_texture(appearance.weapon, -pivot, Color(1, 1, 1, tint.a * 0.35))
			else:
				canvas.draw_texture(appearance.weapon, -anchor, tint)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
