extends RefCounted

const Config = preload("res://battle/config.gd")
const Combat = preload("res://battle/rules/combat.gd")

## Input keys: move (Vector2), face (float), sprint, block, attack (bool).
static func step(battle: RefCounted, hero: RefCounted, input: Dictionary, dt: float, rng: RandomNumberGenerator) -> void:
	if dt <= 0.0 or hero.dead or hero.gone:
		return
	var move: Vector2 = input.get("move", Vector2.ZERO)
	move = move.limit_length(1.0)
	hero.facing = float(input.get("face", hero.facing))
	hero.blocking = bool(input.get("block", false)) and hero.attack_windup <= 0.0
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
	var steering: float = Config.HERO_HORSE_STEERING_RATE if move.length() > 0.0 else Config.HERO_HORSE_IDLE_STEERING_RATE
	if not hero.mounted:
		steering = Config.HERO_FOOT_STEERING_RATE
	hero.velocity = hero.velocity.lerp(move * speed, minf(1.0, steering * dt))
	hero.position += hero.velocity * dt
	hero.position = hero.position.clamp(Vector2(Config.FIELD_LEFT_RIGHT_MARGIN, Config.FIELD_TOP_MARGIN), battle.arena_size - Vector2(Config.FIELD_LEFT_RIGHT_MARGIN, Config.FIELD_BOTTOM_MARGIN))
	hero.attack_cooldown -= dt
	if bool(input.get("attack", false)) and hero.attack_cooldown <= 0.0 and hero.attack_windup <= 0.0 and not hero.blocking:
		hero.attack_cooldown = hero.attack_interval
		hero.attack_windup = Config.HERO_ATTACK_WINDUP
		hero.swing_facing = hero.facing
	if hero.attack_windup > 0.0:
		hero.attack_windup -= dt
		if hero.attack_windup <= 0.0:
			_strike(battle, hero, rng)

static func _strike(battle: RefCounted, hero: RefCounted, rng: RandomNumberGenerator) -> void:
	var hits := 0
	for enemy in battle.units:
		if enemy.side == hero.side or enemy.dead or enemy.gone:
			continue
		var delta: Vector2 = enemy.position - hero.position
		if delta.length() > Config.HERO_ATTACK_DISTANCE + enemy.collision_radius + hero.melee_reach:
			continue
		if absf(wrapf(delta.angle() - hero.swing_facing, -PI, PI)) > Config.HERO_ATTACK_ARC:
			continue
		var original_damage: float = hero.damage
		if hits > 0:
			hero.damage *= Config.HERO_FOLLOWUP_DAMAGE
		Combat.strike(battle, hero, enemy, rng)
		hero.damage = original_damage
		hits += 1
		if hits >= Config.HERO_MAX_HITS:
			break
