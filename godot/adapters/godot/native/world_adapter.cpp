#include "../../../core/campaign/world/native/world_kernel.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
namespace godot {
// Engine side of the campaign world kernel (ADR-025): checks sizes and converts packed arrays.
class IronWorldKernel : public RefCounted {
  GDCLASS(IronWorldKernel, RefCounted)

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("stamp", "xs", "ys", "strengths", "layers", "layer_count",
                                  "cols", "rows", "cell", "radius"),
                         &IronWorldKernel::stamp);
    ClassDB::bind_method(D_METHOD("contact_pairs", "xs", "ys", "reach"),
                         &IronWorldKernel::contact_pairs);
    ClassDB::bind_method(D_METHOD("box", "xs", "ys", "x", "y", "half"), &IronWorldKernel::box);
  }

public:
  // [layer grids (PackedFloat32Array each), stamped cells, sources]; [] when the columns disagree.
  Array stamp(const PackedFloat64Array &xs, const PackedFloat64Array &ys,
              const PackedFloat64Array &strengths, const PackedInt32Array &layers,
              int64_t layer_count, int64_t cols, int64_t rows, double cell, double radius) {
    const int64_t n = xs.size();
    if (ys.size() != n || strengths.size() != n || layers.size() != n || layer_count < 0 ||
        cols < 1 || rows < 1 || !(cell > 0.0) || !(radius > 0.0))
      return Array();
    iron::campaign::StampResult r = iron::campaign::stamp_layers(
        xs.ptr(), ys.ptr(), strengths.ptr(), layers.ptr(), static_cast<int>(n),
        static_cast<int>(layer_count), static_cast<int>(cols), static_cast<int>(rows), cell, radius);
    Array grids;
    for (const std::vector<float> &layer : r.layers) {
      PackedFloat32Array grid;
      grid.resize(static_cast<int64_t>(layer.size()));
      float *w = grid.ptrw();
      for (size_t i = 0; i < layer.size(); ++i)
        w[i] = layer[i];
      grids.push_back(grid);
    }
    Array out;
    out.push_back(grids);
    out.push_back(r.stamped_cells);
    out.push_back(r.sources);
    return out;
  }

  // Flat [i0, j0, i1, j1, ...] of pairs closer than reach; empty when the columns disagree.
  PackedInt32Array contact_pairs(const PackedFloat64Array &xs, const PackedFloat64Array &ys,
                                 double reach) {
    PackedInt32Array out;
    if (xs.size() != ys.size() || !(reach > 0.0))
      return out;
    std::vector<int32_t> pairs = iron::campaign::contact_pairs(
        xs.ptr(), ys.ptr(), static_cast<int>(xs.size()), reach);
    out.resize(static_cast<int64_t>(pairs.size()));
    int32_t *w = out.ptrw();
    for (size_t i = 0; i < pairs.size(); ++i)
      w[i] = pairs[i];
    return out;
  }

  // Indices of the points within the box, ascending; empty when the columns disagree.
  PackedInt32Array box(const PackedFloat64Array &xs, const PackedFloat64Array &ys, double x, double y,
                       double half) {
    PackedInt32Array out;
    if (xs.size() != ys.size() || !(half >= 0.0))
      return out;
    std::vector<int32_t> hit =
        iron::campaign::box_query(xs.ptr(), ys.ptr(), static_cast<int>(xs.size()), x, y, half);
    out.resize(static_cast<int64_t>(hit.size()));
    int32_t *w = out.ptrw();
    for (size_t i = 0; i < hit.size(); ++i)
      w[i] = hit[i];
    return out;
  }
};
void register_world_kernel() { ClassDB::register_class<IronWorldKernel>(); }
} // namespace godot
