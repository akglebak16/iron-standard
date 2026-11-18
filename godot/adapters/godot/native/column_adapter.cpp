#include "../../../core/battle/api/native/column_operations.hpp"
#include "../../../core/battle/api/native/terrain_grid.hpp"
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
namespace godot {
class IronColumnKernel : public RefCounted {
  GDCLASS(IronColumnKernel, RefCounted)
  iron::battle::ProjectileQueries projectile_queries;
  iron::battle::CrowdQueries crowd_queries;

protected:
  static void _bind_methods() {
    ClassDB::bind_method(
        D_METHOD("wall_status", "columns", "inside_x", "alert_x", "defender_x"),
        &IronColumnKernel::wall_status);
    ClassDB::bind_method(D_METHOD("densest_ready", "columns", "side", "low_x",
                                  "high_x", "half", "arena", "cell"),
                         &IronColumnKernel::densest_ready);
    ClassDB::bind_method(D_METHOD("projectile_candidates", "columns", "impacts",
                                  "arena", "padding", "height", "cell"),
                         &IronColumnKernel::projectile_candidates);
    ClassDB::bind_method(D_METHOD("nearby", "columns", "position", "radius"),
                         &IronColumnKernel::nearby);
    ClassDB::bind_method(
        D_METHOD("nearest_ready", "columns", "position", "side"),
        &IronColumnKernel::nearest_ready);
    ClassDB::bind_method(D_METHOD("copy_rows", "columns", "rows"),
                         &IronColumnKernel::copy_rows);
    ClassDB::bind_method(D_METHOD("capture", "columns", "previous"),
                         &IronColumnKernel::capture);
    ClassDB::bind_method(D_METHOD("terrain_cells", "cover", "elevation",
                                  "width", "cell", "points"),
                         &IronColumnKernel::terrain_cells);
    ClassDB::bind_method(D_METHOD("summary", "columns"),
                         &IronColumnKernel::summary);
    ClassDB::bind_method(
        D_METHOD("render", "columns", "previous", "special", "definitions"),
        &IronColumnKernel::render);
  }
  struct Input {
    int capacity = 0, count = 0;
    bool valid = false;
    PackedVector2Array positions, velocities, vectors;
    PackedFloat64Array reals;
    PackedInt64Array integers;
    Input(const Array &a) {
      using namespace iron::battle;
      if (a.size() != 6)
        return;
      capacity = a[0];
      positions = a[1];
      velocities = a[2];
      reals = a[3];
      integers = a[4];
      vectors = a[5];
      count = int(positions.size());
      valid = capacity >= count && capacity <= 131072 && capacity >= 0 &&
              velocities.size() == count &&
              reals.size() == capacity * R_COUNT &&
              integers.size() == capacity * I_COUNT &&
              vectors.size() == capacity * V_COUNT;
    }
    iron::battle::ColumnView view() const {
      return {count, capacity, reals.ptr(), integers.ptr()};
    }
  };

public:
  Array wall_status(const Array &columns, double inside_x, double alert_x,
                    double defender_x) {
    Input c(columns);
    if (!c.valid || !std::isfinite(inside_x) || !std::isfinite(alert_x) ||
        !std::isfinite(defender_x))
      return {};
    iron::battle::WallSummary summary;
    auto view = c.view();
    const auto *positions = c.positions.ptr();
    for (int row = 0; row < c.count; ++row)
      summary.add(view, row, positions[row].x, inside_x, alert_x, defender_x);
    PackedInt32Array attackers;
    attackers.resize(summary.attackers.size());
    auto *out = attackers.ptrw();
    for (int row = 0; row < int(summary.attackers.size()); ++row)
      out[row] = summary.attackers[row];
    Array result;
    result.push_back(attackers);
    result.push_back(summary.inside);
    result.push_back(summary.alert);
    result.push_back(summary.defenders);
    return result;
  }
  // TERRAIN.md 3.4: reads the battle terrain grid at `points` with the C++ reader; cover | height << 8 per point,
  // empty on a malformed grid. Used to prove the reader equals core/battle/model/terrain_grid.gd.
  PackedInt32Array terrain_cells(const PackedByteArray &cover,
                                 const PackedByteArray &elevation, int width,
                                 double cell, const PackedVector2Array &points) {
    PackedInt32Array out;
    if (width <= 0 || cover.size() == 0 || cover.size() % width != 0 ||
        elevation.size() != cover.size() || !(cell > 0.0))
      return out;
    iron::battle::TerrainGrid grid;
    grid.width = width;
    grid.height = int(cover.size() / width);
    grid.cell = cell;
    grid.cover = cover.ptr();
    grid.elevation = elevation.ptr();
    out.resize(points.size());
    for (int64_t i = 0; i < points.size(); ++i) {
      const Vector2 at = points[i];
      out.set(i, int(grid.cover_at(at.x, at.y)) | int(grid.height_at(at.x, at.y)) << 8);
    }
    return out;
  }
  PackedInt32Array densest_ready(const Array &columns, int side, double low_x,
                                 double high_x, double half, Vector2 arena,
                                 double cell) {
    Input c(columns);
    PackedInt32Array out;
    if (!c.valid || side < 0 || side > 1 || !std::isfinite(low_x) ||
        !std::isfinite(high_x) || low_x > high_x || !std::isfinite(half) ||
        half <= 0 || !arena.is_finite() || arena.x <= 0 || arena.y <= 0 ||
        !std::isfinite(cell) || cell <= 0)
      return out;
    const auto *positions = c.positions.ptr();
    auto result = crowd_queries.densest(
        c.view(),
        [&](int row) { return iron::Vec2{positions[row].x, positions[row].y}; },
        side, low_x, high_x, half, {arena.x, arena.y}, cell);
    out.push_back(result[0]);
    out.push_back(result[1]);
    return out;
  }
  Array projectile_candidates(const Array &columns,
                              const PackedVector2Array &impacts, Vector2 arena,
                              double padding, double height, double cell) {
    Input c(columns);
    Array result;
    if (!c.valid || !arena.is_finite() || arena.x <= 0 || arena.y <= 0 ||
        !std::isfinite(cell) || cell <= 0 || !std::isfinite(padding) ||
        padding < 0 || !std::isfinite(height))
      return result;
    std::vector<iron::Vec2> targets;
    for (int k = 0; k < impacts.size(); ++k) {
      if (!impacts[k].is_finite())
        return result;
      targets.push_back({impacts[k].x, impacts[k].y});
    }
    const auto *positions = c.positions.ptr();
    auto batches = projectile_queries.query(
        c.view(),
        [&](int row) { return iron::Vec2{positions[row].x, positions[row].y}; },
        targets, {arena.x, arena.y}, padding, height, cell);
    for (const auto &batch : batches) {
      PackedInt32Array values;
      values.resize(batch.size());
      auto *out = values.ptrw();
      for (int k = 0; k < int(batch.size()); ++k)
        out[k] = batch[k];
      result.push_back(values);
    }
    return result;
  }
  PackedInt32Array nearby(const Array &columns, Vector2 position,
                          double radius) {
    Input c(columns);
    PackedInt32Array out;
    if (!c.valid || !position.is_finite() || !std::isfinite(radius) ||
        radius < 0)
      return out;
    const Vector2 *points = c.positions.ptr();
    for (int row = 0; row < c.count; ++row)
      if (iron::battle::distance({points[row].x, points[row].y},
                                 {position.x, position.y}) <= radius)
        out.push_back(row);
    return out;
  }
  double nearest_ready(const Array &columns, Vector2 position, int side) {
    Input c(columns);
    if (!c.valid || !position.is_finite() || side < 0 || side > 1)
      return INFINITY;
    auto view = c.view();
    const Vector2 *points = c.positions.ptr();
    double result = INFINITY;
    for (int row = 0; row < c.count; ++row)
      if (iron::battle::ready_on_side(view, row, side))
        result = std::min(result,
                          iron::battle::distance({points[row].x, points[row].y},
                                                 {position.x, position.y}));
    return result;
  }
  Array copy_rows(const Array &columns, const PackedInt32Array &rows) {
    using namespace iron::battle;
    Input c(columns);
    if (!c.valid)
      return {};
    for (int k = 0; k < rows.size(); ++k)
      if (rows[k] < k || rows[k] >= c.count ||
          (k > 0 && rows[k] <= rows[k - 1]))
        return {};
    auto *p = c.positions.ptrw(), *v = c.velocities.ptrw(),
         *vf = c.vectors.ptrw();
    auto *r = c.reals.ptrw();
    auto *i = c.integers.ptrw();
    for (int k = 0; k < rows.size(); ++k) {
      int from = rows[k];
      p[k] = p[from];
      v[k] = v[from];
    }
    for (int f = 0; f < R_COUNT; ++f)
      for (int k = 0; k < rows.size(); ++k)
        r[f * c.capacity + k] = r[f * c.capacity + rows[k]];
    for (int f = 0; f < I_COUNT; ++f)
      for (int k = 0; k < rows.size(); ++k)
        i[f * c.capacity + k] = i[f * c.capacity + rows[k]];
    for (int f = 0; f < V_COUNT; ++f)
      for (int k = 0; k < rows.size(); ++k)
        vf[f * c.capacity + k] = vf[f * c.capacity + rows[k]];
    c.positions.resize(rows.size());
    c.velocities.resize(rows.size());
    Array out;
    out.push_back(c.positions);
    out.push_back(c.velocities);
    out.push_back(c.reals);
    out.push_back(c.integers);
    out.push_back(c.vectors);
    return out;
  }
  PackedVector2Array capture(const Array &columns,
                             PackedVector2Array previous) {
    using namespace iron::battle;
    Input c(columns);
    if (!c.valid)
      return {};
    auto view = c.view();
    for (int row = 0; row < c.count; ++row)
      if (view.i(I_HISTORY_INDEX, row) < 0 ||
          view.i(I_HISTORY_INDEX, row) >= previous.size())
        return {};
    auto *out = previous.ptrw();
    auto *pos = c.positions.ptr();
    for (int row = 0; row < c.count; ++row)
      out[view.i(I_HISTORY_INDEX, row)] = pos[row];
    return previous;
  }
  Array summary(const Array &columns) {
    using namespace iron::battle;
    Input c(columns);
    if (!c.valid)
      return {};
    Summary s;
    auto view = c.view();
    const Vector2 *pos = c.positions.ptr();
    for (int row = 0; row < c.count; ++row) {
      if (view.i(I_SIDE, row) < 0 || view.i(I_SIDE, row) > 1)
        return {};
      s.add(view, row, {pos[row].x, pos[row].y});
    }
    Array counts, focus, focus_count;
    for (int side = 0; side < 2; ++side) {
      counts.push_back(s.counts[side]);
      focus.push_back(Vector2(s.focus[side].x, s.focus[side].y));
      focus_count.push_back(s.focus_count[side]);
    }
    PackedFloat64Array groups;
    for (double w : s.groups)
      groups.push_back(w);
    Array out;
    out.push_back(counts);
    out.push_back(focus);
    out.push_back(focus_count);
    out.push_back(s.enemy);
    out.push_back(s.ally);
    out.push_back(groups);
    return out;
  }
  Array render(const Array &columns, const PackedVector2Array &previous,
               const PackedInt32Array &special,
               const TypedArray<Dictionary> &definitions) {
    using namespace iron::battle;
    Input c(columns);
    if (!c.valid)
      return {};
    auto view = c.view();
    for (int row = 0; row < c.count; ++row)
      if (view.i(I_HISTORY_INDEX, row) < 0 ||
          view.i(I_HISTORY_INDEX, row) >= special.size() ||
          view.i(I_HISTORY_INDEX, row) >= definitions.size())
        return {};
    PackedVector2Array prev;
    PackedInt32Array sides, groups, flags, histories;
    PackedInt64Array ids;
    TypedArray<Dictionary> selected;
    ids.resize(c.count);
    selected.resize(c.count);
    PackedFloat64Array dynamic;
    prev.resize(c.count);
    sides.resize(c.count);
    groups.resize(c.count);
    flags.resize(c.count);
    histories.resize(c.count);
    dynamic.resize(c.count * 5);
    auto *o = prev.ptrw();
    auto *s = sides.ptrw(), *g = groups.ptrw(), *f = flags.ptrw(),
         *h = histories.ptrw();
    auto *d = dynamic.ptrw();
    const Vector2 *positions = c.positions.ptr(),
                  *velocities = c.velocities.ptr();
    for (int row = 0; row < c.count; ++row) {
      RenderRow value(view, row, {velocities[row].x, velocities[row].y},
                      special[view.i(I_HISTORY_INDEX, row)]);
      h[row] = value.history;
      ids.set(row, view.i(I_ID, row));
      selected[row] = definitions[value.history];
      s[row] = value.side;
      g[row] = value.group;
      f[row] = value.flags;
      o[row] = value.history < previous.size() ? previous[value.history]
                                               : positions[row];
      for (int k = 0; k < 5; ++k)
        d[row * 5 + k] = value.dynamic[k];
    }
    Array out;
    out.push_back(c.positions);
    out.push_back(prev);
    out.push_back(sides);
    out.push_back(groups);
    out.push_back(flags);
    out.push_back(dynamic);
    out.push_back(histories);
    out.push_back(ids);
    out.push_back(selected);
    return out;
  }
};
void register_column_kernel() { ClassDB::register_class<IronColumnKernel>(); }
} // namespace godot
