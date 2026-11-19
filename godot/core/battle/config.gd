extends RefCounted

## Balance values copied from the browser battle. Change them here, then run Godot tests.
const TroopConfig = preload("res://core/troops/config.gd")
const ARENA_SIZE := Vector2(2600, 1700) # The base field: battles up to ARENA_TIERS[0] fighters a side and every siege.
## TERRAIN.md 5 (stage Р0а): the field grows with the larger army on it (figures a side at the start, after the cap).
## [fighters a side up to, field size, side 0 infantry front as a share of the width]; above the last row the last
## field is used. The first row is the base field with the browser placement (FRONT_X). Sizes change only here.
const ARENA_TIERS := [
	[200, Vector2(2600, 1700), 640.0 / 2600.0],
	[500, Vector2(3600, 2400), 0.29],
	[1000, Vector2(4600, 3000), 0.32],
]
const DEFAULT_BIOME := "grass"
const TERRAIN_CELL := 32.0 # TERRAIN.md 3.4: side of a battle terrain cell (model/terrain_grid.gd, api/native/terrain_grid.hpp).
## TERRAIN.md 4.4 (stage Р1а): rules of the terrain grid, rules/terrain_rules.gd and movement_kernel.hpp. Starting numbers
## of the table, by the recommendation to question 5 (no answer from Gleb yet); the arena checks them (TERRAIN.md 8).
## Speed by cover, in TerrainGrid.Cover order: open, brush, forest, field, road, ford, bridge, water, rock. Deep water
## and rocks become impassable with path finding (Р2); until then they are the slowest ground.
const TERRAIN_COVER_SPEED := [1.0, 0.9, 0.75, 0.9, 1.1, 0.5, 1.0, 0.35, 0.35]
const TERRAIN_MIN_SPEED := 0.35 # Cover and slope multiply; the product never goes below this.
const TERRAIN_UPHILL_SPEED := 0.85
const TERRAIN_DOWNHILL_SPEED := 1.05
## A slope: the height bytes of the two neighbour cells along the way differ by at least this per two cells.
const TERRAIN_SLOPE_STEP := 4.0
## "Higher than the target": the height bytes of the two cells differ by at least this.
const TERRAIN_HIGHER_STEP := 4
const TERRAIN_HIGH_RANGE_MULTIPLIER := 1.15 # A shooter higher than his target shoots this much farther.
const TERRAIN_HIGH_STRIKE_MULTIPLIER := 1.1 # A melee blow or a charge from higher ground.
const TERRAIN_BANK_DEFENSE := 1.15 # A man on the bank against one wading in a ford (or water) takes damage / this.
const TERRAIN_FOREST_HIT_CHANCE := 0.6 # An arrow that lands on a man in the forest hits him with this chance...
const TERRAIN_BRUSH_HIT_CHANCE := 0.85 # ...in the brush with this one; the trees catch the rest.
const TERRAIN_FOREST_SIGHT := 250.0 # A shooter does not pick a target in the forest farther than this.
const SIEGE_WALL_RIGHT_OFFSET := 980.0
const SIEGE_WALL_HALF_WIDTH := 22.0
# siegeSetup in src/03_battle.js: a town has a main gate and two side gates, a castle one heavy gate; [top, bottom, hp]
# from the arena middle. Gates are shut and must be battered down. Order breaks equal-distance ties.
const SIEGE_TOWN_GATES := [Vector3(-75, 75, 900), Vector3(-520, -440, 420), Vector3(440, 520, 420)]
const SIEGE_CASTLE_GATES := [Vector3(-70, 70, 1400)]
const SIEGE_CASTLE_WALL_HALF_WIDTH := 32.0
const SIEGE_GATE_MIN_HP := 120.0
const SIEGE_GATE_DAMAGE_WEAKENING := 0.7 # Battered walls: gates keep 30% of their strength.
const SIEGE_GATE_SKILL_WEAKENING := 0.4 # Companion siegecraft at its cap takes 40% more.
const SIEGE_GATE_BASH_SHARE := 0.35 # Share of a fighter's damage per second that goes into the gate.
const SIEGE_GATE_BASH_REACH := 14.0
const SIEGE_GATE_HIT_FLASH := 0.3
const SIEGE_GATE_SORTIE_SECONDS := 45.0 # The garrison opens the main gate and comes out to fight.
const SIEGE_GATE_SORTIE_MIN_INFANTRY := 10
const SIEGE_BREACH_MIN_DAMAGE := 0.3 # A badly battered wall has an open breach.
const SIEGE_BREACH_BASE_WIDTH := 60.0
const SIEGE_BREACH_DAMAGE_WIDTH := 80.0
const SIEGE_BREACH_OFFSET := 230.0
const SIEGE_BREACH_SEED_OFFSET := 3
const SIEGE_ROUTE_ID_SPREAD := 23 # (id * 37) % 23 spreads attackers between equally close gaps.
const SIEGE_ROUTE_ID_FACTOR := 37
const SIEGE_WALL_RADIUS_PADDING := 0.8
const SIEGE_GAP_RADIUS_PADDING := 0.75
const SIEGE_INFANTRY_OFFSET := 80.0
const SIEGE_ARCHER_OFFSET := 52.0
const SIEGE_CAVALRY_RIGHT_OFFSET := 380.0
const SIEGE_DEFENDER_MORALE := 28.0
const SIEGE_SKILL_MAX := 0.9
# src/03c_siegedef.js: stones and boiling oil from the wall.
const SIEGE_DEFAULT_STONES := 10
const SIEGE_DEFAULT_OIL := 2
const SIEGE_DAMAGE_SUPPLY_LOSS := 0.6
const SIEGE_SIDE_CAULDRON_MIN_OIL := 3
const SIEGE_SIDE_OIL_SHARE := 0.67
const SIEGE_DEFENSE_SKILL_SCALE := 0.5
const SIEGE_DEFENDER_LINE_OFFSET := 10.0
const SIEGE_STONE_FIRST_DELAY := 5.0
const SIEGE_STONE_MIN_DEFENDERS := 6
const SIEGE_STONE_NEAR_EDGE := 8.0
const SIEGE_STONE_RANGE := 320.0
const SIEGE_STONE_CROWD_BOX := 60.0
const SIEGE_STONE_MIN_CROWD := 2
const SIEGE_STONE_RETRY_SECONDS := 1.2
const SIEGE_STONE_LEAD_SECONDS := 0.6
const SIEGE_STONE_ORIGIN_OFFSET := 18.0
const SIEGE_STONE_EDGE := 60.0
const SIEGE_STONE_FLIGHT_SECONDS := 0.95
const SIEGE_STONE_COOLDOWN_MIN := 4.5
const SIEGE_STONE_COOLDOWN_MAX := 7.0
const SIEGE_STONE_RATE_BASE := 0.6
const SIEGE_STONE_RATE_DEFENDERS := 0.4
const SIEGE_STONE_FULL_DEFENDERS := 25.0
const SIEGE_STONE_RADIUS := 52.0
const SIEGE_STONE_DAMAGE := 32.0
const SIEGE_STONE_EDGE_FALLOFF := 0.5
const SIEGE_STONE_MORALE_LOSS := 4.0
const SIEGE_OIL_FIRST_DELAY := 4.0
const SIEGE_OIL_DELAY_STEP := 2.0
const SIEGE_OIL_MIN_DEFENDERS := 4
const SIEGE_OIL_REACH := 140.0
const SIEGE_OIL_GAP_MARGIN := 40.0
const SIEGE_OIL_MIN_CROWD := 3
const SIEGE_OIL_COOLDOWN := 14.0
const SIEGE_OIL_MORALE_LOSS := 6.0
const SIEGE_FIRE_OFFSET := 36.0
const SIEGE_FIRE_HALF_WIDTH := 64.0
const SIEGE_FIRE_MIN_HALF_HEIGHT := 46.0
const SIEGE_FIRE_HEIGHT_PADDING := 12.0
const SIEGE_FIRE_SECONDS := 6.0
const SIEGE_FIRE_DAMAGE_INTERVAL := 0.5
const SIEGE_FIRE_DAMAGE := 6.0
const SIEGE_FIRE_PIERCE := 0.5
const SIEGE_FIRE_MORALE_LOSS := 1.6
const SIEGE_CAULDRON_X_OFFSET := 6.0
const SIEGE_POUR_Y_OFFSET := 10.0
const AI_TACTIC_SIEGE := "siege"
const SIEGE_ROUTE_DESTINATION_WEIGHT := 0.6
const SIEGE_ROUTE_CROSS_READY_DISTANCE := 34.0
const SIEGE_ROUTE_CROSS_DISTANCE := 70.0
const SIEGE_ROUTE_APPROACH_OFFSET := 30.0
const SIEGE_ROUTE_CENTERING_DISTANCE := 140.0
const SIEGE_COVER_DEPTH := 80.0
const SIEGE_COVER_DAMAGE_MULTIPLIER := 0.45
const SIEGE_COVER_SKILL_SCALE := 0.5
const SIEGE_ALERT_DISTANCE := 160.0
const SIEGE_INFANTRY_ATTACKERS_INSIDE := 2
const SIEGE_CAVALRY_ATTACKERS_INSIDE := 4
const SIEGE_ARCHERS_ATTACKERS_INSIDE := 8
const SIEGE_INFANTRY_FORCE_CHARGE_SECONDS := 150.0
const SIEGE_CAVALRY_FORCE_CHARGE_SECONDS := 170.0
const SPATIAL_CELL_SIZE := 64.0 # Broad-phase cell; changing it must not change battle results.
const SPATIAL_MIN_UNITS := 64 # Small battles avoid index construction overhead.
# Placement on the base field; on a larger field rules/arena_layout.gd turns it into shares (offsets grow with the field).
const FRONT_X := 640.0
const CENTER_Y := 850.0
const HERO_START := Vector2(730, 850) # startBattle: mkUnit(0, hd, 'player', 730, H / 2), on the base field.
const ARCHER_REAR_OFFSET := 105.0
const CAVALRY_REAR_OFFSET := 20.0
const CAVALRY_FLANK_OFFSET := 380.0
const ALLY_FLANK_OFFSET := 380.0 # allied line beside the player's, on the flank away from his cavalry (#243)
const GROUP_KINDS := TroopConfig.GROUP_KINDS
const ALL_GROUPS := TroopConfig.GROUP_KINDS
## Commands on the field (#243): each has its own groups in State.groups and its own commander.
const COMMAND_PLAYER := 0
const COMMAND_ENEMY := 1
const COMMAND_ALLY := 2  # the player's allies: side 0, their own commander
const GROUP_INFANTRY := TroopConfig.GROUP_INFANTRY
const GROUP_ARCHERS := TroopConfig.GROUP_ARCHERS
const GROUP_CAVALRY := TroopConfig.GROUP_CAVALRY
const ORDER_HOLD := "hold"
const ORDER_FOLLOW := "follow"
const ORDER_CHARGE := "charge"
const ORDER_RETREAT := "back"
const HOLD_ARCHER_OFFSET := 95.0
const HOLD_CAVALRY_OFFSET := 240.0
const RETREAT_DISTANCE := 300.0
const RETREAT_EDGE := 80.0
const SLOT_EDGE := 30.0
const FORMATION_FACTOR := [3.2, 6.0, 4.0]
const FORMATION_MIN_COLUMNS := [4, 5, 4]
const FORMATION_SPACING := [29.0, 38.0, 50.0]
const FORMATION_ROW_DEPTH := 0.92
const ARMOR_SCALE := 55.0
const MIN_HIT_DAMAGE := 1
const BASE_MORALE := 72.0
const TIER_MORALE := 14.0
const HIT_MORALE_PER_DAMAGE := 0.12
const KILL_MORALE_BONUS := 8.0
const DEATH_MORALE_RADIUS := 170.0
const LEADER_DEATH_MORALE := 9.0
const HERO_DOWN_MORALE_LOSS := 7.0
const COMPANION_DOWN_MORALE_LOSS := 4.0
const BATTLE_END_DELAY_SECONDS := 2.2
const BASE_WOUNDED_CHANCE := 0.38
const COMPANION_TIER := 3
const COMPANION_BASE_MORALE := 160.0
const COMPANION_TROOP_PREFIX := "comp:"
const XP_PER_ENEMY_TIER := 10.0
const XP_MOUNTED_ENEMY_BONUS := 5.0
const LEADER_GLOBAL_MORALE_LOSS := 10.0
const LEADER_HEALTH_MULTIPLIER := 1.9
const LEADER_DAMAGE_MULTIPLIER := 1.3
const LEADER_BASE_MORALE := 200.0
const ALLY_DEATH_MORALE := 1.6
const ALLY_DEATH_MORALE_PER_TIER := 0.5
const ENEMY_DEATH_MORALE_BONUS := 3.0
const SOLO_UNIT_CAP := 300
const RESERVE_WAVE_SHARE := 1.0 / 3.0 # A third of the field cap enters at once.
const RESERVE_EDGE_OFFSET := 90.0
const RESERVE_SPAWN_X_JITTER := 50.0
const RESERVE_SPAWN_Y_SPREAD := 420.0
const LEADER_BOND_RESERVE_LOSS := 0.35
const SPAWN_JITTER := 30.0
const SPEED_RANDOM_MIN := 0.94
const SPEED_RANDOM_MAX := 1.06
const FOLLOW_REAR_OFFSET := [50.0, 135.0, 60.0]
const FOLLOW_CAVALRY_SIDE_OFFSET := 170.0
const AI_INFANTRY_CHARGE_DISTANCE := 215.0
const AI_INFANTRY_FORCE_CHARGE_SECONDS := 80.0
const AI_GROUP_ADVANCE_DELAY_SECONDS := 2.5
const AI_INFANTRY_ADVANCE_SPEED := 40.0
const AI_ARCHER_CHARGE_DISTANCE := 105.0
const AI_ARCHER_NO_INFANTRY_CHARGE_DISTANCE := 190.0
const AI_ARCHER_ADVANCE_DISTANCE := 325.0
const AI_ARCHER_ADVANCE_WITH_INFANTRY_SPEED := 40.0
const AI_ARCHER_ADVANCE_ALONE_SPEED := 30.0
const AI_CAVALRY_FLANK_DELAY_SECONDS := 4.0
const AI_CAVALRY_FLANK_OFFSET := 430.0
const AI_CAVALRY_FLANK_EDGE := 120.0
const AI_CAVALRY_FLANK_PROGRESS := 0.7
const AI_CAVALRY_FLANK_SPEED := 105.0
const AI_CAVALRY_WAYPOINT_ARRIVAL := 60.0
const AI_CAVALRY_CHARGE_DISTANCE := 250.0
const AI_TACTIC_WAIT := "wait"
const AI_TACTIC_FLANK := "flank"
# Squad-level AI (DESIGN.md 1.4, stage K): attack decisions look at enemy squads, not single fighters.
const AI_SQUAD_MIN_UNITS := 3 # A group with fewer ready fighters (e.g. the hero's companions alone) is not a squad.
const AI_SQUAD_SCAN_SECONDS := 0.25 # Squad picture and kite check refresh; decisions in between reuse it.
const AI_SQUAD_SAMPLE_LIMIT := 64 # Fighters sampled per group and scan; larger groups use a fixed stride.
const AI_KITE_SECONDS := 3.0 # A charge that has not closed the gap for this long is called off.
const AI_KITE_PROGRESS_DISTANCE := 20.0 # The mean chase gap must shrink by this much to count as progress.
const AI_KITE_CONTACT_DISTANCE := 60.0 # Closer than this (or within weapon range) a fighter is fighting, not chasing.
const AI_KITE_SPEED_RATIO := 1.0 # Target speed above own speed times this marks the chase as hopeless.
const AI_KITE_RECHARGE_DISTANCE := 80.0 # A group that called off a chase closes in formation and charges only at contact.
const AI_KITE_CHASER_SHARE := 0.5 # More than this share of sampled fighters must be in hopeless chases.
const AI_MISSILE_LOSS_MEMORY_SECONDS := 6.0 # Decay time of the per-side count of fighters lost to missiles.
const AI_MISSILE_PRESSURE_LOSSES := 2.0 # Recent missile losses from which a side counts as under fire.
# AI foundation (DESIGN.md stage 0-battle, ADR-022). Observation and scheduling only: nothing below changes a battle.
const AI_PROFILE_PLAYER := "" # The side follows player orders; no AI brain makes decisions for it.
const AI_PROFILE_REFERENCE := "reference" # The current timer-and-threshold brain (tactics.gd), frozen as the arena reference.
const AI_COMMANDER_PERIOD_SECONDS := 0.5 # Decision schedule: one side commander decision this often.
const AI_SQUAD_PERIOD_SECONDS := 0.25 # Decision schedule: one decision per group this often, staggered by group number.
const AI_TRACE_RECENT := 32 # Decision records kept for the debug snapshot.
# Field assessment (DESIGN.md 4.1). Unit classes for the "who beats whom" matrix, read from properties, not troop IDs.
const AI_CLASS_FOOT := 0
const AI_CLASS_SPEAR := 1 # Foot with anti_cavalry.
const AI_CLASS_ARCHER := 2 # Foot with a ranged attack.
const AI_CLASS_CAVALRY := 3 # Mounted melee.
const AI_CLASS_HORSE_ARCHER := 4 # Mounted with a ranged attack.
const AI_CLASSES := 5
## Strength multiplier of a row class against a column class. An estimate for decisions, never a combat value.
const AI_MATCHUP := [
	[1.0, 1.0, 1.3, 0.8, 0.7],
	[0.9, 1.0, 1.2, 1.6, 0.8],
	[1.1, 1.2, 1.0, 0.8, 0.9],
	[1.2, 0.6, 1.6, 1.0, 1.2],
	[1.1, 1.2, 0.9, 0.8, 1.0],
]
const AI_FIELD_TIER_POWER := 0.25 # Fighting power of a fighter: weight x health share x (1 + this x tier).
const AI_FIELD_CONTACT_DISTANCE := 60.0 # A melee fighter this close to its target counts as engaged.
const AI_FIELD_ENGAGED_SHARE := 0.25 # A group with this share of engaged fighters is bound by the fight.
const AI_FIELD_THREAT_RADIUS := 600.0 # Enemy groups farther than this from a group's center add no threat.
const AI_FIELD_FRONT_ARC := PI * 0.25 # Enemy within this angle of the group's facing is in front.
const AI_FIELD_REAR_ARC := PI * 0.75 # Beyond this angle the enemy is behind; in between, on a flank.
const FORMATION_RELAYOUT_SECONDS := 2.4
const FOOT_STEERING_RATE := 10.0
const HORSE_STEERING_RATE := 2.4
const ARRIVAL_DISTANCE := 2.0
const ARRIVAL_BRAKE := 5.0
const FLEE_SPEED_MULTIPLIER := 1.12
const FLEE_DESTINATION_PADDING := 90.0
const FLEE_EXIT_PADDING := 25.0
const FOOT_COLLISION_RADIUS := 12.5
const HORSE_COLLISION_RADIUS := 19.0
const FOOT_MASS := 1.0
const HORSE_MASS := 3.0
const FRIEND_COLLISION_PUSH := 0.5
const ENEMY_COLLISION_PUSH := 0.9
const MIN_COLLISION_DISTANCE := 0.01
const CONTACT_QUERY_SLACK := 10.0
const FIELD_LEFT_RIGHT_MARGIN := 20.0
const FIELD_TOP_MARGIN := 26.0
const FIELD_BOTTOM_MARGIN := 16.0
const DEFAULT_MELEE_REACH := 6.0
const MELEE_DAMAGE_MIN := 0.8
const MELEE_DAMAGE_MAX := 1.2
const REAR_ANGLE := 2.1
const REAR_DAMAGE_MULTIPLIER := 1.4
const BLOCK_ARC := 1.25
const SHIELD_ARROW_BONUS_MULTIPLIER := 1.25
const SHIELD_ARROW_MAX_BLOCK := 0.88
const UNSHIELDED_ARROW_BLOCK_MULTIPLIER := 0.85
const HERO_SHIELD_ACTIVE_ARROW_MULTIPLIER := 1.5
const HERO_SHIELD_IDLE_ARROW_MULTIPLIER := 0.5
const ANTI_CAVALRY_MULTIPLIER := 1.7
const CHARGE_MIN_SPEED := 80.0
const CHARGE_EXTRA_REACH := 5.0
const CHARGE_COOLDOWN := 1.7
const CHARGE_BASE_DAMAGE := 0.6
const CHARGE_SPEED_DAMAGE_DIVISOR := 150.0
const CHARGE_ANTI_DAMAGE_MULTIPLIER := 0.45
const CHARGE_BLOCK_DAMAGE_MULTIPLIER := 0.4
const CHARGE_FRONT_ARC := 1.1
const CHARGE_COUNTER_DAMAGE := 16.0
const CHARGE_COUNTER_RANDOM_MIN := 0.8
const CHARGE_COUNTER_RANDOM_MAX := 1.3
const CHARGE_KNOCKBACK := 15.0
const CHARGE_ATTACKER_VELOCITY_MULTIPLIER := 0.4
const CHARGE_ATTACK_COOLDOWN := 0.45
const HERO_CHARGE_MIN_SPEED := 95.0
const HERO_CHARGE_EXTRA_REACH := 5.0
const HERO_CHARGE_DIRECTION_ARC := 0.9
const HERO_CHARGE_COOLDOWN := 0.9
const SHOT_SPEED := 620.0
const THROW_SPEED := 460.0
const PROJECTILE_START_DELAY := 0.16
const SHOT_BASE_SCATTER := 5.0
const PROJECTILE_HIT_PADDING := 3.0
const AIM_VELOCITY_LEAD := 0.8
const PROJECTILE_START_HEIGHT := 16.0
const PROJECTILE_HIT_HEIGHT := 10.0
const PROJECTILE_THROW_WEAPON := "throw"
const PROJECTILE_CROSSBOW_WEAPON := "xbow"
const HERO_BASE_HEALTH := 100.0
const HERO_HEALTH_PER_VITALITY := 14.0
const HERO_ALLY_MORALE_PER_CHARISMA := 4.0
const HERO_MIN_HEALTH_FRACTION := 0.3
const HERO_BASE_FOOT_SPEED := 86.0
const HERO_SPEED_PER_AGILITY := 3.0
const HERO_MELEE_DAMAGE_PER_STRENGTH := 2.5
const HERO_MELEE_BASE_COOLDOWN := 0.56
const HERO_MELEE_AGILITY_COOLDOWN := 0.03
const HERO_MELEE_MIN_COOLDOWN := 0.3
const HERO_RANGED_AGILITY_COOLDOWN := 0.025
const HERO_RANGED_MIN_COOLDOWN := 0.35
const HERO_SWAP_COOLDOWN_FLOOR := 0.35
const HERO_SLOT_REQUEST_TICKS := 90
const HERO_GEAR_ACCURACY_MULTIPLIER := 1.8
const EQUIPPED_DEFAULT_ACCURACY := 0.05
const RANGED_MELEE_DAMAGE_MULTIPLIER := 0.6
const SHOOT_MOVE_SPEED_LIMIT := 26.0
const RETARGET_MIN_SECONDS := 0.35
const RETARGET_RANDOM_SECONDS := 0.35
const RETARGET_INITIAL_MAX_SECONDS := 0.5
const TARGET_FLEE_DISTANCE_MULTIPLIER := 1.7
const CAVALRY_ARCHER_TARGET_MULTIPLIER := 0.7
const CURRENT_TARGET_MULTIPLIER := 0.85
# Stage 1a (DESIGN.md 1.4 step 2, 4.4): fighter-level rules, the same for both sides and in GDScript and C++.
# A melee fighter weighs a target farther away when others already fight it and when it runs away faster than
# he can follow. Attackers are melee fighters whose current target it is, counted at the start of the tick.
const TARGET_CROWD_FREE_ATTACKERS := 3.0 # Melee attackers a target takes before it starts to look farther away.
const TARGET_CROWD_MULTIPLIER := 0.25 # Each further attacker adds this share of the distance.
const TARGET_OUTRUN_MULTIPLIER := 2.0 # k in distance × (1 + k × max(0, receding speed − own speed) / own speed).
# Stage 1a-archers (DESIGN.md 4.4, decision 15): fire distribution of shooters (attack_range > 0), the same for both
# sides, foot and mounted, in GDScript and C++. Aimers are shooters whose current target it is, counted at the start
# of the tick like attackers. A shooter expects one arrow to deal his damage × TARGET_VOLLEY_HIT_SHARE to the man he
# aims at, so hp / that many shooters are enough; every shooter beyond that (him included) makes the target look
# TARGET_OVERKILL_MULTIPLIER of its distance farther, and new shooters take his neighbours. An estimate, no new RNG.
const TARGET_VOLLEY_HIT_SHARE := 0.35
const TARGET_OVERKILL_MULTIPLIER := 0.5
# Front ranks: a shooter weighs every enemy up to this share farther, by a fixed amount drawn from his id and the
# enemy's id. Enemies about as close as the nearest one (the front ranks of a formation) then share the fire, while a
# rear rank stays farther than the front. The same shooter keeps the same preference, so the current target stays sticky.
const TARGET_FRONT_SPREAD := 0.15
# Leash in a charge, measured from the fighter's place in a formation fitted around his group's current position
# (mean of position minus formation offset). It holds only in a chase, while the target runs away from him at
# AI_CHARGE_CHASE_SPEED_SHARE of his speed or faster; in a standing fight the formation may deform freely.
# Beyond the soft leash he stops running after a target that is even farther away; beyond the hard leash, or after
# waiting out there too long, he walks back and chases again only when he is closer than the return distance.
# In contact he always fights.
const AI_CHARGE_CHASE_SPEED_SHARE := 0.5
const AI_CHARGE_FOOT_SOFT_LEASH := 180.0
const AI_CHARGE_FOOT_HARD_LEASH := 300.0
const AI_CHARGE_FOOT_RETURN_DISTANCE := 110.0
const AI_CHARGE_MOUNTED_SOFT_LEASH := 320.0
const AI_CHARGE_MOUNTED_HARD_LEASH := 520.0
const AI_CHARGE_MOUNTED_RETURN_DISTANCE := 200.0
const AI_CHARGE_CHASE_SECONDS := 3.0 # Longest wait beyond the soft leash without contact.
# Stage 1v (DESIGN.md 4.3, 4.4, decision 14): doctrines of troop types, the same for both sides. Group decisions
# (simulation/ai/squad_doctrine.gd, GDScript) run every AI_SQUAD_PERIOD_SECONDS per group, staggered by group number;
# fighter rules (ai_decision.gd, spatial_index.gd and movement_kernel.hpp) read their results every tick.
# Formation: an infantry group in a charge marches as a line ("formed") in the field. Its centre is the formation
# fitted to its fighters plus AI_FORMATION_LEAD ahead, its direction turns to the mean of its fighters' targets.
# Only the front ranks (slot offset less than AI_FORMATION_FRONT_DEPTH behind the front) step out to fight within the
# engage distance; the rear ranks keep their places and fight only in contact. Loose (the old charge: every man for
# himself, with the stage 1a leash) near a siege wall or with the targets across it, in a pursuit (most targets flee)
# and with fewer than AI_FORMATION_MIN_UNITS fighters. A switch holds at least AI_FORMATION_SWITCH_SECONDS.
const AI_FORMATION_LEAD := 45.0
const AI_FORMATION_TURN_RATE := 0.6 # Radians per second.
const AI_FORMATION_FRONT_DEPTH := 40.0 # Two front ranks: row depth is FORMATION_SPACING x FORMATION_ROW_DEPTH (26.7).
const AI_FORMATION_REAR_ENGAGE_BUFFER := 10.0 # A rear rank fights a target within reach plus this.
const AI_FORMATION_MIN_UNITS := 6
const AI_FORMATION_WALL_DISTANCE := 260.0 # From the wall line to the fitted formation centre.
const AI_FORMATION_PURSUIT_SHARE := 0.5
const AI_FORMATION_SWITCH_SECONDS := 1.0
const AI_FORMATION_AIM_RADIUS := 250.0 # The line turns to the cluster of its targets around the nearest one.
# A line in melee (AI_FORMATION_CONTACT_SHARE of its sampled men fighting within AI_FIELD_CONTACT_DISTANCE) for
# AI_FORMATION_MELEE_SECONDS while AI_FORMATION_WAITING_SHARE of them still wait in their ranks mingles: it goes loose,
# so the wings and rear ranks join the melee, and forms again when the contact is over.
const AI_FORMATION_CONTACT_SHARE := 0.1
const AI_FORMATION_MELEE_SECONDS := 6.0
const AI_FORMATION_WAITING_SHARE := 0.4
# Spearmen (anti_cavalry): a rider closing in on the spearman faster than AI_BRACE_APPROACH_SPEED within
# AI_BRACE_DISTANCE makes him stand and face the rider instead of running at him; in reach he strikes as usual.
const AI_BRACE_DISTANCE := 260.0
const AI_BRACE_APPROACH_SPEED := 40.0
# Screen: enemy riders closer than AI_SCREEN_THREAT_DISTANCE to the own archers and closing in, an own infantry group
# holding (not charging) within AI_SCREEN_RANGE of them: its spearmen within AI_SCREEN_RADIUS of the screen point form
# a line AI_SCREEN_OFFSET in front of the archers towards the riders, spread by AI_SCREEN_SPREAD of their slot offset.
const AI_SCREEN_THREAT_DISTANCE := 450.0
const AI_SCREEN_RANGE := 350.0
const AI_SCREEN_OFFSET := 70.0
const AI_SCREEN_SPREAD := 0.8
const AI_SCREEN_RADIUS := 400.0
# Foot archers keep their distance: their target, foot melee closing in faster than AI_ARCHER_FALLBACK_APPROACH_SPEED
# within AI_ARCHER_FALLBACK_DISTANCE, makes them step back AI_ARCHER_FALLBACK_STEP, but only towards their own infantry
# (its fitted formation centre within AI_ARCHER_FALLBACK_COVER_DISTANCE before and after the step), inside the field
# (AI_ARCHER_FALLBACK_EDGE) and on their side of a siege wall. Backing off is slower than infantry runs and they do not
# shoot while moving, so an endless kite does not pay: the infantry catches up and they fight in melee as before.
const AI_ARCHER_FALLBACK_DISTANCE := 160.0
const AI_ARCHER_FALLBACK_APPROACH_SPEED := 20.0
const AI_ARCHER_FALLBACK_STEP := 60.0
const AI_ARCHER_FALLBACK_SPEED_MULTIPLIER := 0.8
const AI_ARCHER_FALLBACK_COVER_DISTANCE := 450.0
const AI_ARCHER_FALLBACK_EDGE := 90.0
# Target priorities of the types, after the older multipliers and only raising the distance (search bounds hold).
# A shooter weighs a shielded enemy that is not a shooter (shield_block > 0, troop data "shb") this much farther, so
# archers and men without shields come first. A melee rider weighs a spearman (anti_cavalry, not fleeing) who faces him
# within CHARGE_FRONT_ARC this much farther, so cavalry looks for a flank or another target.
const TARGET_SHIELDED_MULTIPLIER := 1.3
const TARGET_SPEAR_FRONT_MULTIPLIER := 2.0
# Shock cavalry cycle (cavalry group in a charge): run-up and impact as before; when AI_CAVALRY_CONTACT_SHARE of its
# sampled melee riders have been in contact with foot melee for AI_CAVALRY_MELEE_SECONDS, the group rides to a rally
# point AI_CAVALRY_RALLY_DISTANCE beyond its centre, away from its targets (through them if it is past them), re-forms
# there (mean distance to the slots under AI_CAVALRY_REFORM_DISTANCE, or after AI_CAVALRY_RALLY_SECONDS) and charges
# again from the new run-up.
const AI_CAVALRY_CONTACT_SHARE := 0.3
const AI_CAVALRY_CONTACT_DISTANCE := 12.0 # Beyond reach: still in contact.
const AI_CAVALRY_MELEE_SECONDS := 2.5
const AI_CAVALRY_RALLY_DISTANCE := 320.0
const AI_CAVALRY_RALLY_EDGE := 120.0
const AI_CAVALRY_REFORM_DISTANCE := 70.0
const AI_CAVALRY_RALLY_SECONDS := 7.0
const AI_MODE_UNASSIGNED := ""
const AI_MODE_SLOT := "slot"
const AI_MODE_MELEE := "melee"
const AI_MODE_SHOOT := "shoot"
const AI_MODE_SHOOT_SLOT := "shootslot"
const AI_MODE_SKIRMISH := "skirm"
const AI_MODE_RANK := "rank" # Stage 1v: a formed fighter keeping his place in the line.
const AI_MODE_BRACE := "brace" # Stage 1v: a spearman standing against a rider.
const AI_MODE_FALLBACK := "fallback" # Stage 1v: an archer stepping back from infantry.
const AI_BACKING_SLOT_DISTANCE := 40.0
const AI_MOUNTED_SKIRMISH_TRIGGER := 1.15
const AI_ARCHER_MELEE_BUFFER := 24.0
const AI_ARCHER_SLOT_DISTANCE := 70.0
const AI_FOOT_ENGAGE_DISTANCE := 80.0
const AI_MOUNTED_ENGAGE_DISTANCE := 150.0
const AI_FOOT_LEASH_DISTANCE := 135.0
const AI_MOUNTED_LEASH_DISTANCE := 260.0
const AI_SLOT_FACE_DISTANCE := 8.0
const AI_SHOOT_APPROACH_RANGE := 0.9
const AI_SKIRMISH_CLOSE_RANGE := 0.55
const AI_SKIRMISH_APPROACH_RANGE := 0.9
const AI_SKIRMISH_BACK_OFFSET := 130.0
const AI_SKIRMISH_LATERAL_OFFSET := 60.0
const AI_SKIRMISH_ORBIT_OFFSET := 140.0
const AI_SKIRMISH_EDGE_MARGIN := 60.0
const AI_SKIRMISH_SPEED_MULTIPLIER := 0.8
const AI_INITIAL_ATTACK_COOLDOWN_MAX := 1.2
const AI_MELEE_WINDUP_SECONDS := 0.2
const AI_MELEE_COOLDOWN_MIN := 0.9
const AI_MELEE_COOLDOWN_MAX := 1.15
const AI_SHOOT_COOLDOWN_MIN := 0.85
const AI_SHOOT_COOLDOWN_MAX := 1.2
const AI_WIND_HIT_EXTRA_REACH := 10.0 # Browser: radius + radius + 16 + troop reach; melee_reach already includes 6.
const ARROW_DAMAGE_MIN := 0.85
const ARROW_DAMAGE_MAX := 1.15
const HERO_MAX_STAMINA := 100.0
const HERO_SPRINT_MIN_INPUT := 0.2
const HERO_SPRINT_MIN_STAMINA := 2.0
const HERO_FOOT_SPRINT_MULTIPLIER := 1.4
const HERO_HORSE_SPRINT_MULTIPLIER := 1.2
const HERO_SPRINT_STAMINA_COST := 26.0
const HERO_MOVE_STAMINA_RECOVERY := 9.0
const HERO_IDLE_STAMINA_RECOVERY := 18.0
const HERO_BLOCK_SPEED_MULTIPLIER := 0.55
const HERO_FOOT_STEERING_RATE := 12.0
const HERO_HORSE_STEERING_RATE := 1.7
const HERO_HORSE_IDLE_STEERING_RATE := 0.9
const HERO_ATTACK_WINDUP := 0.13
const HERO_RANGED_WINDUP := 0.2
const HERO_SHOT_CONE := 0.2
const HERO_SHOT_MIN_DISTANCE := 14.0
const HERO_SHOT_ANGLE_SCORE := 420.0
const HERO_SHOT_DISTANCE_SCORE := 0.12
const HERO_SHOT_MISS_DISTANCE_FRACTION := 0.7
const HERO_ATTACK_ARC := 1.0
const HERO_ATTACK_DISTANCE := 30.0
const HERO_WEAPON_BASE_REACH := 9.0
const HERO_MOUNTED_ATTACK_REACH := 8.0
const HERO_MAX_HITS := 3
const HERO_FOLLOWUP_DAMAGE := 0.7
const HERO_DEFAULT_KNOCKBACK := 1.0
const HERO_KNOCKBACK_DISTANCE := 5.0
const HERO_BLOCK_HOLD_CHANCE := 0.75
const HERO_MELEE_DAMAGE_MIN := 0.85
const HERO_MELEE_DAMAGE_MAX := 1.2
const HERO_UNARMED_PIERCE := 0.1
const HERO_SWING_SECONDS := 0.26
const HERO_SWING_SPEED_MULTIPLIER := 0.7
const HERO_ACTIVE_BLOCK_BONUS := 0.13
const HERO_IDLE_BLOCK_MULTIPLIER := 0.25
const HERO_MAX_BLOCK_CHANCE := 0.97
const MORALE_TICK_SECONDS := 1.0
const MORALE_OPPONENT_FLOOR := 0.5
const MORALE_BAD_ODDS := 0.5
const MORALE_VERY_BAD_ODDS := 0.3
const MORALE_BAD_ODDS_LOSS := 2.5
const MORALE_VERY_BAD_ODDS_LOSS := 3.5
const MORALE_STRONG_ODDS := 1.5
const MORALE_EVEN_ODDS := 0.8
const MORALE_STRONG_RECOVERY := 4.0
const MORALE_EVEN_RECOVERY := 2.5
const MORALE_WEAK_RECOVERY := 1.0
const MORALE_FORCE_FLEE_START_SHARE := 0.2
const MORALE_FORCE_FLEE_ENEMY_SHARE := 0.5
const MORALE_FORCE_FLEE_MIN_START := 4
# Stage 1b morale (DESIGN.md 4.5). The same rules for both sides and for player orders; fighters only, the hero,
# companions and the undead (morale_immune) keep their old ways. Steps of a fighter: steady -> wavering (below
# MORALE_WAVER_SHARE of his base morale; steady again from MORALE_STEADY_SHARE) -> fleeing (morale at 0 or the side
# collapses) -> rallied (wavering, at most MORALE_RALLY_LIMIT times). Before stage 1b "wavering" was only a notice
# below 22 (tier 1: base 86, so 0.26 of it).
const MORALE_WAVER_SHARE := 0.35
const MORALE_STEADY_SHARE := 0.5
# A wavering fighter strikes and blocks worse, advances slower (melee and shooting approach) and does not charge a
# far enemy: in a loose charge he fights only what comes within the hold engage distance and stands his ground.
const MORALE_WAVER_DAMAGE_MULTIPLIER := 0.85
const MORALE_WAVER_BLOCK_MULTIPLIER := 0.8
const MORALE_WAVER_SPEED_MULTIPLIER := 0.85
# A hit from the flank or the rear of the target's formation (the group's facing while it keeps a formation, the
# fighter's own facing in a loose charge; sectors as in the field assessment) costs more morale than one from the front.
const MORALE_FLANK_HIT_MULTIPLIER := 1.5
const MORALE_REAR_HIT_MULTIPLIER := 2.5
# A cavalry charge shakes its victim, except a spearman meeting it face on; times the hit direction multiplier.
const MORALE_CHARGE_SHOCK := 6.0
# Threat from the field assessment (DESIGN.md 4.1; terrain joins it there, TERRAIN.md 7): enemy strength near the
# group by sector against the group's own strength. Pressure: flank threat, plus the rear threat
# MORALE_THREAT_REAR_WEIGHT times, plus MORALE_THREAT_FRONT_WEIGHT of the front threat beyond MORALE_THREAT_FRONT_FREE
# (an overwhelming enemy ahead); an even fight in front costs nothing. Above MORALE_THREAT_FREE every fighter of the
# group loses MORALE_THREAT_LOSS per second per unit of pressure, up to MORALE_THREAT_CAP units.
const MORALE_THREAT_FRONT_FREE := 2.0
const MORALE_THREAT_FRONT_WEIGHT := 0.5
const MORALE_THREAT_REAR_WEIGHT := 1.6
const MORALE_THREAT_FREE := 0.3
const MORALE_THREAT_CAP := 1.5
const MORALE_THREAT_LOSS := 6.0
const MORALE_THREAT_STRENGTH_FLOOR := 1.0 # Strength below this counts as this much (a group of a few wounded men).
# Panic: a fighter who starts to flee costs friends within MORALE_PANIC_RADIUS MORALE_PANIC_LOSS each (at most
# MORALE_PANIC_CAP per check); every fighter of a group loses MORALE_PANIC_SHARE_LOSS per second times its fleeing share.
const MORALE_PANIC_RADIUS := 110.0
const MORALE_PANIC_LOSS := 4.0
const MORALE_PANIC_CAP := 12.0
const MORALE_PANIC_SHARE_LOSS := 6.0
# Rally: a fleeing fighter with no ready enemy within MORALE_PURSUIT_RADIUS recovers MORALE_ROUT_RECOVERY per second,
# MORALE_RALLY_LEADER_BONUS more with an own leader or the hero within MORALE_RALLY_LEADER_RADIUS; at
# MORALE_RALLY_SHARE of his base morale he turns back, wavering, unless the side has collapsed or he is within
# MORALE_RALLY_EDGE of the side edges of the field. Pursued, he does not recover. A flight starts at zero morale or,
# after a heavy blow, down to minus MORALE_RALLY_SHARE of the base.
const MORALE_PURSUIT_RADIUS := 150.0
const MORALE_ROUT_RECOVERY := 6.0
const MORALE_RALLY_LEADER_BONUS := 4.0
const MORALE_RALLY_LEADER_RADIUS := 260.0
const MORALE_RALLY_SHARE := 0.3
const MORALE_RALLY_EDGE := 120.0
const MORALE_RALLY_LIMIT := 1
# Group step for the debug overlay and future commanders: routed from this fleeing share, wavering from this
# share of wavering and fleeing fighters.
const MORALE_GROUP_ROUTED_SHARE := 0.5
const MORALE_GROUP_WAVERING_SHARE := 0.3
const MORALE_GROUP_STEADY := 0
const MORALE_GROUP_WAVERING := 1
const MORALE_GROUP_ROUTED := 2
