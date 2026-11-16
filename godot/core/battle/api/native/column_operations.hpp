#pragma once
#include "../../../../runtime/simulation/native/contact_solver.hpp"
#include "../../simulation/native/unit_columns.hpp"
#include <array>
namespace iron::battle {
struct ColumnView {
  int count, capacity;
  const double *reals;
  const int64_t *integers;
  double r(R f, int row) const { return reals[int(f) * capacity + row]; }
  int64_t i(I f, int row) const { return integers[int(f) * capacity + row]; }
};
inline double distance(Vec2 a, Vec2 b) { return (a - b).length(); }
inline bool ready_on_side(const ColumnView &c, int row, int side) {
  return c.i(I_SIDE, row) == side && !c.i(I_DEAD, row) && !c.i(I_GONE, row) &&
         !c.i(I_FLEEING, row);
}
class ProjectileQueries {
  Grid grid;
  std::vector<Vec2> positions;

public:
  template <class Position>
  std::vector<std::vector<int>> query(const ColumnView &c, Position position,
                                      const std::vector<Vec2> &impacts,
                                      Vec2 arena, double padding, double height,
                                      double cell) {
    positions.resize(c.count);
    double radius = padding;
    for (int row = 0; row < c.count; ++row) {
      positions[row] = position(row);
      radius = std::max(radius, c.r(R_COLLISION_RADIUS, row) + padding);
    }
    grid.reset(positions, arena.x, arena.y, 0, cell);
    std::vector<std::vector<int>> result(impacts.size());
    for (int k = 0; k < int(impacts.size()); ++k)
      grid.query(impacts[k] + Vec2{0, float(height)}, radius, 0, result[k]);
    return result;
  }
};
// A wall weapon selects the first maximum in active-unit order. The grid only
// narrows the crowd count; strict box edges and tie ordering remain unchanged.
class CrowdQueries {
  Grid grid;
  std::vector<Vec2> positions;
  std::vector<uint8_t> ready;
  std::vector<int> candidates;

public:
  template <class Position>
  std::array<int, 2> densest(const ColumnView &c, Position position, int side,
                             double low_x, double high_x, double half,
                             Vec2 arena, double cell) {
    positions.resize(c.count);
    ready.resize(c.count);
    for (int row = 0; row < c.count; ++row) {
      positions[row] = position(row);
      ready[row] = ready_on_side(c, row, side);
    }
    grid.reset(positions, arena.x, arena.y, 0, cell, &ready);
    std::array<int, 2> best{-1, 0};
    for (int row = 0; row < c.count; ++row) {
      auto p = positions[row];
      if (!ready[row] || p.x < low_x || p.x > high_x)
        continue;
      grid.query(p, half, 0, candidates);
      int count = 0;
      for (int other : candidates)
        if (std::abs(double(positions[other].x) - p.x) < half &&
            std::abs(double(positions[other].y) - p.y) < half)
          ++count;
      if (count > best[1])
        best = {row, count};
    }
    return best;
  }
};
struct Summary {
  std::array<int, 2> counts{}, focus_count{};
  std::array<Vec2, 2> focus{};
  double enemy = 0, ally = 0;
  std::array<double, 3> groups{};
  void add(const ColumnView &c, int row, Vec2 position) {
    if (c.i(I_DEAD, row) || c.i(I_GONE, row))
      return;
    int side = int(c.i(I_SIDE, row));
    counts[side]++;
    if (c.i(I_FLEEING, row))
      return;
    focus_count[side]++;
    focus[side] = focus[side] + position;
    if (side == 1)
      enemy += c.r(R_WEIGHT, row);
    else {
      ally += c.r(R_WEIGHT, row);
      int group = int(c.i(I_GROUP_KIND, row));
      if (!c.i(I_HERO, row) && group >= 0 && group < 3)
        groups[group] += c.r(R_WEIGHT, row);
    }
  }
};
struct RenderRow {
  int flags, side, group, history;
  std::array<double, 5> dynamic;
  RenderRow(const ColumnView &c, int row, Vec2 velocity, int special) {
    history = int(c.i(I_HISTORY_INDEX, row));
    side = int(c.i(I_SIDE, row));
    group = int(c.i(I_GROUP_KIND, row));
    flags = int(c.i(I_DEAD, row)) | int(c.i(I_GONE, row)) * 2 |
            int(c.i(I_HERO, row)) * 4 | special |
            int(c.i(I_MOUNTED, row)) * 16 | int(c.i(I_FLEEING, row)) * 32 |
            int(c.i(I_BLOCKING, row)) * 64 | int(c.i(I_LEADER, row)) * 128;
    dynamic = {c.r(R_COLLISION_RADIUS, row),
               c.r(R_MAX_HP, row) > 0
                   ? std::clamp(c.r(R_HP, row) / c.r(R_MAX_HP, row), 0.0, 1.0)
                   : 0.0,
               c.r(R_FACING, row), velocity.length(), c.r(R_AI_WINDUP, row)};
  }
};
} // namespace iron::battle
