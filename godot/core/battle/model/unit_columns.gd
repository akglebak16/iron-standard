extends "res://runtime/simulation/motion_store.gd"
## Generated layout; values are authoritative for bound units.
enum R { HP, MAX_HP, WEIGHT, COLLISION_RADIUS, MASS, SPEED, ATTACK_RANGE, MELEE_REACH, ATTACK_INTERVAL, ATTACK_COOLDOWN, CHARGE_COOLDOWN, TARGET_TIMER, FACING, AI_WINDUP, PLAN_FACE, PLAN_SPEED, PLAN_DISTANCE, CHASE_SECONDS, DAMAGE, COUNT }
enum I { ID, SIDE, GROUP_KIND, TARGET_HANDLE, AI_WIND_TARGET_HANDLE, UNIT_HANDLE, HISTORY_INDEX, RETIRED_TICK, DEAD, GONE, HERO, MOUNTED, FLEEING, BLOCKING, LEADER, ATTACKERS, LEASHED, AIMERS, MODE, COUNT }
enum V { SLOT_OFFSET, PLAN_DESTINATION, COUNT }
const MODES = ["","slot","melee","shoot","shootslot","skirm"]
var capacity := 0
var real_fields := PackedFloat64Array()
var integer_fields := PackedInt64Array()
var vector_fields := PackedVector2Array()

func resize(count: int) -> void:
	super.resize(count)
	if count <= capacity: return
	var grown := maxi(16, capacity * 2)
	while grown < count: grown *= 2
	var reals := PackedFloat64Array()
	var integers := PackedInt64Array()
	var vectors := PackedVector2Array()
	reals.resize(grown * R.COUNT)
	integers.resize(grown * I.COUNT)
	vectors.resize(grown * V.COUNT)
	for field in R.COUNT:
		for row in capacity: reals[field * grown + row] = real_fields[field * capacity + row]
	for field in I.COUNT:
		for row in capacity: integers[field * grown + row] = integer_fields[field * capacity + row]
	for field in V.COUNT:
		for row in capacity: vectors[field * grown + row] = vector_fields[field * capacity + row]
	real_fields = reals
	integer_fields = integers
	vector_fields = vectors
	capacity = grown

func copy_row(source: int, destination: int) -> void:
	super.copy_row(source, destination)
	for field in R.COUNT: real_fields[field * capacity + destination] = real_fields[field * capacity + source]
	for field in I.COUNT: integer_fields[field * capacity + destination] = integer_fields[field * capacity + source]
	for field in V.COUNT: vector_fields[field * capacity + destination] = vector_fields[field * capacity + source]
