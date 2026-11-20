extends SceneTree
const Loader = preload("res://adapters/content/catalog_loader.gd")
const Catalog = preload("res://core/troops/data/catalog.gd")
const Factory = preload("res://core/battle/application/factory.gd")
const NativeColumns = preload("res://adapters/godot/native/columns.gd")
const Contacts = preload("res://adapters/godot/native/contacts.gd")
const Movement = preload("res://adapters/godot/native/movement.gd")
const HeroInput = preload("res://core/battle/application/hero_input.gd")
const Config = preload("res://core/battle/config.gd")
const TerrainGrid = preload("res://core/battle/model/terrain_grid.gd")
const TerrainRules = preload("res://core/battle/rules/terrain_rules.gd")
const KITE_CENTER := Vector2(1250, 850)
const KITE_RADIUS := 220.0
const VOLLEY_LONE_AHEAD := 170.0
const LARGE_FIELD := Vector2(3600, 2400) # Config.ARENA_TIERS: 201..500 a side.
const LARGE_TICKS := 600 # The approach and the first clash; the full battle would double the test time.
# Stage 1v: every doctrine must decide something in the compared battle, or the equal columns prove nothing.
const DOCTRINE_RULES := ["formed", "rank", "brace", "screen", "fallback", "rally", "rally_end", "shield", "spear"]
# Shield and spear priorities, proven by distance ratios the older multipliers cannot explain (see _check_doctrine).
const SHIELD_PROOF_RATIO := 1.36
const SPEAR_PROOF_RATIO := 1.25
# Stage 1b: a wavering fighter stands against a far enemy and closes in slower; a fugitive nobody pursues rallies.
const MORALE_RULES := ["standing", "slowed", "rallied", "fled"]
const MORALE_LOW_BASE := 30.0 # Base morale of the shaken half: never back above MORALE_STEADY_SHARE of it.
# TERRAIN.md 4.4 (stage Р1а): every fighter-level terrain rule must decide something in the compared battle, and the
# battle must differ from the same battle on the open field (otherwise equal columns would prove nothing).
# Stage Р3: the AI's terrain weights in target choice (aim_weight, the cell speed in "I will not catch him").
const TERRAIN_RULES := ["speed", "no_charge", "hidden", "range", "differs", "aim", "outrun"]
const AIM_PROOF_RATIO := 1.2 # Stage Р3 "aim": the enemy in cover is this much nearer than the shooter's target.
const TERRAIN_TICKS := 720 # The approach and the clash, where every rule fires; the rest of the battle adds only time.
func _initialize() -> void:
	var catalog := Catalog.new()
	assert(Loader.populate(catalog))
	assert(Movement.create().is_valid())
	for scenario in ["field", "siege", "castle", "breach", "mixed", "kite", "volley", "doctrine", "morale", "large", "terrain"]:
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
		if scenario == "morale":
			# Stage 1b (DESIGN.md 4.5): the player's side charges loose with a shaken half and a few men about to run.
			setup.player_army.assign([{"type": "n1", "n": 40}, {"type": "n2a", "n": 16}, {"type": "n3c", "n": 10}])
			setup.enemy_army.assign([{"type": "e1", "n": 36}, {"type": "e2a", "n": 16}, {"type": "e3c", "n": 12}])
		if scenario == "large":
			# TERRAIN Р0а: more than 200 a side stand on the larger field; the kernel must take its bounds, not the base field.
			setup.player_army.assign([{"type": "n1", "n": 120}, {"type": "n2a", "n": 60}, {"type": "n3c", "n": 50}])
			setup.enemy_army.assign([{"type": "e1", "n": 120}, {"type": "e2a", "n": 60}, {"type": "e3c", "n": 50}])
		if scenario == "terrain":
			# Stage Р1а: archers on a hill, cavalry in a forest, a ford and water across the way, brush on a flank.
			setup.player_army.assign([{"type": "n1", "n": 30}, {"type": "n2a", "n": 24}, {"type": "n3c", "n": 14}])
			setup.enemy_army.assign([{"type": "k1", "n": 30}, {"type": "k2a", "n": 20}, {"type": "k2c", "n": 18}])
		if scenario == "mixed":
			setup.player_army.assign([{"type": "n1", "n": 35}, {"type": "n2a", "n": 20}, {"type": "n3c", "n": 15}])
			setup.enemy_army.assign([{"type": "k1", "n": 30}, {"type": "k2a", "n": 20}, {"type": "k2c", "n": 20}])
		var a := Factory.create(setup, catalog, null, null, null, Contacts.create())
		var b := Factory.create(setup, catalog, null, null, null, Contacts.create(), Movement.create(), NativeColumns.create())
		var open = Factory.create(setup, catalog, null, null, null, Contacts.create()) if scenario == "terrain" else null
		var input := HeroInput.new()
		var fired := {"crowd": false, "wait": false, "leashed": false, "overkill": false, "front": false}
		for key in DOCTRINE_RULES: fired[key] = false
		for key in MORALE_RULES: fired[key] = false
		for key in TERRAIN_RULES: fired[key] = false
		var rider_timers := {}
		if scenario == "large":
			var beyond := false
			for unit in a._state.units:
				if unit.position.x > Config.ARENA_SIZE.x or unit.position.y > Config.ARENA_SIZE.y: beyond = true
			assert(a._state.arena_size == LARGE_FIELD and b._state.arena_size == LARGE_FIELD and beyond, "The large battle must use the larger field")
		for battle in ([a, b, open] if open != null else [a, b]):
			if scenario == "terrain":
				var state = battle._state
				_place(state, state.groups[0][Config.GROUP_INFANTRY], Vector2(1050, 800), 0.0)
				_place(state, state.groups[0][Config.GROUP_ARCHERS], Vector2(900, 800), 0.0)
				_place(state, state.groups[0][Config.GROUP_CAVALRY], Vector2(900, 1350), 0.0)
				_place(state, state.groups[1][Config.GROUP_INFANTRY], Vector2(1800, 800), PI)
				_place(state, state.groups[1][Config.GROUP_ARCHERS], Vector2(1950, 650), PI)
				_place(state, state.groups[1][Config.GROUP_CAVALRY], Vector2(1800, 1350), PI)
				battle.issue_order("charge", Vector2.ZERO, 3)
				if battle != open: state.set_terrain(_terrain_grid(state.arena_size))
				continue
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
			if scenario == "morale":
				var state = battle._state
				_place(state, state.groups[0][Config.GROUP_INFANTRY], Vector2(1150, 850), 0.0)
				_place(state, state.groups[0][Config.GROUP_ARCHERS], Vector2(1000, 850), 0.0)
				_place(state, state.groups[0][Config.GROUP_CAVALRY], Vector2(1050, 500), 0.0)
				_place(state, state.groups[1][Config.GROUP_INFANTRY], Vector2(1900, 850), PI)
				_place(state, state.groups[1][Config.GROUP_ARCHERS], Vector2(2050, 850), PI)
				_place(state, state.groups[1][Config.GROUP_CAVALRY], Vector2(2000, 1200), PI)
				battle.issue_order("charge", Vector2.ZERO, 3)
				state.groups[0][Config.GROUP_INFANTRY].loose = true
				for unit in state.groups[0][Config.GROUP_INFANTRY].units:
					if unit.id % 2 == 0:
						unit.base_morale = MORALE_LOW_BASE
						unit.morale = MORALE_LOW_BASE * 0.3
					elif unit.id % 7 == 1:
						unit.morale = -5.0
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
		for tick in (LARGE_TICKS if scenario == "large" else TERRAIN_TICKS if scenario == "terrain" else 1200):
			if siege and tick == 300:
				for battle in [a, b]: battle._state.wall.open_main_gate()
			if siege and tick == 600:
				for battle in [a, b]:
					for gate in battle._state.wall.gates: gate.hp = 0.0
			if tick == (700 if scenario == "doctrine" else 900) and scenario not in ["kite", "morale"]:
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
			if scenario == "morale":
				_check_morale(a._state, fired)
			if scenario == "terrain":
				_check_terrain(a._state, fired)
				if tick == 900: open._state.kill(open._hero)
				open.step()
			a.step()
			b.step()
			if open != null and a._state.motion.positions != open._state.motion.positions: fired.differs = true
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
		if scenario == "morale":
			for key in MORALE_RULES: assert(fired[key], "the stage 1b rule %s must fire in the compared battle: %s" % [key, fired])
		if scenario == "terrain":
			for key in TERRAIN_RULES: assert(fired[key], "the stage Р1а/Р3 rule %s must fire in the compared battle: %s" % [key, fired])
	print("Native movement parity tests passed")
	quit(0)

