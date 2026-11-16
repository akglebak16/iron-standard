extends RefCounted

const TROOP_GOLD_PER_TIER := 9
const TROOP_BASE_GOLD := 6
const BATTLE_GOLD_MIN := 0.7
const BATTLE_GOLD_MAX := 1.1
const LOW_LOOT_GOLD_MULTIPLIER := 0.2
const CAMP_GOLD := 120
const DEFEAT_GOLD_SHARE := 0.25
const OPPONENT_DEFEAT_COOLDOWN := 10
const PARTY_IDLE := "idle"
const SETTLEMENT_TOWN := "town"
const SETTLEMENT_VILLAGE := "village"
const LORD_KIND := "lord"
const PLAYER_FACTION := "player"
const UNDEAD_FACTION := "undead"
const BANDIT_FACTION := "bandit"
const SOLO_ARMY_SCALE := 2
const SPECIAL_ARMY_SCALE := 1.25
const CAPTURE_GARRISON_COUNT := 4
const CAPTURE_GARRISON_QUALITY := 0.3
const SIEGE_TOWN_GOLD := 350
const SETTLEMENT_CASTLE := "castle"
# src/05i_siege.js sgDefCfg: wall supplies of the defenders.
const SIEGE_SUPPLIES_CASTLE := {"stones": 14, "oil": 3}
const SIEGE_SUPPLIES_OTHER := {"stones": 10, "oil": 2}
const SIEGE_OTHER_GOLD := 180
const INITIAL_GARRISONS := {
	"town": {"counts": Vector2i(85, 120), "quality": 0.62},
	"castle": {"counts": Vector2i(130, 175), "quality": 0.75},
}
const CAPTURE_RELATION_LOSS := 15
const CAPTURE_RUIN_HOURS := 24 * 10
const LIBERATION_RELATION_REWARD := 8
const TOWN_RECOVERY_OFFSET := Vector2(10, 34)
const RECOVERY_GOLD_THRESHOLD := 60
const RECOVERY_GOLD := 80
const CAMP_RESPAWN_HOURS := 24 * 9
const RELATION_MAX := 100
const RELATION_MIN := -100
const HOSTILE_BELOW := -20
const QUEST_RELATION_REWARD := 6
const CULTURE_VICTORY_REWARD := 1
const BARROW_RELATION_REWARD := 5
const UNDEAD_ARMY_RELATION_REWARD := 3
const UNDEAD_OTHER_RELATION_REWARD := 1
const CAMP_QUEST := "camp"
const PURGE_QUEST := "purge"
const HERO_MIN_RECOVERY_HEALTH := 0.22
const COMPANION_MIN_RECOVERY_HEALTH := 0.1
const COMPANION_BATTLE_XP_SHARE := 0.3
const COMPANION_KILL_XP := 12
const COMPANION_BASE_XP := 8
const VICTORY_BASE_XP := 12
const HERO_KILL_XP := 4
const DEFEAT_XP_SHARE := 0.5
const BATTLE_PROVISIONS := Vector2i(0, 8)
const CARAVAN_PROVISIONS := Vector2i(10, 30)
const GRAIN_ID := "grain"
const PORTIONS_PER_GRAIN := 6

const LOOT_MAX_TIER := 3
const LOOT_FACTION_PREFERENCE := 2.2
const LOOT_ROLLS_PER_ENEMY := 0.12
const LOOT_MAX_ROLLS := 6
const LOOT_GOODS_CHANCE := 0.3
const LOOT_GOODS_VALUE := Vector2i(120, 300)
const LOOT_MAX_GOODS := 14
const CARGO_BASE := 60
const CARGO_PER_TROOP := 3
const CARGO_PER_STRENGTH := 6
const CARGO_HORSE_BONUS := 30
const CARGO_WEIGHT_PRECISION := 10.0
const CARGO_WEIGHT_EPSILON := 0.000001

# Threat map of the campaign AI (docs/modules/ai/DESIGN.md §5.1, ADR-023). Derived from parties, never saved.
const THREAT_CELL_SIZE := 100.0  # map units per cell: 52 × 34 cells over Europe
const THREAT_RADIUS := 300.0     # strength fades linearly to zero at this distance
const THREAT_FRONT_MIN := 20.0   # both sides need at least this influence in a front cell
const THREAT_FRONT_BALANCE := 0.5 # |a - b| <= share of (a + b): neither side more than 3:1
const THREAT_HAVEN_COST := 0.25  # strength per map unit of distance to the nearest own settlement

