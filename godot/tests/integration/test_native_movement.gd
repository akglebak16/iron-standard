extends SceneTree
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const NativeColumns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
const HeroInput = preload("res://core/battle/application/hero_input.gd")
const Config = preload("res://core/battle/config.gd")
const KITE_CENTER := Vector2(1250, 850)
const KITE_RADIUS := 220.0
const VOLLEY_LONE_AHEAD := 170.0
# Stage 1v: every doctrine must decide something in the compared battle, or the equal columns prove nothing.
const DOCTRINE_RULES := ["formed", "rank", "brace", "screen", "fallback", "rally", "rally_end", "shield", "spear"]
# Shield and spear priorities, proven by distance ratios the older multipliers cannot explain (see _check_doctrine).
const SHIELD_PROOF_RATIO := 1.36
const SPEAR_PROOF_RATIO := 1.25
func _initialize() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	assert(Movement.create().is_valid())
	for scenario in ["field", "siege", "castle", "breach", "mixed", "kite", "volley", "doctrine"]:
		var siege: bool = scenario in ["siege", "castle", "breach"]
		var setup = load("res://content/scenarios/demo_battle.tres").to_setup()
		setup.siege = siege
		setup.castle = scenario == "castle"
		setup.wall_damage = 0.65 if scenario == "breach" else 0.0
		setup.hero_profile.clear()
		setup.companion_profiles.clear()
		if scenario == "kite":
			# Stage 1a rules (DESIGN.md 1.4, 4.4): a fast hero circles in front of a charging mixed enemy.
			setup.player_army.assign([{"type": "n1", "n": 20}, {"type": "n2a", "n": 20}])
			setup.enemy_army.assign([{"type": "k1", "n": 40}, {"type": "k2c", "n": 15}, {"type": "e1", "n": 25}])
			setup.hero_position = KITE_CENTER + Vector2(KITE_RADIUS, 0)
		if scenario == "volley":
			# Stage 1a-archers (DESIGN.md 4.4): archers of both sides, foot and mounted, against a line with one man ahead.
			setup.player_army.assign([{"type": "n1", "n": 12}, {"type": "n2a", "n": 44}])
			setup.enemy_army.assign([{"type": "k1", "n": 40}, {"type": "k2a", "n": 20}, {"type": "k3h", "n": 10}])
		if scenario == "doctrine":
			# Stage 1v doctrines (DESIGN.md 4.3, 4.4): formed lines, spearmen, archers keeping distance, shock cavalry.
			setup.player_army.assign([{"type": "n1", "n": 24}, {"type": "n2s", "n": 16}, {"type": "n2a", "n": 20}, {"type": "n3c", "n": 10}])
			setup.enemy_army.assign([{"type": "e1", "n": 30}, {"type": "e2a", "n": 14}, {"type": "e3c", "n": 16}])
		if scenario == "mixed":
			setup.player_army.assign([{"type": "n1", "n": 35}, {"type": "n2a", "n": 20}, {"type": "n3c", "n": 15}])
			setup.enemy_army.assign([{"type": "k1", "n": 30}, {"type": "k2a", "n": 20}, {"type": "k2c", "n": 20}])
		var a := Factory.create(setup, catalog, null, null, null, Contacts.create())
		var b := Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create(), NativeColumns.create())
		var input := HeroInput.new()
		var fired := {"crowd": false, "wait": false, "leashed": false, "overkill": false, "front": false}
		for key in DOCTRINE_RULES: fired[key] = false
		var rider_timers := {}
		for battle in [a, b]:
			if scenario == "volley":
				_place(battle._state, battle._state.groups[0][Config.GROUP_ARCHERS], Vector2(900, 850), 0.0)
				_place(battle._state, battle._state.groups[0][Config.GROUP_INFANTRY], Vector2(1000, 850), 0.0)
				_place(battle._state, battle._state.groups[1][Config.GROUP_INFANTRY], Vector2(1420, 850), PI)
				_place(battle._state, battle._state.groups[1][Config.GROUP_ARCHERS], Vector2(1520, 850), PI)
				_place(battle._state, battle._state.groups[1][Config.GROUP_CAVALRY], Vector2(1500, 1250), PI)
				for group in battle._state.groups[0]: group.order = Config.ORDER_HOLD
				var lone = battle._state.groups[1][Config.GROUP_INFANTRY].units[0]
				lone.slot_offset += Vector2(0, VOLLEY_LONE_AHEAD)
				lone.position = battle._state.groups[1][Config.GROUP_INFANTRY].slot_position(lone, battle._state.arena_size)
				continue
			if scenario == "doctrine":
				# The enemy (reference AI) advances, flanks with its cavalry and charges; the player's side holds with
				# its archers ahead of the spearmen until the hero falls (tick 700) and every group charges.
				var state = battle._state
				_place(state, state.groups[0][Config.GROUP_INFANTRY], Vector2(900, 800), 0.0)
				_place(state, state.groups[0][Config.GROUP_ARCHERS], Vector2(1000, 1060), 0.0)
				_place(state, state.groups[0][Config.GROUP_CAVALRY], Vector2(700, 600), 0.0)
				_place(state, state.groups[1][Config.GROUP_INFANTRY], Vector2(1500, 850), PI)
				_place(state, state.groups[1][Config.GROUP_ARCHERS], Vector2(1650, 850), PI)
				_place(state, state.groups[1][Config.GROUP_CAVALRY], Vector2(1550, 1250), PI)
				for group in state.groups[0]: group.order = Config.ORDER_HOLD
				continue
			if scenario == "kite":
				battle._hero.speed = 260.0
				battle._hero.max_hp = 1000000.0
				battle._hero.hp = battle._hero.max_hp
				for group in battle._state.groups[0]: group.order = Config.ORDER_HOLD
				for group in battle._state.groups[1]: group.order = Config.ORDER_CHARGE
				# Stage 1a rules belong to the loose charge (stage 1v forms a line in the field, DESIGN.md 4.3).
				battle._state.groups[1][Config.GROUP_INFANTRY].loose = true
				# Split the enemy infantry into two wings far from their formation places: the leash must pull them back.
				for unit in battle._state.groups[1][Config.GROUP_INFANTRY].units:
					unit.position.y += 420.0 if unit.id % 2 else -420.0
				continue
			battle.issue_order("charge", Vector2.ZERO, 3)
			if scenario == "mixed":
				for unit in battle._state.active_units:
					if unit.hero: continue
					unit.position = Vector2(1200 + unit.side * 100 + (unit.id % 6) * 18, 550 + (unit.id % 12) * 22)
				for group in battle._state.groups[1]: group.order = "charge"
		for tick in 1200:
			if siege and tick == 300:
				for battle in [a, b]: battle._state.wall.open_main_gate()
			if siege and tick == 600:
				for battle in [a, b]:
					for gate in battle._state.wall.gates: gate.hp = 0.0
			if tick == (700 if scenario == "doctrine" else 900) and scenario != "kite":
				for battle in [a, b]: battle._state.kill(battle._hero)
			if scenario == "kite":
				var offset: Vector2 = a._hero.position - KITE_CENTER
				var radial := offset.normalized() if offset.length() > 1.0 else Vector2.RIGHT
				var move := Vector2(-radial.y, radial.x) + radial * clampf((KITE_RADIUS - offset.length()) / 40.0, -1.0, 1.0)
				input.move = move.normalized()
				input.face = move.angle()
				for battle in [a, b]: assert(battle.set_hero_input(input))
				for unit in a._state.active_units:
					if unit.attackers > Config.TARGET_CROWD_FREE_ATTACKERS: fired.crowd = true
					if unit.chase_seconds > 0.0: fired.wait = true
					if unit.leashed: fired.leashed = true
			if scenario == "volley" and tick < 240:
				_check_volley(a._state, fired)
			if scenario == "doctrine":
				_check_doctrine(a._state, fired, tick, rider_timers)
			a.step()
			b.step()
			assert(a._rng.state == b._rng.state, "RNG tick %d siege %s" % [tick, siege])
			assert(a.take_events() == b.take_events(), "Events tick %d siege %s" % [tick, siege])
			if tick % 30 == 0:
				assert(a.snapshot() == b.snapshot(), "Snapshot tick %d" % tick)
				var left_frame = a.snapshot(true).render
				var right_frame = b.snapshot(true).render
				assert(left_frame.size() == right_frame.size())
				for row in left_frame.size(): assert(left_frame.unit_at(row, 0.5) == right_frame.unit_at(row, 0.5), "Render row %d tick %d" % [row, tick])
			for field in ["positions", "velocities", "real_fields", "integer_fields", "vector_fields"]:
				assert(a._state.motion.get(field) == b._state.motion.get(field), "Columns %s tick %d %s" % [field, tick, scenario])
			for index in a._state.units.size():
				assert(a._state.units[index].morale == b._state.units[index].morale)
				assert(a._state.units[index].kills == b._state.units[index].kills)
		if scenario == "kite":
			assert(fired.crowd and fired.wait and fired.leashed, "the stage 1a rules must fire in the compared battle: %s" % fired)
		if scenario == "volley":
			assert(fired.overkill and fired.front, "the stage 1a-archers rules must fire in the compared battle: %s" % fired)
		if scenario == "doctrine":
			for key in DOCTRINE_RULES: assert(fired[key], "the stage 1v rule %s must fire in the compared battle: %s" % [key, fired])
	print("Native movement parity tests passed")
	quit(0)

