extends RefCounted
## Port of src/03c_siegedef.js sdUpdate(): stones thrown at the densest crowd below the wall, oil poured into crowded breaches.
const Config = preload("res://battle/config.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const Defense = preload("res://battle/model/siege_defense.gd")
const Event = preload("res://battle/combat_event.gd")

static func step(battle: State, dt: float, rng: RandomNumberGenerator) -> void:
	var defense: Defense = battle.siege_defense
	if battle.wall == null or defense == null:
		return
	var wall := battle.wall
	var skill_scale := 1.0 - battle.siege_skill * Config.SIEGE_DEFENSE_SKILL_SCALE
	var defenders := 0
	var attackers: Array[Unit] = []
	for unit: Unit in battle.units:
		if not _ready(unit):
			continue
		if unit.side == 1 and unit.position.x > wall.x - Config.SIEGE_DEFENDER_LINE_OFFSET:
			defenders += 1
		elif unit.side == 0:
			attackers.append(unit)
	defense.stone_cooldown -= dt
	if defense.stones > 0 and defense.stone_cooldown <= 0.0 and defenders >= Config.SIEGE_STONE_MIN_DEFENDERS:
		_throw_stone(battle, defense, attackers, defenders, rng)
	for i in range(defense.stones_in_flight.size() - 1, -1, -1):
		var stone: Dictionary = defense.stones_in_flight[i]
		stone.time += dt
		if stone.time < stone.duration:
			continue
		defense.stones_in_flight.remove_at(i)
		_land_stone(battle, stone.impact, attackers, skill_scale, rng)
	for cauldron in defense.cauldrons:
		cauldron.cooldown -= dt
		if cauldron.charges <= 0 or cauldron.cooldown > 0.0 or defenders < Config.SIEGE_OIL_MIN_DEFENDERS:
			continue
		var gap: Vector2 = cauldron.gap
		var crowd := 0
		for unit in attackers:
			if unit.position.x > wall.x - Config.SIEGE_OIL_REACH and unit.position.x < wall.x + wall.half_width and unit.position.y > gap.x - Config.SIEGE_OIL_GAP_MARGIN and unit.position.y < gap.y + Config.SIEGE_OIL_GAP_MARGIN:
				crowd += 1
		if crowd < Config.SIEGE_OIL_MIN_CROWD:
			continue
		cauldron.charges -= 1
		cauldron.cooldown = Config.SIEGE_OIL_COOLDOWN
		var fire := {"center": Vector2(wall.x - Config.SIEGE_FIRE_OFFSET, (gap.x + gap.y) * 0.5),
			"half_size": Vector2(Config.SIEGE_FIRE_HALF_WIDTH, maxf(Config.SIEGE_FIRE_MIN_HALF_HEIGHT, (gap.y - gap.x) * 0.5 + Config.SIEGE_FIRE_HEIGHT_PADDING)),
			"time": 0.0, "duration": Config.SIEGE_FIRE_SECONDS, "damage_timer": 0.0, "pour_from": Vector2(wall.x + Config.SIEGE_CAULDRON_X_OFFSET, gap.x - Config.SIEGE_POUR_Y_OFFSET)}
		defense.fires.append(fire)
		for unit in attackers:
			if _inside(unit.position, fire):
				unit.morale -= Config.SIEGE_OIL_MORALE_LOSS
		battle.record_notice(Event.Kind.OIL_POURED, {"position": fire.center, "first": defense.announced < 2})
		defense.announced = 2
	for i in range(defense.fires.size() - 1, -1, -1):
		var fire: Dictionary = defense.fires[i]
		fire.time += dt
		fire.damage_timer -= dt
		if fire.time >= fire.duration:
			defense.fires.remove_at(i)
			continue
		if fire.damage_timer > 0.0:
			continue
		fire.damage_timer = Config.SIEGE_FIRE_DAMAGE_INTERVAL
		for unit in attackers:
			if _ready(unit) and _inside(unit.position, fire):
				battle.hurt(unit, roundf(Config.SIEGE_FIRE_DAMAGE * skill_scale), null, Config.SIEGE_FIRE_PIERCE, rng)
				unit.morale -= Config.SIEGE_FIRE_MORALE_LOSS

static func _throw_stone(battle: State, defense: Defense, attackers: Array[Unit], defenders: int, rng: RandomNumberGenerator) -> void:
	var wall := battle.wall
	var best: Unit = null
	var best_crowd := 0
	for unit in attackers:
		if unit.position.x > wall.x - Config.SIEGE_STONE_NEAR_EDGE or unit.position.x < wall.x - Config.SIEGE_STONE_RANGE:
			continue
		var crowd := 0
		for other in attackers:
			if absf(other.position.x - unit.position.x) < Config.SIEGE_STONE_CROWD_BOX and absf(other.position.y - unit.position.y) < Config.SIEGE_STONE_CROWD_BOX:
				crowd += 1
		if crowd > best_crowd:
			best_crowd = crowd
			best = unit
	if best == null or best_crowd < Config.SIEGE_STONE_MIN_CROWD:
		defense.stone_cooldown = Config.SIEGE_STONE_RETRY_SECONDS
		return
	var impact := best.position + best.velocity * Config.SIEGE_STONE_LEAD_SECONDS
	var origin := Vector2(wall.x + Config.SIEGE_STONE_ORIGIN_OFFSET, clampf(impact.y, Config.SIEGE_STONE_EDGE, battle.arena_size.y - Config.SIEGE_STONE_EDGE))
	defense.stones_in_flight.append({"origin": origin, "impact": impact, "time": 0.0, "duration": Config.SIEGE_STONE_FLIGHT_SECONDS})
	defense.stones -= 1
	defense.stone_cooldown = rng.randf_range(Config.SIEGE_STONE_COOLDOWN_MIN, Config.SIEGE_STONE_COOLDOWN_MAX) / (Config.SIEGE_STONE_RATE_BASE + Config.SIEGE_STONE_RATE_DEFENDERS * minf(1.0, defenders / Config.SIEGE_STONE_FULL_DEFENDERS))
	battle.record_notice(Event.Kind.STONE_THROWN, {"position": origin, "impact": impact, "first": defense.announced == 0})
	if defense.announced == 0:
		defense.announced = 1

static func _land_stone(battle: State, impact: Vector2, attackers: Array[Unit], skill_scale: float, rng: RandomNumberGenerator) -> void:
	battle.record_notice(Event.Kind.STONE_LANDED, {"position": impact, "radius": Config.SIEGE_STONE_RADIUS})
	for unit in attackers:
		var distance := unit.position.distance_to(impact)
		if distance < Config.SIEGE_STONE_RADIUS and _ready(unit):
			battle.hurt(unit, roundf(Config.SIEGE_STONE_DAMAGE * (1.0 - distance / Config.SIEGE_STONE_RADIUS * Config.SIEGE_STONE_EDGE_FALLOFF) * skill_scale), null, 0.0, rng)
			unit.morale -= Config.SIEGE_STONE_MORALE_LOSS

static func _inside(point: Vector2, fire: Dictionary) -> bool:
	return absf(point.x - fire.center.x) < fire.half_size.x and absf(point.y - fire.center.y) < fire.half_size.y

static func _ready(unit: Unit) -> bool:
	return not unit.dead and not unit.gone and not unit.fleeing