# Party goals of the campaign AI (docs/modules/ai/DESIGN.md §5.2, stage 2a, ADR-023). Scores are 0..1 products of
# normalised factors (Dave Mark), times the weight of the goal for the kind of party. Distances are map units, times hours.
const GOAL_THINK_HOURS := Vector2(0.8, 1.6)  # a party re-evaluates its goal this often (random within the range)
const GOAL_WAIT_PER_THINK := 1.2   # hours of lingering at a goal spent by one evaluation
const GOAL_HOLD_HOURS := 2.0       # a new goal is kept at least this long ...
const GOAL_SWITCH_MARGIN := 0.25   # ... and replaced only by a goal scoring this share better
const GOAL_URGENT_SCORE := 0.75    # a goal scoring this much ignores the hold time (still needs the margin)
const GOAL_PICK_BAND := 0.9        # a new goal is drawn among candidates scoring at least this share of the best
const GOAL_DISTANCE_FALLOFF := 0.7 # the distance factor drops from 1 to 1 - falloff at the edge of the range
const GOAL_CROWD_PENALTY := 0.6    # factor 1 / (1 + penalty × own parties already on the same goal)
const GOAL_SIGHT_RADIUS := 260.0   # parties a party sees (hunting radius of the browser AI)
const GOAL_SCOUT_RADIUS := 450.0   # beyond this the threat at a foreign place is unknown (§5.1 visibility)
const GOAL_UNKNOWN_RISK := 0.15    # risk assumed for a foreign place out of scouting range
const GOAL_RISK_SPAN := 1.0        # enemy strength (in own strengths) at a target that makes the risk factor zero
const GOAL_ARMY_HUNT_RADIUS := 90.0 # parties in a faction campaign only attack enemies this close
# Hunting: the target must be weaker than `hunt_ratio` of own strength (with allies nearby).
const GOAL_HUNT_EDGE_FLOOR := 0.35 # advantage factor of a target just below the ratio; 1 for a target of no strength
const GOAL_FASTER_PENALTY := 2.0   # catch-up factor 1 - penalty × (target speed - own) / own
const GOAL_FASTER_CHASE_HOURS := 3.0 # a faster target is given up after this long a chase
const GOAL_CHASE_REPATH_HOURS := 0.7 # chasers and escorts re-plan the route to a moving party this often
const GOAL_PLAYER_SIGHT := 230.0     # the player's party is noticed this close
const GOAL_PLAYER_DROP := 300.0      # a chase after the player ends beyond this distance
const GOAL_PLAYER_STRENGTH_BONUS := 6.0 # the hero counts as this much strength
const GOAL_PLAYER_HUNT_RATIO := 0.95
const GOAL_PLAYER_FLEE_RATIO := 1.25
const GOAL_PLAYER_FLEE_SIGHT := 180.0
const GOAL_PREY_WORTH := {"lord": 1.0, "player": 1.0, "vassal": 0.9, "cvass": 0.9, "caravan": 0.85, "dead": 0.8, "raid": 0.75, "bandit": 0.7}
const GOAL_PREY_WORTH_OTHER := 0.7
# Fleeing: pressure 1 = an enemy `flee_ratio` times stronger than us is in sight.
const GOAL_FLEE_FULL_PRESSURE := 1.5 # pressure at which fleeing scores 1 (0.5 at pressure 1)
const GOAL_FLEE_MAP_SHARE := 0.85    # enemy strength felt on the threat map counts this much towards the pressure
const GOAL_FLEE_HAVEN_RANGE := 700.0 # own settlements this close are havens
const GOAL_FLEE_THREAT_COST := 1.5   # haven cost per own strength of enemies at it and half-way (plus distance / range)
const GOAL_FLEE_SAFER := 0.8         # a haven must feel less than this share of the enemy strength felt here
const GOAL_FLEE_SAFE_RADIUS := 300.0 # without a haven: safest threat-map cell this close
const GOAL_FLEE_FALLBACK := 220.0    # last resort: this far straight away from the enemy (the browser AI)
const GOAL_FLEE_RESIDUAL := 0.5      # score of a flight under way once the enemy is out of sight, until the hold ends
const GOAL_MAP_MARGIN := 60.0        # points picked by the AI stay this far from the map edge
# Patrol, defence, raids, rest and escort.
const GOAL_ALARM_HOURS := 24         # a settlement remembers enemies seen around it this long (saved as s.alarm)
const GOAL_ALARM_MIN_THREAT := 80.0  # enemy strength on the threat map that raises the alarm
const GOAL_PATROL_RANGE := 900.0
const GOAL_PATROL_BASE := 0.35       # patrol factor of a quiet settlement; 1 right after an alarm
const GOAL_PATROL_OFFSET := Vector2(30.0, 90.0) # patrol point around the settlement
const GOAL_PATROL_WAIT := Vector2i(2, 6)
const GOAL_DEFEND_RANGE := 900.0
const GOAL_DEFEND_THREAT_SHARE := 0.5 # enemies around an own settlement worth defending: this share of own strength
const GOAL_DEFEND_OFFSET := 40.0
const GOAL_DEFEND_WAIT := 4
const GOAL_RAID_RANGE := 600.0
const GOAL_RUIN_RANGE := 1100.0      # own ruins held by the dead are retaken from this far
const GOAL_RAID_VALUE := {"village": 0.7, "player": 0.8, "ruin": 1.0}
const GOAL_RAID_FULL_SHARE := Vector2(0.4, 0.8) # raids need this share of a full army (none at x, full at y)
const GOAL_RAID_BURN_HOURS := 24     # a raided village gives no recruits this long (s.burnt, like the dead)
const GOAL_RAID_GOLD := 40
const GOAL_REST_RANGE := 1200.0
const GOAL_REST_BASE := 0.3          # rest factor of a full army; 1 when the army misses GOAL_REST_NEED.y of its men
const GOAL_REST_NEED := Vector2(0.1, 0.6)
const GOAL_REST_VILLAGE := 0.7       # lords rest in villages less willingly than in towns and castles
const GOAL_LORD_FULL := 165.0        # full army of a lord before the MK multiplier
const GOAL_VASSAL_FULL := 70.0       # full retinue of a faction vassal before MK
const GOAL_PARTY_FULL := 34.0        # refill target of other parties resting inside (before MK)
const GOAL_ESCORT_RANGE := 500.0
const GOAL_ESCORT_DANGER := Vector2(0.5, 2.0) # enemy strength around a caravan, in caravan strengths: none at x, full at y
const GOAL_ESCORT_KEEP := 40.0
const GOAL_FOLLOW_KEEP := 80.0       # a vassal rides to its lord when farther than this
const GOAL_FOLLOW_OFFSET := 45.0
const GOAL_ROAM_RANGE := Vector2(80.0, 340.0) # bandits roam this far around their camp
const GOAL_ROAM_TRIES := 4           # random roam points tried until one has a route
# Goal weights by kind of party (data, not code). Missing goals weigh 0. hunt_ratio / flee_ratio are strength
# thresholds relative to own strength, sight / flee_sight the radii. outlaws_only: only bandits and the dead are feared;
# map_pressure false: only an enemy in sight makes the party flee (caravans would otherwise run from every band around).
# Stage 3 multiplies these by traits and difficulty.
const GOAL_PROFILES := {
	"lord": {"hunt": 1.0, "flee": 1.0, "defend": 0.9, "patrol": 0.45, "raid": 0.5, "rest": 0.5,
		"hunt_ratio": 0.75, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0},
	"vassal": {"hunt": 1.0, "flee": 1.0, "defend": 0.6, "patrol": 0.45, "escort": 0.7, "follow": 0.45, "rest": 0.4,
		"hunt_ratio": 0.75, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0},
	"bandit": {"hunt": 1.0, "flee": 1.0, "roam": 0.4,
		"hunt_ratio": 0.9, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0},
	"caravan": {"flee": 1.0, "hunt_ratio": 0.75, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0, "outlaws_only": true,
		"map_pressure": false},
	"dead": {"hunt": 1.0, "hunt_ratio": 0.75, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0},
	"raid": {"hunt": 1.0, "hunt_ratio": 0.75, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0},
}
const GOAL_PROFILE_OTHER := {"hunt": 1.0, "flee": 1.0, "hunt_ratio": 0.75, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0}
# The player's retinues (world_vassals.gd MODES): each order is a set of weights over the same goals.
# leash: targets farther than this from the fief are ignored. skip_busy: parties already in a fight are not hunted.
const GOAL_RETINUE_MODES := {
	"guard": {"hunt": 1.0, "flee": 1.0, "guard": 0.4, "hunt_ratio": 0.8, "flee_ratio": 1.2, "sight": 150.0,
		"flee_sight": 150.0, "leash": 230.0, "skip_busy": true},
	"patrol": {"hunt": 1.0, "flee": 1.0, "patrol": 0.4, "hunt_ratio": 0.8, "flee_ratio": 1.2, "sight": 260.0,
		"flee_sight": 150.0, "skip_busy": true},
	"follow": {"hunt": 1.0, "flee": 1.0, "follow": 0.6, "hunt_ratio": 0.8, "flee_ratio": 1.2, "sight": 260.0,
		"flee_sight": 150.0, "skip_busy": true},
}
const GOAL_RETINUE_GUARD_RANGE := Vector2(30.0, 90.0) # a guarding retinue wanders this far around its fief ...
const GOAL_RETINUE_GUARD_FAR := 110.0  # ... and walks back when farther than this
const GOAL_RETINUE_GUARD_WANDER := 0.25 # chance to wander at an evaluation
const GOAL_RETINUE_PATROL_RANGE := Vector2(80.0, 300.0) # a patrolling retinue rides this far around its fief
const GOAL_RETINUE_FOLLOW_KEEP := 70.0 # a following retinue catches up with the player beyond this
