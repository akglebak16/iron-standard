extends SceneTree
const Config = preload("res://core/battle/config.gd")
const State = preload("res://core/battle/model/state.gd")
const Unit = preload("res://core/battle/model/unit.gd")
const HeroControl = preload("res://core/battle/rules/hero_control.gd")
const Damage = preload("res://core/battle/rules/damage.gd")
const STEP := 0.01
const HERO_START := Vector2(100, 100)
const TARGET_AHEAD := Vector2(130, 100)

func _initialize() -> void:
	_check_hit_and_cooldown()
	_check_speed_direction_and_distance()
	_check_anti_cavalry()
	print("Hero charge tests passed")
	quit(0)

func _pair() -> Dictionary:
	var battle := State.new()
	var hero := Unit.new(0, 0, HERO_START, 100, 0, 1)
	hero.hero = true
	hero.mounted = true
	hero.speed = 120.0
	hero.velocity = Vector2(120, 0)
	hero.collision_radius = Config.HORSE_COLLISION_RADIUS
	hero.mass = Config.HORSE_MASS
	hero.damage = 30.0
	var enemy := Unit.new(1, 1, TARGET_AHEAD, 100, 0, 1)
	enemy.facing = PI
	battle.add_unit(hero)
	battle.add_unit(enemy)
	var rng := RandomNumberGenerator.new()
	rng.seed = 27
	return {"battle": battle, "hero": hero, "enemy": enemy, "rng": rng}

func _step(pair: Dictionary, move: Vector2 = Vector2.RIGHT) -> void:
	HeroControl.step(pair.battle, pair.hero, {"move": move, "face": PI}, STEP, pair.rng)

func _check_hit_and_cooldown() -> void:
	var pair := _pair()
	var enemy: Unit = pair.enemy
	var hero: Unit = pair.hero
	var follower := Unit.new(2, 1, TARGET_AHEAD, 100, 0, 1)
	pair.battle.add_unit(follower)
	var expected: int = Damage.after_armor(hero.damage * (Config.CHARGE_BASE_DAMAGE + hero.velocity.length() / Config.CHARGE_SPEED_DAMAGE_DIVISOR), enemy.armor)
	_step(pair)
	assert(enemy.hp == 100 - expected)
	assert(follower.hp == 100) # First eligible enemy only.
	assert(hero.charge_cooldown == Config.HERO_CHARGE_COOLDOWN)
	assert(hero.attack_cooldown == Config.CHARGE_ATTACK_COOLDOWN)
	assert(hero.velocity.x < Config.HERO_CHARGE_MIN_SPEED)
	var hp_after: float = enemy.hp
	_step(pair)
	assert(enemy.hp == hp_after)
	assert(hero.charge_cooldown < Config.HERO_CHARGE_COOLDOWN)

func _check_speed_direction_and_distance() -> void:
	var slow := _pair()
	slow.hero.velocity = Vector2(Config.HERO_CHARGE_MIN_SPEED, 0)
	_step(slow, Vector2.ZERO)
	assert(slow.enemy.hp == 100)
	var side := _pair()
	side.enemy.position = Vector2(100, 130)
	_step(side)
	assert(side.enemy.hp == 100)
	var far := _pair()
	far.enemy.position = Vector2(160, 100)
	_step(far)
	assert(far.enemy.hp == 100)
	var on_foot := _pair()
	on_foot.hero.mounted = false
	_step(on_foot)
	assert(on_foot.enemy.hp == 100)
	var on_cooldown := _pair()
	on_cooldown.hero.charge_cooldown = 1.0
	_step(on_cooldown)
	assert(on_cooldown.enemy.hp == 100)

func _check_anti_cavalry() -> void:
	var pair := _pair()
	pair.enemy.anti_cavalry = true
	_step(pair)
	assert(pair.hero.hp < 100)
	assert(pair.enemy.hp < 100)
	assert(pair.hero.charge_cooldown == Config.HERO_CHARGE_COOLDOWN)