static func _place(state, group, at: Vector2, facing: float) -> void:
	group.center = at
	group.direction = facing
	group.layout(true)
	for unit in group.units:
		unit.position = group.slot_position(unit, state.arena_size)
		unit.velocity = Vector2.ZERO

## Proof that the stage 1a-archers rules decided something in this battle. Overkill: fewer archers aim at the man
## ahead of the line than have him as their plain nearest enemy (the front spread alone cannot outweigh his lead).
## Front: an archer aims past his nearest enemy although that one still needs more shooters.
static func _check_volley(state, fired: Dictionary) -> void:
	var lone = state.groups[1][Config.GROUP_INFANTRY].units[0]
	var nearest_to_lone := 0
	for archer in state.groups[0][Config.GROUP_ARCHERS].units:
		if archer.dead or archer.fleeing or archer.target_handle == 0: continue
		var nearest = null
		var best := INF
		for enemy in state.active_units:
			if enemy.side == archer.side or enemy.dead or enemy.gone or enemy.hero: continue
			var d: float = archer.position.distance_to(enemy.position)
			if d < best:
				best = d
				nearest = enemy
		if nearest == null: continue
		if nearest == lone: nearest_to_lone += 1
		var target = state.unit_for(archer.target_handle)
		if target != null and target != nearest and nearest != lone:
			var needed: float = nearest.hp / (archer.damage * Config.TARGET_VOLLEY_HIT_SHARE)
			if float(nearest.aimers) + 1.0 <= needed: fired.front = true
	if not lone.dead and lone.aimers < nearest_to_lone:
		fired.overkill = true