## The field of the terrain scenario: a hill under the player's archers, forest along the lower edge, brush on the
## enemy's flank and a river across the way with a ford in its upper half.
static func _terrain_grid(arena: Vector2):
	var grid = TerrainGrid.create(arena)
	for y in grid.height:
		for x in grid.width:
			var center: Vector2 = grid.cell_center(x, y)
			var k: int = y * grid.width + x
			if center.y > 1150.0: grid.cover[k] = TerrainGrid.Cover.FOREST
			elif center.y > 1000.0 and center.x > 1700.0: grid.cover[k] = TerrainGrid.Cover.BRUSH
			if center.x >= 1500.0 and center.x < 1600.0 and center.y <= 1150.0:
				grid.cover[k] = TerrainGrid.Cover.FORD if center.y < 700.0 else TerrainGrid.Cover.WATER
			var d := center.distance_to(Vector2(950, 800)) / 450.0
			grid.elevation[k] = clampi(roundi(220.0 * exp(-d * d * 2.0)), 0, 255)
	return grid

## Proof that the stage Р1а fighter rules decided something (the parity of the columns proves both backends apply
## them alike; "differs" in the caller proves they change the battle). Speed: a fighter walking on ground that is not
## open and flat. No charge: a rider ready to charge his target from the forest or a ford. Hidden: a shooter whose
## nearest enemy stands deep in the forest and who aims at someone else. Range: a shooter shooting from higher ground
## at a target beyond his plain range.
static func _check_terrain(state, fired: Dictionary) -> void:
	var grid = state.terrain_rules
	assert(grid != null)
	for unit in state.active_units:
		if unit.dead or unit.gone or unit.hero or unit.fleeing: continue
		var way: Vector2 = unit.plan_destination - unit.position
		if way.length() > Config.ARRIVAL_DISTANCE and unit.velocity.length() > 1.0 and TerrainRules.speed_scale(grid, unit.position, way, way.length()) != 1.0:
			fired.speed = true
		var target = state.unit_for(unit.target_handle)
		if target == null or target.dead or target.gone: continue
		var distance: float = unit.position.distance_to(target.position)
		# Stage Р3: a melee fighter weighing a receding target at the speed of his own cell towards it.
		if unit.attack_range <= 0.0 and distance > 0.0 and target.velocity.dot(target.position - unit.position) / distance > unit.speed * Config.TERRAIN_MIN_SPEED \
				and TerrainRules.speed_scale(grid, unit.position, target.position - unit.position, distance) != 1.0:
			fired.outrun = true
		if unit.mounted and unit.attack_range <= 0.0 and unit.ai_mode == Config.AI_MODE_MELEE and unit.charge_cooldown <= 0.0 and unit.velocity.length() > Config.CHARGE_MIN_SPEED \
				and distance < unit.collision_radius + target.collision_radius + unit.melee_reach + Config.CHARGE_EXTRA_REACH and TerrainRules.no_charge(grid, unit.position):
			fired.no_charge = true
		if unit.attack_range <= 0.0: continue
		if unit.ai_mode in [Config.AI_MODE_SHOOT, Config.AI_MODE_SHOOT_SLOT] and distance >= unit.attack_range and TerrainRules.range_scale(grid, unit.position, target.position) > 1.0 and distance < unit.attack_range * Config.TERRAIN_HIGH_RANGE_MULTIPLIER:
			fired.range = true
		var nearest = null
		var best := INF
		var covered := false # Stage Р3: an enemy in cover he sees, well nearer than his target in the open.
		var open_target: bool = TerrainRules.hit_chance(grid, target.position) == 1.0
		for enemy in state.active_units:
			if enemy.side == unit.side or enemy.dead or enemy.gone: continue
			var d: float = unit.position.distance_to(enemy.position)
			if d < best:
				best = d
				nearest = enemy
			if open_target and d * AIM_PROOF_RATIO < distance and TerrainRules.hit_chance(grid, enemy.position) < 1.0 and not TerrainRules.hidden(grid, enemy.position, d):
				covered = true
		if nearest != null and nearest != target and TerrainRules.hidden(grid, nearest.position, best):
			fired.hidden = true
		if covered:
			fired.aim = true

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

