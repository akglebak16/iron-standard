// Hot fields of a battle unit, kept in native memory so the battle core reads them directly.
// battle/model/unit.gd extends this class and adds everything else; GDScript sees these as ordinary properties.
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <limits>

namespace godot {

class BattleUnit : public RefCounted {
	GDCLASS(BattleUnit, RefCounted)

protected:
	static void _bind_methods();

public:
	int64_t id = 0;
	int64_t battle_index = -1;
	int64_t side = 0;
	int64_t group_kind = 0;
	Vector2 position;
	Vector2 velocity;
	Vector2 slot_offset;
	double facing = 0.0;
	double speed = 0.0;
	double attack_range = 0.0;
	double collision_radius = 12.5;
	double mass = 1.0;
	double melee_reach = 6.0;
	double attack_interval = 1.0;
	double attack_cooldown = 0.0;
	double charge_cooldown = 0.0;
	double target_timer = 0.0;
	double ai_windup = -1.0;
	double plan_face = 0.0;
	double plan_speed = 1.0;
	double plan_distance = std::numeric_limits<double>::infinity();
	Vector2 plan_destination;
	int64_t target_index = -1;
	int64_t ai_wind_target_index = -1;
	String ai_mode;
	double hp = 0.0;
	double weight = 1.0;
	double max_hp = 0.0;
	double morale = 0.0;
	double base_morale = 0.0;
	double attack_windup = -1.0;
	int64_t tier = 0;
	bool leader = false;
	bool is_companion = false;
	bool blocking = false;
	bool mounted = false;
	bool dead = false;
	bool gone = false;
	bool hero = false;
	bool fleeing = false;
	int ai_mode_code = 0; // cached ai_mode for the core; kept in sync by set_ai_mode

#define BU_PROP(T, N) \
	void set_##N(T v) { N = v; } \
	T get_##N() const { return N; }
	BU_PROP(int64_t, id)
	BU_PROP(int64_t, battle_index)
	BU_PROP(int64_t, side)
	BU_PROP(int64_t, group_kind)
	BU_PROP(Vector2, position)
	BU_PROP(Vector2, velocity)
	BU_PROP(Vector2, slot_offset)
	BU_PROP(double, facing)
	BU_PROP(double, speed)
	BU_PROP(double, attack_range)
	BU_PROP(double, collision_radius)
	BU_PROP(double, mass)
	BU_PROP(double, melee_reach)
	BU_PROP(double, attack_interval)
	BU_PROP(double, attack_cooldown)
	BU_PROP(double, charge_cooldown)
	BU_PROP(double, target_timer)
	BU_PROP(double, ai_windup)
	BU_PROP(double, plan_face)
	BU_PROP(double, plan_speed)
	BU_PROP(double, plan_distance)
	BU_PROP(Vector2, plan_destination)
	BU_PROP(int64_t, target_index)
	BU_PROP(int64_t, ai_wind_target_index)
	BU_PROP(double, hp)
	BU_PROP(double, weight)
	BU_PROP(double, max_hp)
	BU_PROP(double, morale)
	BU_PROP(double, base_morale)
	BU_PROP(double, attack_windup)
	BU_PROP(int64_t, tier)
	BU_PROP(bool, leader)
	BU_PROP(bool, is_companion)
	BU_PROP(bool, blocking)
	BU_PROP(bool, mounted)
	BU_PROP(bool, dead)
	BU_PROP(bool, gone)
	BU_PROP(bool, hero)
	BU_PROP(bool, fleeing)
#undef BU_PROP
	void set_ai_mode(const String &v);
	String get_ai_mode() const { return ai_mode; }
	static int mode_code(const String &v);
};

} // namespace godot
