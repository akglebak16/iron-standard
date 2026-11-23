#include "../../../core/battle/api/native/morale_kernel.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <type_traits>
namespace godot {
// ADR-026: the native morale check and the field assessment pass (core/battle/api/native/morale_kernel.hpp). Packed
// arrays are read and written only through ptr()/ptrw() (#263); the check writes the morale columns in place after the
// store handed them over, as the movement kernel does (#298).
class IronMoraleKernel : public RefCounted {
  GDCLASS(IronMoraleKernel, RefCounted)
  iron::battle::MoraleKernel kernel;
  iron::battle::MoraleKernel::Result result;
  std::vector<double> sums;
  bool ready = false;
  static_assert(std::is_same_v<real_t, float> && sizeof(Vector2) == sizeof(iron::Vec2) &&
                    alignof(Vector2) == alignof(iron::Vec2),
                "the morale kernel reads PackedVector2Array buffers as iron::Vec2");

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "parameters"), &IronMoraleKernel::configure);
    ClassDB::bind_method(D_METHOD("assess", "columns", "laterals", "loose", "cover", "elevation", "width"),
                         &IronMoraleKernel::assess);
    ClassDB::bind_method(D_METHOD("check", "columns", "losses", "starting", "arena_width", "grouped", "cell"),
                         &IronMoraleKernel::check);
  }
  // The columns packet [capacity, positions, velocities, reals, integers, vectors], as in column_adapter.cpp, with the
  // side of every row checked: the kernel indexes per-side tables with it.
  bool bind(const Array &columns, PackedVector2Array &positions, PackedFloat64Array &reals,
            PackedInt64Array &integers) {
    using namespace iron::battle;
    if (!ready || columns.size() != 6)
      return false;
    const int64_t capacity = columns[0];
    positions = columns[1];
    const PackedVector2Array velocities = columns[2], vectors = columns[5];
    reals = columns[3];
    integers = columns[4];
    const int64_t count = positions.size();
    if (capacity < count || capacity > 131072 || capacity < 0 || velocities.size() != count ||
        reals.size() != capacity * R_COUNT || integers.size() != capacity * I_COUNT ||
        vectors.size() != capacity * V_COUNT)
      return false;
    const int64_t *sides = integers.ptr() + I_SIDE * capacity;
    for (int64_t row = 0; row < count; ++row)
      if (sides[row] < 0 || sides[row] > 1)
        return false;
    kernel.count = int(count);
    kernel.capacity = int(capacity);
    kernel.positions = reinterpret_cast<const iron::Vec2 *>(positions.ptr());
    return true;
  }
  void release() {
    kernel.positions = nullptr;
    kernel.reals = nullptr;
    kernel.integers = nullptr;
    kernel.terrain = {};
  }

public:
  bool configure(const PackedFloat64Array &parameters) {
    using namespace iron::battle::morale;
    ready = false;
    if (parameters.size() != PARAMETER_COUNT)
      return false;
    const double *values = parameters.ptr();
    for (int64_t n = 0; n < parameters.size(); ++n)
      if (!std::isfinite(values[n]) || values[n] < 0)
        return false;
    kernel.parameters.assign(values, values + parameters.size());
    const int classes = int(values[AI_CLASSES]);
    if (values[GROUP_KINDS] < 1 || values[GROUP_KINDS] > 8 || classes < 1 || classes > 16 ||
        values[TERRAIN_CELL] <= 0)
      return false;
    for (int klass : {AI_CLASS_FOOT, AI_CLASS_SPEAR, AI_CLASS_ARCHER, AI_CLASS_CAVALRY, AI_CLASS_HORSE_ARCHER})
      if (values[klass] >= classes || double(int(values[klass])) != values[klass])
        return false;
    // GDScript's cos and sin are the engine's utility functions: the same results, bit for bit.
    kernel.cosine = [](double x) { return UtilityFunctions::cos(x); };
    kernel.sine = [](double x) { return UtilityFunctions::sin(x); };
    ready = true;
    return true;
  }

  // FieldAssessment.assess, the pass over the fighters: per slot the sums of MoraleKernel::Sum; empty on bad input.
  PackedFloat64Array assess(const Array &columns, const PackedVector2Array &laterals, const PackedByteArray &loose,
                            const PackedByteArray &cover, const PackedByteArray &elevation, int64_t width) {
    PackedFloat64Array out;
    PackedVector2Array positions;
    PackedFloat64Array reals;
    PackedInt64Array integers;
    if (!bind(columns, positions, reals, integers))
      return out;
    const int slots = 2 * kernel.kinds();
    if (laterals.size() != slots || loose.size() != slots)
      return out;
    iron::battle::TerrainGrid grid;
    if (!cover.is_empty()) {
      if (width <= 0 || cover.size() % width != 0 || elevation.size() != cover.size())
        return out;
      grid.width = int(width);
      grid.height = int(cover.size() / width);
      grid.cell = kernel.parameters[iron::battle::morale::TERRAIN_CELL];
      grid.cover = cover.ptr();
      grid.elevation = elevation.ptr();
    }
    // Read only: const pointers, no copy-on-write of the store's columns.
    kernel.reals = const_cast<double *>(reals.ptr());
    kernel.integers = const_cast<int64_t *>(integers.ptr());
    kernel.terrain = grid;
    out.resize(int64_t(slots) * kernel.sum_fields());
    kernel.assess(reinterpret_cast<const iron::Vec2 *>(laterals.ptr()), loose.ptr(), out.ptrw());
    release();
    return out;
  }

  // Morale.tick after the group losses. `columns` is a handoff packet: the store gave up its reals and integers, so
  // they are written in place and come back as [active 0, active 1, notices, rallied, reals, integers]; on a
  // rejection the packet is untouched and the result empty.
  Array check(Array columns, const PackedFloat64Array &losses, const PackedInt64Array &starting, double arena_width,
              bool grouped, double cell) {
    PackedVector2Array positions;
    PackedFloat64Array reals;
    PackedInt64Array integers;
    if (!bind(columns, positions, reals, integers) || losses.size() != 2 * kernel.kinds() ||
        starting.size() != 2 || !std::isfinite(arena_width) || !(cell > 0) || !std::isfinite(cell))
      return {};
    // The packet no longer holds the store's buffers: ptrw() then writes them without a copy.
    columns[3] = Variant();
    columns[4] = Variant();
    kernel.reals = reals.ptrw();
    kernel.integers = integers.ptrw();
    const int64_t sides[2] = {starting[0], starting[1]};
    kernel.check(losses.ptr(), sides, arena_width, grouped, cell, result);
    release();
    PackedInt32Array notices, rallied;
    notices.resize(int64_t(result.notices.size()));
    std::copy(result.notices.begin(), result.notices.end(), notices.ptrw());
    rallied.resize(int64_t(result.rallied.size()));
    std::copy(result.rallied.begin(), result.rallied.end(), rallied.ptrw());
    Array out;
    out.push_back(result.active[0]);
    out.push_back(result.active[1]);
    out.push_back(notices);
    out.push_back(rallied);
    out.push_back(reals);
    out.push_back(integers);
    return out;
  }
};
void register_morale_kernel() { ClassDB::register_class<IronMoraleKernel>(); }
} // namespace godot