## Proof that the stage 1v doctrines decided something. Formed: an infantry line in a charge with men keeping their
## places in its ranks. Brace: a spearman standing against a rider. Screen: a spearman sent to the screen line in front
## of his archers. Fallback: an archer stepping back. Rally: a shock cavalry group rallying and charging again.
## Shield: a shooter aiming past a nearest enemy who is shielded and not yet doomed, farther than the front spread and
## the sticky current target allow (1.15 / 0.85 = 1.35). Spear: a rider who chose his target in this very tick (his
## retarget timer went up), passing a spearman who is his nearest enemy, not crowded and not running away, farther than
## the sticky current target allows (1 / 0.85 = 1.18; a rider moves too much between his choices to judge later).
static func _check_doctrine(state, fired: Dictionary, tick: int, rider_timers: Dictionary) -> void:
	for side in 2:
		for group in state.groups[side]:
			if group.formed: fired.formed = true
			if group.rally: fired.rally = true
			elif fired.rally and group.kind == Config.GROUP_CAVALRY and group.order == Config.ORDER_CHARGE: fired.rally_end = true
			if group.screen.is_finite():
				for unit in group.units:
					if unit.anti_cavalry and not unit.dead and unit.plan_destination.distance_to(group.screen) < Config.AI_SCREEN_RADIUS * 0.5: fired.screen = true
	for unit in state.active_units:
		if unit.ai_mode == Config.AI_MODE_RANK: fired.rank = true
		elif unit.ai_mode == Config.AI_MODE_BRACE: fired.brace = true
		elif unit.ai_mode == Config.AI_MODE_FALLBACK: fired.fallback = true
	for unit in state.active_units:
		if unit.dead or unit.gone or unit.hero or unit.fleeing or unit.target_handle == 0: continue
		var shooter: bool = unit.attack_range > 0.0
		var rider: bool = unit.mounted and not shooter
		if rider:
			var previous: float = rider_timers.get(unit.id, INF)
			rider_timers[unit.id] = unit.target_timer
			if unit.target_timer <= previous: continue
		elif not shooter or tick % 5 != 0: continue
		var target = state.unit_for(unit.target_handle)
		if target == null or target.dead or target.gone: continue
		var nearest = null
		var best := INF
		for enemy in state.active_units:
			if enemy.side == unit.side or enemy.dead or enemy.gone or enemy.hero: continue
			var d: float = unit.position.distance_to(enemy.position)
			if d < best:
				best = d
				nearest = enemy
		if nearest == null or nearest == target or nearest.fleeing: continue
		var ratio: float = unit.position.distance_to(target.position) / maxf(best, 1.0)
		if shooter and nearest.attack_range <= 0.0 and nearest.shield_block > 0.0 and target.shield_block <= 0.0 and ratio > SHIELD_PROOF_RATIO:
			if float(nearest.aimers) + 1.0 <= nearest.hp / (unit.damage * Config.TARGET_VOLLEY_HIT_SHARE): fired.shield = true
		if rider and nearest.anti_cavalry and not nearest.mounted and nearest.attackers < Config.TARGET_CROWD_FREE_ATTACKERS and target.attack_range <= 0.0 and ratio > SPEAR_PROOF_RATIO:
			if nearest.velocity.dot(nearest.position - unit.position) <= 0.0: fired.spear = true
