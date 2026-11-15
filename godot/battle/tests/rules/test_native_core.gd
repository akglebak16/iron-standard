extends SceneTree
## The native battle core must give exactly the battle the GDScript rules give: same seed, same units, bit for bit.
const Factory = preload("res://battle/application/factory.gd")
const Catalog = preload("res://troops/data/catalog.gd")
const GearCatalog = preload("res://equipment/data/gear_catalog.gd")
const PerkCatalog = preload("res://characters/data/perk_catalog.gd")
const CompanionCatalog = preload("res://characters/data/companion_catalog.gd")
const Config = preload("res://battle/config.gd")
const Movement = preload("res://battle/rules/movement.gd")

func _run(native: bool, path: String, armies: Array, ticks: int) -> Array:
	Movement.use_native = native
	var c := Catalog.new(); c.load_data()
	var g := GearCatalog.new(); g.load_data()
	var p := PerkCatalog.new(); p.load_data()
	var k := CompanionCatalog.new(); k.load_data()
	var setup = load(path).duplicate(true)
	setup.seed = 9001
	if not armies.is_empty():
		setup.player_army.assign(armies[0])
		setup.enemy_army.assign(armies[1])
	var session = Factory.create(setup, c, g, p, k)
	session.issue_order(Config.ORDER_CHARGE, Vector2.ZERO, Config.ALL_GROUPS)
	var trace: Array = []
	for i in ticks:
		session.advance(1.0 / 60.0)
		if i % 60 == 59:
			var frame: Dictionary = session.snapshot()
			frame.erase("render") # packed drawing data exists only on the native path
			trace.append(hash(var_to_str(frame)))
	if native:
		_check_render(session.snapshot())
	var out: Array = [trace, var_to_str(session.result())]
	for u in session._state.units:
		out.append([u.position, u.velocity, u.facing, u.hp, u.dead, u.gone, u.target_index, u.kills, u.ai_mode, u.attack_cooldown])
	return out

## The packed drawing data (BattleCore.render_data) must say what the frame dictionaries say.
func _check_render(frame: Dictionary) -> void:
	var render: PackedFloat64Array = frame.render
	assert(render.size() == frame.units.size() * 12)
	for i in frame.units.size():
		var u: Dictionary = frame.units[i]
		var r := render.slice(i * 12, i * 12 + 12)
		var flags := int(r[10])
		assert(int(r[0]) == u.id and Vector2(r[1], r[2]) == u.position and r[3] == u.radius and r[4] == u.facing)
		assert(is_equal_approx(r[5], u.speed) and r[6] == u.windup and is_equal_approx(r[7], u.health_fraction) and int(r[8]) == u.side and int(r[9]) == u.group_kind)
		assert(bool(flags & 1) == u.mounted and bool(flags & 2) == u.fleeing and bool(flags & 4) == u.dead and bool(flags & 8) == u.gone)
		assert(bool(flags & 16) == u.hero and bool(flags & 32) == bool(u.companion) and bool(flags & 64) == u.leader and bool(flags & 128) == u.blocking, "flags of %s" % u.id)

func _initialize() -> void:
	assert(ClassDB.class_exists("BattleCore"), "the native battle core is not loaded")
	var cases := [
		["res://battle/data/demo_battle.tres", [], 900],
		["res://battle/data/demo_siege.tres", [], 900],
		["res://battle/data/demo_battle.tres", [[{"type": "k1", "n": 40}, {"type": "k2a", "n": 30}, {"type": "k2c", "n": 30}], [{"type": "n1", "n": 50}, {"type": "n2a", "n": 25}, {"type": "n2s", "n": 25}]], 900],
	]
	for case in cases:
		var fast := _run(true, case[0], case[1], case[2])
		var plain := _run(false, case[0], case[1], case[2])
		assert(fast.size() == plain.size())
		for i in fast.size():
			assert(fast[i] == plain[i], "%s differs at %d: %s vs %s" % [case[0], i, str(fast[i]).left(300), str(plain[i]).left(300)])
	Movement.use_native = true
	print("Native core tests passed")
	quit(0)
