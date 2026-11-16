#include "../../../core/battle/api/native/movement_kernel.hpp"
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
namespace godot {
class IronMovementKernel : public RefCounted {
  GDCLASS(IronMovementKernel, RefCounted)
  iron::battle::MovementKernel kernel;
  bool ready = false, active = false;
  static void read_vectors(const PackedVector2Array &in,
                           std::vector<iron::Vec2> &out) {
    out.resize(in.size());
    const Vector2 *p = in.ptr();
    for (int n = 0; n < in.size(); ++n)
      out[n] = {p[n].x, p[n].y};
  }
  static PackedVector2Array write_vectors(const std::vector<iron::Vec2> &in) {
    PackedVector2Array out;
    out.resize(in.size());
    Vector2 *p = out.ptrw();
    for (int n = 0; n < int(in.size()); ++n)
      p[n] = {in[n].x, in[n].y};
    return out;
  }

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "parameters"),
                         &IronMovementKernel::configure);
    ClassDB::bind_method(
        D_METHOD("advance", "columns", "context", "rng", "dt", "begin"),
        &IronMovementKernel::advance);
  }

public:
  bool configure(const PackedFloat64Array &parameters) {
    ready = false;
    if (parameters.size() != iron::battle::PARAMETER_COUNT)
      return false;
    for (double value : parameters)
      if (!std::isfinite(value) || value <= 0)
        return false;
    StringName name("angle");
    auto angle = gdextension_interface::variant_get_ptr_builtin_method(
        GDEXTENSION_VARIANT_TYPE_VECTOR2, name._native_ptr(), 466405837);
    if (!angle)
      return false;
    kernel.angle = [angle](iron::Vec2 at) {
      Vector2 v(at.x, at.y);
      double result = 0;
      angle(&v, nullptr, &result, 0);
      return result;
    };
    kernel.parameters.assign(parameters.ptr(),
                             parameters.ptr() + parameters.size());
    ready = true;
    return true;
  }
  Array advance(Array columns, const Dictionary &context,
                const Ref<RandomNumberGenerator> &rng, double dt, bool begin) {
    using namespace iron::battle;
    if (!ready || rng.is_null() || !std::isfinite(dt) || dt <= 0 ||
        columns.size() != 6)
      return {};
    int64_t capacity = columns[0];
    PackedVector2Array positions = columns[1], velocities = columns[2],
                       vectors = columns[5];
    PackedFloat64Array reals = columns[3];
    PackedInt64Array integers = columns[4];
    int64_t count = positions.size();
    if (capacity < count || capacity > 131072 || capacity < 0 ||
        velocities.size() != count || reals.size() != capacity * R_COUNT ||
        integers.size() != capacity * I_COUNT ||
        vectors.size() != capacity * V_COUNT)
      return {};
    if (!begin && (!active || kernel.capacity != capacity ||
                   int64_t(kernel.positions.size()) != count))
      return {};
    // Validate indices before the engine-independent kernel dereferences them.
    for (int row = 0; row < count; ++row) {
      if (integers[I_UNIT_HANDLE * capacity + row] <= 0 ||
          (integers[I_UNIT_HANDLE * capacity + row] & 0xffffffffLL) < 1 ||
          (integers[I_UNIT_HANDLE * capacity + row] & 0xffffffffLL) > 131072 ||
          integers[I_SIDE * capacity + row] < 0 ||
          integers[I_SIDE * capacity + row] > 1 ||
          integers[I_GROUP_KIND * capacity + row] < 0 ||
          integers[I_GROUP_KIND * capacity + row] > 2 ||
          !positions[row].is_finite() || !velocities[row].is_finite())
        return {};
    }
    if (begin) {
      PackedFloat64Array group = context.get("groups", PackedFloat64Array());
      Vector2 arena = context.get("arena", Vector2());
      if (group.size() != 54 || !arena.is_finite() ||
          arena.x < 2 * kernel.parameters[SLOT_EDGE] ||
          arena.y < 2 * kernel.parameters[SLOT_EDGE])
        return {};
      kernel.width = arena.x;
      kernel.height = arena.y;
      kernel.wall_x = context.get("wall_x", INFINITY);
      kernel.wall_half = context.get("wall_half", 0.0);
      read_vectors(context.get("gaps", PackedVector2Array()), kernel.gaps);
      read_vectors(context.get("all_gaps", PackedVector2Array()),
                   kernel.all_gaps);
      kernel.groups.resize(6);
      for (int n = 0; n < 6; ++n) {
        const double *g = group.ptr() + n * 9;
        kernel.groups[n] = {{float(g[0]), float(g[1])},
                            {float(g[2]), float(g[3])},
                            {float(g[4]), float(g[5])},
                            g[6],
                            g[7] != 0,
                            g[8] != 0};
      }
    }
    // Release the handoff packet aliases before requesting writable pointers.
    // Core has relinquished these buffers for this synchronous call; a retained
    // external value still forces normal COW and remains unchanged.
    columns[3] = Variant();
    columns[4] = Variant();
    kernel.capacity = int(capacity);
    kernel.reals = reals.ptrw();
    kernel.integers = integers.ptrw();
    kernel.dt = dt;
    read_vectors(positions, kernel.positions);
    read_vectors(velocities, kernel.velocities);
    read_vectors(vectors, kernel.vectors);
    kernel.random = [&rng]() { return rng->randf(); };
    if (begin) {
      kernel.begin();
      active = true;
    }
    auto result = kernel.run();
    active = result.reason != MovementKernel::DONE;
    Array out;
    out.push_back(result.reason);
    out.push_back(result.unit);
    out.push_back(result.target);
    out.push_back(write_vectors(kernel.positions));
    out.push_back(write_vectors(kernel.velocities));
    out.push_back(reals);
    out.push_back(integers);
    out.push_back(write_vectors(kernel.vectors));
    kernel.reals = nullptr;
    kernel.integers = nullptr;
    kernel.random = {};
    return out;
  }
};
void register_movement_kernel() {
  ClassDB::register_class<IronMovementKernel>();
}
} // namespace godot