## Proof that the stage 1b fighter rules decided something. Standing: a wavering man of a loose charge waits where he
## stands although his target is farther than the engage distance and not running from him (no leash, no chase).
## Slowed: a wavering man closing in on his target at less than full speed (only the morale rule slows melee). Fled and
## rallied: a man ran and came back.
static func _check_morale(state, fired: Dictionary) -> void:
	for unit in state.active_units:
		if unit.dead or unit.gone or unit.hero: continue
		if unit.fleeing: fired.fled = true
		if unit.rallies > 0: fired.rallied = true
		if not unit.wavering or unit.fleeing: continue
		var group = state.groups[unit.side][unit.group_kind]
		if group.order != Config.ORDER_CHARGE or group.formed or unit.attack_range > 0.0: continue
		var target = state.unit_for(unit.target_handle)
		if target == null or target.dead or target.gone: continue
		var engage: float = Config.AI_MOUNTED_ENGAGE_DISTANCE if unit.mounted else Config.AI_FOOT_ENGAGE_DISTANCE
		if unit.ai_mode == Config.AI_MODE_SLOT and not unit.leashed and unit.plan_distance >= engage and unit.plan_destination == unit.position:
			if target.velocity.length() < unit.speed * Config.AI_CHARGE_CHASE_SPEED_SHARE: fired.standing = true
		if unit.ai_mode == Config.AI_MODE_MELEE and unit.plan_speed < 1.0: fired.slowed = true
