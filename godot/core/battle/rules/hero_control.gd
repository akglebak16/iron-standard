extends RefCounted
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")

const Config = preload("res://core/battle/config.gd")
const Combat = preload("res://core/battle/rules/combat.gd")
const Charge = preload("res://core/battle/rules/charge.gd")
const Event = preload("res://core/battle/combat_event.gd")

## Input keys: move (Vector2), face (float), sprint, block, attack (bool).
static func step(battle: State, hero: Unit, input: Dictionary, dt: float, rng: RandomNumberGenerator) -> void:
	if dt <= 0.0 or hero.dead or hero.gone:
		return
	var move: Vector2 = input.get("move", Vector2.ZERO)
	move = move.limit_length(1.0)
	hero.facing = float(input.get("face", hero.facing))
	hero.blocking = bool(input.get("block", false)) and hero.attack_windup < 0.0
	var sprinting: bool = bool(input.get("sprint", false)) and move.length() > Config.HERO_SPRINT_MIN_INPUT and hero.stamina > Config.HERO_SPRINT_MIN_STAMINA and not hero.blocking
	var speed: float = hero.speed
	if sprinting:
		speed *= Config.HERO_HORSE_SPRINT_MULTIPLIER if hero.mounted else Config.HERO_FOOT_SPRINT_MULTIPLIER
		hero.stamina = maxf(0.0, hero.stamina - Config.HERO_SPRINT_STAMINA_COST * dt)
	else:
		var recovery: float = Config.HERO_MOVE_STAMINA_RECOVERY if move.length() > Config.HERO_SPRINT_MIN_INPUT else Config.HERO_IDLE_STAMINA_RECOVERY
		hero.stamina = minf(Config.HERO_MAX_STAMINA, hero.stamina + recovery * dt)
	if hero.blocking:
		speed *= Config.HERO_BLOCK_SPEED_MULTIPLIER
	if hero.swing_timer > 0.0 and not hero.mounted:
		speed *= Config.HERO_SWING_SPEED_MULTIPLIER
	var steering: float = Config.HERO_HORSE_STEERING_RATE if move.length() > 0.0 else Config.HERO_HORSE_IDLE_STEERING_RATE
	if not hero.mounted:
		steering = Config.HERO_FOOT_STEERING_RATE
	hero.velocity = hero.velocity.lerp(move * speed, minf(1.0, steering * dt))
	hero.attack_cooldown -= dt
	hero.charge_cooldown -= dt
	if bool(input.get("attack", false)) and hero.attack_cooldown <= 0.0 and hero.attack_windup < 0.0 and not hero.blocking:
		hero.attack_cooldown = hero.attack_interval
		hero.attack_windup = Config.HERO_RANGED_WINDUP if hero.attack_range > 0.0 else Config.HERO_ATTACK_WINDUP
		hero.swing_timer = 0.0 if hero.attack_range > 0.0 else Config.HERO_SWING_SECONDS
		hero.swing_facing = hero.facing
		if hero.attack_range <= 0.0:
			battle.record_event(Event.Kind.SWING, hero, null, Event.Attack.MELEE)
	if hero.attack_windup >= 0.0:
		hero.attack_windup -= dt
		if hero.attack_windup < 0.0:
			_strike(battle, hero, rng)
	hero.swing_timer -= dt
	_charge(battle, hero, rng)
	hero.position += hero.velocity * dt

static func _charge(battle: State, hero: Unit, rng: RandomNumberGenerator) -> void:
	if not hero.mounted or hero.charge_cooldown > 0.0:
		return
	var speed := hero.velocity.length()
	if speed <= Config.HERO_CHARGE_MIN_SPEED:
		return
	var travel_direction := hero.velocity.angle()
	for enemy: Unit in battle.units:
		if enemy.side == hero.side or enemy.dead or enemy.gone:
			continue
		var delta := enemy.position - hero.position
		if delta.length() >= hero.collision_radius + enemy.collision_radius + Config.HERO_CHARGE_EXTRA_REACH:
			continue
		if absf(wrapf(delta.angle() - travel_direction, -PI, PI)) >= Config.HERO_CHARGE_DIRECTION_ARC:
			continue
		Charge.hit(battle, hero, enemy, rng)
		hero.charge_cooldown = Config.HERO_CHARGE_COOLDOWN
		break

static func _strike(battle: State, hero: Unit, rng: RandomNumberGenerator) -> void:
	if hero.attack_range > 0.0:
		_shoot(battle, hero, rng)
		return
	var weapon: Dictionary = hero.hero_weapon
	var reach: float = Config.HERO_WEAPON_BASE_REACH + float(weapon.get("reach", 0.0)) if not weapon.is_empty() else hero.melee_reach
	var attack_distance: float = Config.HERO_ATTACK_DISTANCE + reach + (Config.HERO_MOUNTED_ATTACK_REACH if hero.mounted else 0.0)
	var arc: float = float(weapon.get("arc", Config.HERO_ATTACK_ARC))
	var max_hits: int = int(weapon.get("cleave", Config.HERO_MAX_HITS))
	var hits := 0
	for enemy: Unit in battle.units:
		if enemy.side == hero.side or enemy.dead or enemy.gone:
			continue
		var delta: Vector2 = enemy.position - hero.position
		if delta.length() > attack_distance + enemy.collision_radius:
			continue
		if absf(wrapf(delta.angle() - hero.swing_facing, -PI, PI)) > arc:
			continue
		Combat.hero_strike(battle, hero, enemy, hits, rng)
		hits += 1
		if hits >= max_hits:
			break

static func _shoot(battle: State, hero: Unit, rng: RandomNumberGenerator) -> void:
	var best: Unit = null
	var best_score := INF
	for enemy: Unit in battle.units:
		if enemy.side == hero.side or enemy.dead or enemy.gone:
			continue
		var delta: Vector2 = enemy.position - hero.position
		var distance := delta.length()
		if distance > hero.attack_range or distance < Config.HERO_SHOT_MIN_DISTANCE:
			continue
		var angle_difference := absf(wrapf(delta.angle() - hero.swing_facing, -PI, PI))
		if angle_difference > Config.HERO_SHOT_CONE:
			continue
		var score := angle_difference * Config.HERO_SHOT_ANGLE_SCORE + distance * Config.HERO_SHOT_DISTANCE_SCORE
		if score < best_score:
			best = enemy
			best_score = score
	if best == null:
		battle.launch_projectile(Combat.shoot_aim(hero, hero.swing_facing, hero.attack_range * Config.HERO_SHOT_MISS_DISTANCE_FRACTION, rng))
	else:
		battle.launch_projectile(Combat.shoot(hero, best, rng))
