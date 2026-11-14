extends RefCounted
## Shared codes for facts emitted by the simulation and read by presentation.

enum Kind { HIT, BLOCK, CHARGE, DOWN, LAST_STAND, SHOT, SWING, BATTLE_STARTED,
	ORDER_APPLIED, ENEMY_CHARGE, WALL_ALERT, GARRISON_CAVALRY, BATTLE_DECIDED, PROJECTILE_MISSED }
enum Attack { NONE, MELEE, PROJECTILE, CHARGE, COUNTER }
enum ImpactStyle { BLOOD, DUST, DARK_BLOOD }
