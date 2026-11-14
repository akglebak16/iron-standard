extends Node2D

const Config = preload("res://battle/config.gd")
const Demo = preload("res://battle/presentation/demo_config.gd")
const Catalog = preload("res://battle/data/catalog.gd")
const State = preload("res://battle/model/state.gd")
const Unit = preload("res://battle/model/unit.gd")
const HeroControl = preload("res://battle/rules/hero_control.gd")

@onready var camera: Camera2D = $Camera
@onready var status: Label = $Hud/Status

var battle = State.new()
var catalog = Catalog.new()
var rng := RandomNumberGenerator.new()
var hero
var selection := Config.ALL_GROUPS
var outcome := ""

func _ready() -> void:
	rng.seed = Demo.SEED
	if not catalog.load_data():
		status.text = Demo.CATALOG_ERROR
		set_physics_process(false)
		return
	battle.setup_groups()
	battle.spawn_army(0, [{"type": Demo.PLAYER_INFANTRY_TROOP, "n": Demo.PLAYER_INFANTRY}, {"type": Demo.PLAYER_ARCHER_TROOP, "n": Demo.PLAYER_ARCHERS}], Demo.PLAYER_FACTION, catalog, rng)
	battle.spawn_army(1, [{"type": Demo.ENEMY_INFANTRY_TROOP, "n": Demo.ENEMY_INFANTRY}, {"type": Demo.ENEMY_ARCHER_TROOP, "n": Demo.ENEMY_ARCHERS}], Demo.ENEMY_FACTION, catalog, rng)
	battle.place_units()
	var troop: Dictionary = catalog.get_troop(Demo.HERO_TROOP)
	hero = Unit.new(battle.units.size(), 0, Demo.HERO_POSITION, float(troop.hp), float(troop.arm), int(troop.tier))
	hero.hero = true
	hero.troop_id = Demo.HERO_TROOP
	hero.speed = float(troop.spd)
	hero.damage = float(troop.dmg)
	hero.attack_interval = float(troop.cd)
	hero.block_chance = float(troop.block)
	battle.add_unit(hero)
	for group in battle.groups[1]:
		group.order = Config.ORDER_CHARGE
	camera.zoom = Vector2.ONE * Demo.CAMERA_ZOOM
	camera.position = hero.position
	_update_status()

func _physics_process(dt: float) -> void:
	if outcome != "":
		return
	var move := Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	var aim: float = (get_global_mouse_position() - hero.position).angle()
	HeroControl.step(battle, hero, {"move": move, "face": aim, "sprint": Input.is_key_pressed(KEY_SHIFT), "block": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT), "attack": Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)}, dt, rng)
	battle.step_movement(dt, hero.position, hero.facing)
	battle.step_combat(dt, rng)
	battle.step_morale(dt)
	if hero.dead:
		outcome = Demo.HERO_DOWN
	elif not _side_alive(1):
		outcome = Demo.VICTORY
	elif not _side_alive(0):
		outcome = Demo.DEFEAT
	camera.position = hero.position
	_update_status()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1: selection = Config.GROUP_INFANTRY
		KEY_2: selection = Config.GROUP_ARCHERS
		KEY_3: selection = Config.GROUP_CAVALRY
		KEY_4: selection = Config.ALL_GROUPS
		KEY_Q: battle.give_order(Config.ORDER_HOLD, get_global_mouse_position(), selection)
		KEY_E: battle.give_order(Config.ORDER_FOLLOW, hero.position, selection)
		KEY_R: battle.give_order(Config.ORDER_CHARGE, hero.position, selection)
		KEY_F: battle.give_order(Config.ORDER_RETREAT, hero.position, selection)
	_update_status()

func _side_alive(side: int) -> bool:
	for unit in battle.units:
		if unit.side == side and not unit.dead and not unit.gone and not unit.fleeing:
			return true
	return false

func _update_status() -> void:
	var friendly := 0
	var hostile := 0
	for unit in battle.units:
		if not unit.dead and not unit.gone:
			if unit.side == 0: friendly += 1
			else: hostile += 1
	status.text = Demo.HUD_TEXT % [outcome if outcome != "" else Demo.IN_PROGRESS, friendly, hostile, int(hero.stamina)]

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, battle.arena_size), Demo.GROUND_COLOR)
	for unit in battle.units:
		if unit.gone:
			continue
		var color: Color = Demo.DEAD_COLOR if unit.dead else (Demo.PLAYER_COLOR if unit.side == 0 else Demo.ENEMY_COLOR)
		draw_circle(unit.position, unit.collision_radius, color)
		if unit.hero and not unit.dead:
			draw_arc(unit.position, unit.collision_radius + Config.PROJECTILE_HIT_PADDING, 0.0, TAU, 20, Color.WHITE, 2.0)
	for shot in battle.projectiles:
		draw_circle(shot.impact, Config.PROJECTILE_HIT_PADDING, Color.YELLOW)
