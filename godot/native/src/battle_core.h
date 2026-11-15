// The hot part of a battle tick in native code: targeting, AI decisions, steering, attack timing and the
// collision pass (battle/rules/movement.gd, targeting.gd, ai_decision.gd, charge.gd, combat_step.gd).
// Damage, projectiles and walls stay in GDScript and are called back, so the rules have one home.
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace godot {

class BattleCore : public RefCounted {
	GDCLASS(BattleCore, RefCounted)

protected:
	static void _bind_methods();

public:
	static void configure(const Dictionary &config, const Variant &charge_rules, const Variant &combat_rules);
	static bool is_configured();
	static void release();
	static void step(Object *battle, const Array &units, const Array &groups, const Vector2 &arena, double dt,
			const Ref<RandomNumberGenerator> &rng, Object *wall, const PackedVector2Array &trunk_pos, const PackedFloat64Array &trunk_rad);
	static Vector2 centroid(const Array &units, int64_t side);
	static double nearest_foe_distance(const Array &units, const Vector2 &point, int64_t side);
	static bool has_active(const Array &units);
	static void death_morale(const Array &units, Object *target, double radius, double leader_loss, double ally_loss, double ally_loss_per_tier, double enemy_bonus);
	static Array unit_values(const Array &units, const Array &templates, const Array &looks);
	static Array frame_values(const Array &units, const Array &templates, const Array &looks, Array cache, Array kinds);
	static Array frame_stats(const Array &units, int64_t group_kinds);
	static PackedFloat64Array render_data(const Array &units);
};

} // namespace godot
