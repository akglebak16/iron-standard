#include "battle_unit.h"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

int BattleUnit::mode_code(const String &v) {
	if (v.is_empty()) return 0;
	if (v == "slot") return 1;
	if (v == "melee") return 2;
	if (v == "shoot") return 3;
	if (v == "shootslot") return 4;
	if (v == "skirm") return 5;
	return 6;
}

void BattleUnit::set_ai_mode(const String &v) {
	ai_mode = v;
	ai_mode_code = mode_code(v);
}

void BattleUnit::_bind_methods() {
#define BIND(T, N, VT) \
	ClassDB::bind_method(D_METHOD("set_" #N, "value"), &BattleUnit::set_##N); \
	ClassDB::bind_method(D_METHOD("get_" #N), &BattleUnit::get_##N); \
	ADD_PROPERTY(PropertyInfo(Variant::VT, #N), "set_" #N, "get_" #N);
	BIND(int64_t, id, INT)
	BIND(int64_t, battle_index, INT)
	BIND(int64_t, side, INT)
	BIND(int64_t, group_kind, INT)
	BIND(Vector2, position, VECTOR2)
	BIND(Vector2, velocity, VECTOR2)
	BIND(Vector2, slot_offset, VECTOR2)
	BIND(double, facing, FLOAT)
	BIND(double, speed, FLOAT)
	BIND(double, attack_range, FLOAT)
	BIND(double, collision_radius, FLOAT)
	BIND(double, mass, FLOAT)
	BIND(double, melee_reach, FLOAT)
	BIND(double, attack_interval, FLOAT)
	BIND(double, attack_cooldown, FLOAT)
	BIND(double, charge_cooldown, FLOAT)
	BIND(double, target_timer, FLOAT)
	BIND(double, ai_windup, FLOAT)
	BIND(double, plan_face, FLOAT)
	BIND(double, plan_speed, FLOAT)
	BIND(double, plan_distance, FLOAT)
	BIND(Vector2, plan_destination, VECTOR2)
	BIND(int64_t, target_index, INT)
	BIND(int64_t, ai_wind_target_index, INT)
	BIND(String, ai_mode, STRING)
	BIND(double, hp, FLOAT)
	BIND(double, weight, FLOAT)
	BIND(double, max_hp, FLOAT)
	BIND(double, morale, FLOAT)
	BIND(double, base_morale, FLOAT)
	BIND(double, attack_windup, FLOAT)
	BIND(int64_t, tier, INT)
	BIND(bool, leader, BOOL)
	BIND(bool, is_companion, BOOL)
	BIND(bool, blocking, BOOL)
	BIND(bool, mounted, BOOL)
	BIND(bool, dead, BOOL)
	BIND(bool, gone, BOOL)
	BIND(bool, hero, BOOL)
	BIND(bool, fleeing, BOOL)
#undef BIND
}
