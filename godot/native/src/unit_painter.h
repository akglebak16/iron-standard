// Draws the ordinary fighters of a battle frame (body, weapon, ring, health bar, flee flag) and the plants between
// them in depth order, straight into a canvas item (battle/presentation/unit_view.gd, unit_markers.gd).
#pragma once
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/rid.hpp>

namespace godot {

class UnitPainter : public RefCounted {
	GDCLASS(UnitPainter, RefCounted)

protected:
	static void _bind_methods();

public:
	static void configure(const Dictionary &config);
	static void release();
	// render: BattleCore.render_data() for the frame (RENDER_STRIDE doubles per unit, same order as frame).
	// Returns [dead indices to draw now, special indices (hero, companions, leaders)]; ordinary fighters are kept
	// for draw_ordinary(). Looks of new units come from art.layers(frame[i]).
	static Array prepare(const PackedFloat64Array &render, const Array &frame, const Rect2 &visible, Object *art);
	static void draw_ordinary(const RID &canvas, const Array &plants, const Rect2 &visible, int64_t selection, double time,
			const Dictionary &flashes, const Dictionary &attacks);
	static void mark_baked(int64_t id);
	static void forget();
};

} // namespace godot
