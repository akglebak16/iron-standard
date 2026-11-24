extends SceneTree
## AI debug overlay (ADR-022): F3 in the battle view turns the trace on and off, the panel names plans,
## orders and reasons in Russian, every code of the reference brain and of the commander (stage 1g) has a translation,
## the commander's plan scores read as a line, and the overlay
## leaves the battle as it is.
const ContentLoader = preload("res://adapters/content/catalog_loader.gd")
const Overlay = preload("res://apps/godot/presentation/battle/hud/ai_debug_overlay.gd")
const PresentationPreferences = preload("res://apps/godot/composition/presentation_preferences.gd")
const Tactics = preload("res://core/battle/rules/tactics.gd")
const Commander = preload("res://core/battle/simulation/ai/commander.gd")
const Config = preload("res://core/battle/config.gd")
const MotionStore = preload("res://core/battle/model/unit_columns.gd")

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	_check_translations()
	var packed: PackedScene = load("res://apps/godot/composition/main.tscn")
	var scene = packed.instantiate()
	var path := "res://.godot/test-ai-overlay-%d.cfg" % OS.get_process_id()
	assert(DirAccess.make_dir_recursive_absolute("res://.godot") == OK)
	scene.presentation_preferences = PresentationPreferences.new(path)
	assert(scene.presentation_preferences.save(false, false) == OK)
	root.add_child(scene)
	await process_frame
	var view = scene.get_node("Battle")
	assert(view._simulation.ai_debug_snapshot().is_empty())
	assert(not view.has_node("Hud/AiDebug"), "Nothing is created before the first use")
	_press(view, KEY_F3)
	assert(view._ai_overlay.enabled and view.has_node("Hud/AiDebug"))
	for i in 20:
		await process_frame
	var debug: Dictionary = view._ai_overlay.snapshot()
	assert(not debug.is_empty() and debug.sides.size() == 2)
	var panel: Label = view.get_node("Hud/AiDebug")
	assert(panel.visible)
	assert(panel.text.contains("Враги — эталон") and panel.text.contains("Свои — приказы игрока"))
	assert(panel.text.contains("Пехота") and panel.text.contains("Режимы:"))
	_press(view, KEY_F3)
	assert(not view._ai_overlay.enabled and not panel.visible)
	assert(view._simulation.ai_debug_snapshot().is_empty(), "F3 again stops the trace")
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("AI debug overlay tests passed")
	quit(0)

func _press(view, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	view._unhandled_input(event)

## Every plan, decision and reason code of both brains and every fighter mode has a Russian label.
func _check_translations() -> void:
	for brain: Script in [Tactics, Commander]:
		var constants := brain.get_script_constant_map()
		for name in constants:
			var code = constants[name]
			if name.begins_with("PLAN_"): assert(Overlay.PLANS.has(code), "No label for plan %s" % code)
			elif name.begins_with("DECISION_"): assert(Overlay.DECISIONS.has(code), "No label for decision %s" % code)
			elif name.begins_with("REASON_"): assert(Overlay.REASONS.has(code), "No label for reason %s" % code)
			elif name.begins_with("ROLE_"): assert(Overlay.ROLES.has(code), "No label for cavalry role %s" % code)
	for order in [Config.ORDER_HOLD, Config.ORDER_FOLLOW, Config.ORDER_CHARGE, Config.ORDER_RETREAT]:
		assert(Overlay.ORDERS.has(order))
	for mode in MotionStore.MODES:
		assert(Overlay.MODE_COLORS.has(mode))
	assert(Overlay.PROFILES.has(Config.AI_PROFILE_PLAYER) and Overlay.PROFILES.has(Config.AI_PROFILE_REFERENCE))
	assert(Overlay.PROFILES.has(Config.AI_PROFILE_COMMANDER))
	var plan := Overlay.plan_line({"best": [{"plan": "attack", "score": 0.6}], "reason": "outshot", "ratio": 0.77, "outshot": 0.75})
	assert(plan == " (атака 0.60; нас перестреливают; перевес 0.77, перестрелка +0.75)", plan)
	# Part 2 (#267): patience and the enemy coming.
	plan = Overlay.plan_line({"best": [{"plan": "defence", "score": 0.38}, {"plan": "attack", "score": 0.53}], "reason": "plan_kept",
		"ratio": 1.0, "outshot": 0.0, "patience": 0.43, "advancing": true})
	assert(plan == " (оборона 0.38, атака 0.53; план ещё в силе; перевес 1.00, перестрелка +0.00, терпение 0.43, враг идёт)", plan)
	assert(Overlay.plan_line({}) == "", "The reference brain weighs no plans")
	assert(Overlay.mode_color(Config.AI_MODE_MELEE, true) == Overlay.FLEEING_COLOR)
	var line := Overlay.group_line({"kind": 0, "order": "charge", "backing": false, "kited": true,
		"last": {"decision": "call_off", "reason": "hopeless_chase", "elapsed_seconds": 4.0}}, 6.5)
	assert(line == "Пехота: в атаку (бросил погоню) · отмена погони: безнадёжная погоня (2.5 с назад)", line)
	# Part 4 (#269): the cavalry role and why.
	line = Overlay.group_line({"kind": 2, "order": "hold", "backing": false, "kited": false, "role": Commander.ROLE_HUNT,
		"last": {"decision": Commander.DECISION_HUNT, "reason": Commander.REASON_SHOOTERS_BARE, "elapsed_seconds": 9.0}}, 10.0)
	assert(line == "Конница: держать, роль: охота на стрелков · охота на стрелков: стрелки врага без прикрытия (1.0 с назад)", line)
	# Part 5 (#270): the shield wall and why.
	line = Overlay.group_line({"kind": 0, "order": "hold", "backing": false, "kited": false, "wall": true,
		"last": {"decision": Commander.DECISION_ADVANCE, "reason": Commander.REASON_SHIELD_WALL, "elapsed_seconds": 9.5}}, 10.0)
	assert(line == "Пехота: держать, стена щитов · идёт вперёд: стеной щитов, под стрелами (0.5 с назад)", line)
	assert(Overlay.text({}) == "")
