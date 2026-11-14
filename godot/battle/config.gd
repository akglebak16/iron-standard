extends RefCounted
## Balance values copied from the browser battle. Change them here, then run Godot tests.

const ARENA_SIZE := Vector2(2600, 1700)
const FRONT_X := 640.0
const CENTER_Y := 850.0
const ARCHER_REAR_OFFSET := 105.0
const CAVALRY_REAR_OFFSET := 20.0
const CAVALRY_FLANK_OFFSET := 380.0
const GROUP_KINDS := 3
const ALL_GROUPS := 3
const GROUP_INFANTRY := 0
const GROUP_ARCHERS := 1
const GROUP_CAVALRY := 2
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
const ALLY_DEATH_MORALE := 1.6
const ALLY_DEATH_MORALE_PER_TIER := 0.5
const ENEMY_DEATH_MORALE_BONUS := 3.0
const SOLO_UNIT_CAP := 300
const UNDEAD_UNIT_CAP := 600
const SPAWN_JITTER := 30.0
const SPEED_RANDOM_MIN := 0.94
const SPEED_RANDOM_MAX := 1.06

static func unit_cap(faction: String) -> int:
	return UNDEAD_UNIT_CAP if faction == "undead" else SOLO_UNIT_CAP
