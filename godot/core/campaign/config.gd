extends RefCounted

const TROOP_GOLD_PER_TIER := 9
const TROOP_BASE_GOLD := 6
const BATTLE_GOLD_MIN := 0.7
const BATTLE_GOLD_MAX := 1.1
const LOW_LOOT_GOLD_MULTIPLIER := 0.2
const CAMP_GOLD := 120
const DEFEAT_GOLD_SHARE := 0.25
const OPPONENT_DEFEAT_COOLDOWN := 10
const ALLY_WIN_RELATION := 3.0 # relation gained with a faction whose parties won a battle at the player's side
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
const GOAL_MAP_MARGIN := 150.0       # random points and fallbacks of the AI stay this far from the map edge (was 60)
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
# Escort (#315, DESIGN.md §5.7): lords and faction vassals escort own caravans; the danger is read at the caravan and ahead on
# its route, at points this far apart, up to GOAL_ESCORT_AHEAD (one threat radius: about 18 hours of a caravan's way).
const GOAL_ESCORT_AHEAD := 300.0
const GOAL_ESCORT_AHEAD_STEP := 100.0 # one threat-map cell
const GOAL_ESCORT_HOME := 900.0       # caravans are escorted through own lands: an own settlement this close (the patrol range)
const GOAL_FOLLOW_KEEP := 80.0       # a vassal rides to its lord when farther than this
const GOAL_FOLLOW_OFFSET := 45.0
const GOAL_ROAM_RANGE := Vector2(80.0, 340.0) # bandits roam this far around their camp
const GOAL_ROAM_TRIES := 4           # random roam points tried until one has a route
# Help in battle (DESIGN.md §5.7, #312): a lord or vassal goes to a running fight of its faction (world_skirmish) that it
# sees and can turn. Which side it joins is still decided by world_skirmish.hour_tick once it is close.
const GOAL_ASSIST_RANGE := 400.0      # fights this close are seen (between the sight 260 and the scouting range 450)
const GOAL_ASSIST_NEED := Vector2(0.5, 1.2) # enemy / own side strength: help is least needed at x, fully at y ...
const GOAL_ASSIST_NEED_FLOOR := 0.3   # ... and a side that wins anyway still gets help this much (a sooner end)
const GOAL_ASSIST_ODDS := Vector2(0.8, 1.4) # (own side + the party) / enemy: hopeless at x (no goal), sure at y
const GOAL_ASSIST_IN_TIME := Vector2(0.75, 1.25) # hours on the way / hours the fight has left: in time at x, too late at y
# Calls for help (#313): a lord or vassal chased by a stronger enemy, or fleeing, calls; own lords and vassals answer with the
# factors of GOAL_ASSIST_* and the weight of "assist". The fleeing party may run to a strong own party in sight. Since #315
# a caravan that an outlaw hunts or that flees calls and runs to own parties the same way.
const GOAL_FLEE_FRIEND_MIN := 90.0    # an own party closer than this is already at hand (world_skirmish.hour_tick joins at 90)
const GOAL_FLEE_FRIEND_ODDS := 1.0    # it is a haven when together they are at least this share of the enemy's strength
# Goal weights by kind of party (data, not code). Missing goals weigh 0. hunt_ratio / flee_ratio are strength
# thresholds relative to own strength, sight / flee_sight the radii. outlaws_only: only bandits and the dead are feared;
# map_pressure false: only an enemy in sight makes the party flee (caravans would otherwise run from every band around).
# Stage 3 multiplies these by traits and difficulty.
const GOAL_PROFILES := {
	"lord": {"hunt": 1.0, "flee": 1.0, "defend": 0.9, "patrol": 0.45, "raid": 0.5, "rest": 0.5, "escort": 0.7, "assist": 1.0,
		"hunt_ratio": 0.75, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0},
	"vassal": {"hunt": 1.0, "flee": 1.0, "defend": 0.6, "patrol": 0.45, "escort": 0.7, "follow": 0.45, "rest": 0.4, "assist": 0.9,
		"hunt_ratio": 0.75, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0},
	"bandit": {"hunt": 1.0, "flee": 1.0, "roam": 0.4,
		"hunt_ratio": 0.9, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0},
	"caravan": {"flee": 1.0, "hunt_ratio": 0.75, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0, "outlaws_only": true,
		"map_pressure": false},
	# the dead (stage 2c): armies gather and storm with their wave, raids burn villages ahead of it; neither flees
	"dead": {"hunt": 0.8, "muster": 0.9, "assault": 1.0, "roam": 0.2,
		"hunt_ratio": 0.75, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0},
	"raid": {"hunt": 1.0, "raid": 0.8, "roam": 0.25, "hunt_ratio": 0.75, "flee_ratio": 1.2, "sight": 260.0, "flee_sight": 190.0},
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

# Operations of a faction (docs/modules/ai/DESIGN.md §5.3, stage 2b): an offensive campaign led by a marshal and a
# defensive one that relieves an own besieged settlement; at most one of each kind per faction. world_wars.gd carries
# them out every 2 hours, campaign_ops.gd decides. Strengths are PartyRules.strength, distances map units, times hours.
const OP_VALUE := {"town": 90.0, "castle": 70.0, "village": 12.0} # worth of a settlement (as in world_wars.power)
const OP_HOME_THREAT := 250.0        # enemy strength on the threat map at an own town or castle that calls for a defender
const OP_READY_SHARE := 0.5         # a lord joins a campaign with at least this share of a full army (GOAL_LORD_FULL, GOAL_VASSAL_FULL)
const OP_KEEP_BASE := 1              # lords kept home by a faction at war even when its borders are quiet ...
const OP_KEEP_MIN_LORDS := 3         # ... once it has at least this many lords free for a campaign
const OP_KEEP_MAX_SHARE := 0.5       # never more than this share of the free lords stays home
const OP_MUSTER_RADIUS := 150.0      # a lord within this of the marshal has joined the host
const OP_MUSTER_SHARE := 0.7         # the march starts when this share of the host joined the marshal at the rally ...
const OP_MUSTER_HOURS := 40          # ... or after this long
const OP_FOLLOW_KEEP := 60.0         # followers ride after the marshal when farther than this
const OP_MARCH_TOGETHER := 0.5       # the marshal waits while fewer than this share of followers keep up with him
const OP_SIEGE_REACH := 80.0         # the marshal starts the siege this close to the target ...
const OP_SIEGE_GATHER := 90.0        # ... when half of the host is this close to it (besiegers count within 100)
const OP_SIEGE_APPROACH := 200.0     # with the marshal this close to the target the followers ride to the walls
const OP_MARCH_HOURS := 70           # a march that drags on this long starts the siege anyway
const OP_RETREAT_SHARE := 0.45       # a campaign ends when the host falls below this share of its strength at the muster
const OP_HOME_WEIGHT := 1.25         # an own besieged settlement worth more than the target × 1/weight recalls the host ...
const OP_RECALL_RANGE := 1300.0      # ... when the marshal is this close to it
const OP_RELIEF_DELAY := 8           # hours of a siege before the defenders send relief
const OP_RELIEF_RANGE := 900.0       # lords this close to an own besieged settlement may relieve it (was 480)
const OP_RELIEF_FAR_RANGE := 1300.0  # when the lords within OP_RELIEF_RANGE cannot outmatch the besiegers, those this close come too
const OP_RELIEF_MAX_LORDS := 6       # largest relief host (was 3)
const OP_RELIEF_MARGIN := 1.2        # lords are added until relief and 0.3 of the garrison are this much stronger than the besiegers
const OP_RELIEF_MIN_RATIO := 0.6     # relief weaker than this share of the besiegers is not sent
const OP_RELIEF_MIN_TROOPS := 36     # a relieving lord needs this many men (18 × MK, as before)
const OP_RELIEF_WAIT_HOURS := 70     # relief that has not gathered by the walls this long goes home (was 40)
const OP_RELIEF_TRIES := 2           # relief attempts per siege, at least a day apart
const OP_RUIN_PRIORITY := 300.0      # own ruins held by the dead are campaign targets; their score (distance + defence) drops by this
const OP_RUIN_DEFENCE := 1.5         # the dead hold their ruins this many times their garrison's strength (WorldUndead.noble_retake)

# Director of the undead invasion (docs/modules/ai/DESIGN.md §5.5, stage 2c). Every barrow sends one wave: it picks a
# living town or castle, gathers its armies at a rally point short of it and storms it with all of them at once; raids
# burn the villages ahead. undead_director.gd decides, world_undead.gd carries it out every hour, the armies and raids
# follow it through their goals (party_goals.gd). Strengths are PartyRules.strength, distances map units, times hours.
const UNDEAD_TARGET_WORTH := {"town": 1.0, "castle": 0.8} # what a town or castle of the living is worth to the dead
const UNDEAD_TARGET_RANGE := 1400.0  # distance factor of a target falls from 1 to 1 - falloff at this distance from the wave
const UNDEAD_DISTANCE_FALLOFF := 0.85
const UNDEAD_STORM_DEFENCE := 1.3    # walls: a storm meets the garrison and the lords inside this many times (WorldUndead.storm)
const UNDEAD_FIELD_SHARE := 0.5      # living armies around a target (threat map) count this much towards its defence
const UNDEAD_WEAK_RATIO := Vector2(0.4, 2.0) # defence in strengths of the wave: weakness factor 1 at x, UNDEAD_WEAK_FLOOR at y
const UNDEAD_WEAK_FLOOR := 0.1
const UNDEAD_VILLAGE_RADIUS := 300.0 # living villages this close to a target are prey for the raids ahead of the wave ...
const UNDEAD_VILLAGE_BONUS := 0.05   # ... each adds this share to the target's score
const UNDEAD_VILLAGE_BONUS_MAX := 0.3
const UNDEAD_RETARGET_HOURS := 24    # a gathering wave looks for a better target this often ...
const UNDEAD_SWITCH_MARGIN := 0.3    # ... and switches only to one scoring this share better
const UNDEAD_RALLY_DISTANCE := 260.0 # the rally point lies this far short of the target, on the side of the wave
const UNDEAD_RALLY_RADIUS := 170.0   # an army this close to the rally point (or by the target's walls) has gathered
const UNDEAD_MIN_GATHER_HOURS := 12  # a wave gathers at least this long after it picked its target: the living hear of it
const UNDEAD_ATTACK_MARGIN := 1.3    # the wave attacks when its gathered strength is this many times the storm defence ...
const UNDEAD_GATHER_HOURS := 72      # ... or all its armies have gathered and waited this long with at least ...
const UNDEAD_ATTACK_MIN := 0.8       # ... this share of the storm defence; after twice as long it attacks with what it has
const UNDEAD_FALLBACK_SHARE := 0.6   # an attacking wave that fell below this share of the storm defence gathers again
const UNDEAD_STORM_RADIUS := 110.0   # armies this close to the target storm it together ...
const UNDEAD_STORM_SHARE := 0.75     # ... once this share of the attacking strength is at the walls ...
const UNDEAD_STORM_WAIT := 12        # ... or the first army has stood there this long
const UNDEAD_WALL_WAIT := 2.0        # hours an army at the walls waits between checks of the director
const UNDEAD_MUSTER_SPREAD := Vector2(10.0, 70.0) # gathering armies stand this far around the rally point
const UNDEAD_MUSTER_WAIT := 4        # hours an army at the rally point lingers before it looks around again
const UNDEAD_RAVAGE_RANGE := 900.0   # raids burn villages this far from the front of their wave (its target) ...
const UNDEAD_RAVAGE_REACH := 450.0   # ... and this far from themselves (farther ones it would not reach before the front moves)
const UNDEAD_ROAM_RANGE := Vector2(60.0, 250.0) # with nothing to do the dead roam this far around their front or barrow
const UNDEAD_UNKNOWN_GARRISON := 300.0 # strength assumed for a town or castle whose garrison was never raised yet

# Faction strategist (docs/modules/ai/DESIGN.md §5.4, stage 2d): war and peace by gain and war weariness.
# faction_strategist.gd decides, world_wars.gd keeps the weariness and the truces and rolls the remaining noise.
const STRAT_START_WARS := 2         # wars a state starts the game with at most (from Rules.WAR in table order); 0 = the whole table
const STRAT_WAR_RATE := 0.1         # daily chance of a declaration at full will to war (a small noise on top of the gain)
const STRAT_POWER_EDGE := Vector2(0.9, 1.8) # own power / neighbour's: no will to war at x, full at y (the neighbour is weaker)
const STRAT_PRIZE_REACH := 800.0    # enemy towns and castles this close to an own town or castle are within reach ...
const STRAT_PRIZE_FULL := 2.0       # ... and this much of their worth (town 1, castle 0.7) is a full prize
const STRAT_PRIZE_WORTH := {"town": 1.0, "castle": 0.7}
const STRAT_SECOND_FRONT := 0.2     # will to a war while already at war with someone else; none at STRAT_MAX_WARS wars
const STRAT_MAX_WARS := 2
const STRAT_FOE_MAX_WARS := 2       # a neighbour already in this many wars is left alone
const STRAT_WEARY_WAR := 0.4        # a state this weary starts no war (its will falls to zero on the way)
const STRAT_WEARY_DAY := 0.004      # weariness a state gains each day of each of its wars ...
const STRAT_WEARY_LORD := 0.015     # ... each lord it loses while at war (a vassal counts STRAT_WEARY_VASSAL) ...
const STRAT_WEARY_VASSAL := 0.005
const STRAT_WEARY_LOSS := {"town": 0.12, "castle": 0.09} # ... each town or castle an enemy state takes from it
const STRAT_WEARY_REST := 0.015     # weariness a state at peace sheds each day
const STRAT_WEARY_MAX := 1.0
const STRAT_STRAIN := 0.3           # will to peace from thin armies: this × the missing share of the lords' full armies
const STRAT_MIN_WAR_DAYS := 20      # no peace in the first days of a war
const STRAT_PEACE_AT := 0.65        # peace once both sides want it at least this much ...
const STRAT_PEACE_CHANCE := Vector2(0.05, 0.5) # ... with this daily chance on the threshold, rising to y ...
const STRAT_PEACE_SPAN := 0.5       # ... when the lesser will is this much above it
const STRAT_LOSING := 0.25          # will to peace per town (worth) the enemy took more than it lost in this war, ...
const STRAT_LOSING_MAX := 0.6
const STRAT_WAR_AIM := 2.0          # ... a side that took this much more than it lost has what it wanted ...
                                    #     (part of it: that part of STRAT_CONTENT)
const STRAT_CONTENT := 0.45         # ... and wants peace this much more
const STRAT_WEAKER := 0.3           # will to peace per unit of the enemy's power over own beyond STRAT_WEAKER_FROM (up to STRAT_WEAKER)
const STRAT_WEAKER_FROM := 1.2
const STRAT_FRONTS := 0.1           # will to peace per war beyond the first
const STRAT_TRUCE_DAYS := 30        # after a peace the same pair starts no war for this many days
