extends RefCounted
## Shared codes for facts emitted by the simulation and read by presentation.

enum Kind { HIT, BLOCK, CHARGE, DOWN, LAST_STAND }
enum Attack { NONE, MELEE, PROJECTILE, CHARGE, COUNTER }
