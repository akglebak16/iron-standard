#pragma once
// ADR-026: the once-a-second morale check of core/battle/rules/morale.gd (Morale.tick) and the pass over the fighters of
// core/battle/simulation/ai/field_assessment.gd (FieldAssessment.assess), over the unit columns. The GDScript reference
// stays and test_native_morale.gd compares both on every check, bit for bit: rows in storage order, subtractions in the
// reference order, `float` of GDScript as double, positions and vector sums as float32 (Vector2), the same grid cells.
// The check draws no RNG. Schedule, events, the morale summary of the groups and the assessment dictionary stay in
// GDScript: the kernel returns the notices (row, kind) in order, the groups men rallied into and the per-group sums.
#include "../../../../runtime/simulation/native/contact_solver.hpp"
#include "../../simulation/native/morale_parameters.hpp"
#include "../../simulation/native/unit_columns.hpp"
#include "terrain_grid.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <functional>
#include <unordered_map>
#include <vector>

namespace iron::battle {

class MoraleKernel {
public:
  // Event.Kind of the notice is chosen by GDScript from this code.
  enum Notice { WAVERED, FLED, RALLIED };
  // Per slot (side * GROUP_KINDS + kind) of the field sums, then AI_CLASSES class strengths and AI_CLASSES class counts.
  enum Sum {
    SUM_COUNT, SUM_FLEEING, SUM_WAVERING, SUM_ENGAGED, SUM_POWER, SUM_MORALE, SUM_BASE_MORALE, SUM_POSITION_X,
    SUM_POSITION_Y, SUM_LATERAL_MIN, SUM_LATERAL_MAX, SUM_FACING_X, SUM_FACING_Y, SUM_HEIGHT, SUM_FOREST, SUM_BRUSH,
    SUM_WADING, SUM_CLASSES
  };
  struct Result {
    int active[2] = {0, 0};
    std::vector<int32_t> notices; // Row, Notice; in the order of the reference's record_unit_notice calls.
    std::vector<int32_t> rallied; // command * GROUP_KINDS + kind, first rally first (the reference's dictionary order).
  };

  std::vector<double> parameters;
  // GDScript's cos and sin (the engine's), for the mean facing of a loose charge.
  std::function<double(double)> cosine, sine;
  // Borrowed for one call.
  int count = 0, capacity = 0;
  const Vec2 *positions = nullptr;
  double *reals = nullptr;
  int64_t *integers = nullptr;
  TerrainGrid terrain; // battle.terrain_rules; invalid (width 0) on an open, flat field.

  int kinds() const { return int(p(morale::GROUP_KINDS)); }
  int classes() const { return int(p(morale::AI_CLASSES)); }
  int sum_fields() const { return SUM_CLASSES + 2 * classes(); }

  // FieldAssessment.assess, the pass over the fighters: `laterals` and `loose` per slot, `out` slots * sum_fields().
  void assess(const Vec2 *laterals, const uint8_t *loose, double *out) {
    const int k = kinds(), slots = 2 * k, fields = sum_fields(), klasses = classes();
    sums.assign(size_t(slots) * fields, 0.0);
    position_sum.assign(slots, Vec2{});
    facing_sum.assign(slots, Vec2{});
    for (int slot = 0; slot < slots; ++slot) {
      sums[slot * fields + SUM_LATERAL_MIN] = INFINITY;
      sums[slot * fields + SUM_LATERAL_MAX] = -INFINITY;
    }
    for (int row = 0; row < count; ++row) {
      if (i(I_DEAD, row) || i(I_GONE, row) || i(I_HERO, row))
        continue;
      const int64_t kind = i(I_GROUP_KIND, row);
      if (kind < 0 || kind >= k)
        continue;
      const int slot = int(i(I_SIDE, row)) * k + int(kind);
      double *s = sums.data() + size_t(slot) * fields;
      if (i(I_FLEEING, row)) {
        s[SUM_FLEEING] += 1;
        continue;
      }
      const double max_hp = r(R_MAX_HP, row);
      const double health = max_hp > 0.0 ? clamp(r(R_HP, row) / max_hp, 0.0, 1.0) : 0.0;
      const double power =
          r(R_WEIGHT, row) * health * (1.0 + p(morale::AI_FIELD_TIER_POWER) * double(i(I_TIER, row)));
      const int klass = unit_class(i(I_MOUNTED, row) != 0, r(R_ATTACK_RANGE, row) > 0.0, i(I_ANTI_CAVALRY, row) != 0);
      s[SUM_COUNT] += 1;
      s[SUM_POWER] += power;
      s[SUM_CLASSES + klass] += power;
      s[SUM_CLASSES + klasses + klass] += 1;
      s[SUM_MORALE] += r(R_MORALE, row);
      s[SUM_BASE_MORALE] += r(R_BASE_MORALE, row);
      if (i(I_WAVERING, row))
        s[SUM_WAVERING] += 1;
      if (i(I_MODE, row) == MELEE && r(R_PLAN_DISTANCE, row) <= p(morale::AI_FIELD_CONTACT_DISTANCE))
        s[SUM_ENGAGED] += 1;
      const Vec2 at = positions[row];
      if (loose[slot]) {
        const double facing = r(R_FACING, row);
        // Vector2(cos(facing), sin(facing)): double results rounded to the float components, added as float32.
        facing_sum[slot] = facing_sum[slot] + Vec2{float(cosine(facing)), float(sine(facing))};
      }
      position_sum[slot] = position_sum[slot] + at;
      if (terrain.valid()) {
        const int cell = terrain.index(at.x, at.y);
        s[SUM_HEIGHT] += double(terrain.elevation[cell]);
        switch (terrain.cover[cell]) {
        case FOREST: s[SUM_FOREST] += 1; break;
        case BRUSH: s[SUM_BRUSH] += 1; break;
        case FORD:
        case WATER: s[SUM_WADING] += 1; break;
        default: break;
        }
      }
      // Vector2.dot in float32, then minf / maxf in double.
      const Vec2 lateral_axis = laterals[slot];
      const float lateral = at.x * lateral_axis.x + at.y * lateral_axis.y;
      s[SUM_LATERAL_MIN] = minimum(s[SUM_LATERAL_MIN], double(lateral));
      s[SUM_LATERAL_MAX] = maximum(s[SUM_LATERAL_MAX], double(lateral));
    }
    for (int slot = 0; slot < slots; ++slot) {
      double *s = sums.data() + size_t(slot) * fields;
      s[SUM_POSITION_X] = position_sum[slot].x;
      s[SUM_POSITION_Y] = position_sum[slot].y;
      s[SUM_FACING_X] = facing_sum[slot].x;
      s[SUM_FACING_Y] = facing_sum[slot].y;
    }
    std::copy(sums.begin(), sums.end(), out);
  }

  // Morale.tick after the group losses (Morale._group_losses, `losses` per slot): odds and collapse of the sides, the
  // pass over the fighters with the flight and the rally, then the panic of the new flights.
  void check(const double *losses, const int64_t starting[2], double arena_width, bool grouped, double cell_size,
             Result &result) {
    result = Result{};
    cell = cell_size;
    arena = arena_width;
    grids_ready = false;
    const int k = kinds();
    leaders[0].clear();
    leaders[1].clear();
    for (int row = 0; row < count; ++row) {
      if (i(I_DEAD, row) || i(I_GONE, row) || i(I_FLEEING, row))
        continue;
      const int side = int(i(I_SIDE, row));
      result.active[side] += 1;
      if (i(I_LEADER, row) || i(I_HERO, row))
        leaders[side].push_back(positions[row]);
    }
    bool collapsed[2], bad[2], very_bad[2];
    double recoveries[2];
    for (int side = 0; side < 2; ++side) {
      const double friends = result.active[side];
      const double enemies = maximum(p(morale::MORALE_OPPONENT_FLOOR), double(result.active[1 - side]));
      collapsed[side] = friends <= double(starting[side]) * p(morale::MORALE_FORCE_FLEE_START_SHARE) &&
                        friends < enemies * p(morale::MORALE_FORCE_FLEE_ENEMY_SHARE) &&
                        double(starting[side]) > p(morale::MORALE_FORCE_FLEE_MIN_START);
    }
    for (int side = 0; side < 2; ++side) {
      const double odds = double(result.active[side]) /
                          maximum(p(morale::MORALE_OPPONENT_FLOOR), double(result.active[1 - side]));
      bad[side] = odds < p(morale::MORALE_BAD_ODDS);
      very_bad[side] = odds < p(morale::MORALE_VERY_BAD_ODDS);
      recoveries[side] = odds > p(morale::MORALE_STRONG_ODDS) ? p(morale::MORALE_STRONG_RECOVERY)
                         : odds > p(morale::MORALE_EVEN_ODDS) ? p(morale::MORALE_EVEN_RECOVERY)
                                                              : p(morale::MORALE_WEAK_RECOVERY);
    }
    routed.clear();
    for (int row = 0; row < count; ++row) {
      if (i(I_DEAD, row) || i(I_GONE, row) || i(I_HERO, row))
        continue;
      if (i(I_MORALE_IMMUNE, row) || i(I_COMPANION, row))
        continue;
      const int side = int(i(I_SIDE, row));
      const int64_t kind = i(I_GROUP_KIND, row);
      const int slot = grouped && kind >= 0 && kind < k ? side * k + int(kind) : -1;
      if (i(I_FLEEING, row)) {
        if (rout_step(row, side, collapsed[side], slot >= 0, result) && slot >= 0)
          rally_into(int(i(I_COMMAND, row)) * k + int(kind), result);
        continue;
      }
      double &morale = r(R_MORALE, row);
      if (bad[side])
        morale -= p(morale::MORALE_BAD_ODDS_LOSS);
      if (very_bad[side])
        morale -= p(morale::MORALE_VERY_BAD_ODDS_LOSS);
      if (slot >= 0)
        morale -= losses[slot];
      const double base = r(R_BASE_MORALE, row);
      const double level = minimum(base, morale + recoveries[side]);
      morale = level;
      int64_t &wavering = i(I_WAVERING, row);
      if (wavering) {
        if (level >= base * p(morale::MORALE_STEADY_SHARE))
          wavering = 0;
      } else if (level < base * p(morale::MORALE_WAVER_SHARE)) {
        wavering = 1;
        if (!i(I_WAVER_NOTICED, row)) {
          i(I_WAVER_NOTICED, row) = 1;
          notice(row, WAVERED, result);
        }
      }
      const bool collapse = collapsed[side] && !i(I_LEADER, row);
      if (level <= 0.0 || collapse) {
        i(I_FLEEING, row) = 1;
        wavering = 0;
        // The flight starts from nothing; a deep rout (a heavy blow) takes longer to recover from, up to a limit.
        morale = clamp(morale, -base * p(morale::MORALE_RALLY_SHARE), 0.0);
        notice(row, FLED, result);
        routed.push_back(row);
      }
    }
    panic();
  }

private:
  // Morale cells (Morale.CELL): Vector2i(floori(x / CELL), floori(y / CELL)) as one key.
  using Cells = std::unordered_map<int64_t, std::vector<int>>;
  using Points = std::unordered_map<int64_t, std::vector<Vec2>>;
  std::vector<double> sums;
  std::vector<Vec2> position_sum, facing_sum;
  std::vector<Vec2> leaders[2];
  std::vector<int> routed;
  Cells pursuers[2];
  Points routers[2];
  std::unordered_map<int64_t, bool> near[2];
  double cell = 150.0, arena = 0; // Morale.CELL and battle.arena_size.x of the current check.
  bool grids_ready = false;

  double p(morale::Parameter n) const { return parameters[n]; }
  double &r(R f, int row) { return reals[int(f) * capacity + row]; }
  int64_t &i(I f, int row) { return integers[int(f) * capacity + row]; }
  // GDScript's minf, maxf and clampf (Godot's MIN, MAX and CLAMP), operand order included.
  static double minimum(double a, double b) { return a < b ? a : b; }
  static double maximum(double a, double b) { return a > b ? a : b; }
  static double clamp(double v, double low, double high) { return v < low ? low : (v > high ? high : v); }
  static float distance(Vec2 a, Vec2 b) { return (a - b).length(); } // a.distance_to(b), float32
  int unit_class(bool mounted, bool ranged, bool anti_cavalry) const {
    if (mounted)
      return int(ranged ? p(morale::AI_CLASS_HORSE_ARCHER) : p(morale::AI_CLASS_CAVALRY));
    if (ranged)
      return int(p(morale::AI_CLASS_ARCHER));
    return int(anti_cavalry ? p(morale::AI_CLASS_SPEAR) : p(morale::AI_CLASS_FOOT));
  }
  static int64_t key(int64_t x, int64_t y) { return int64_t((uint64_t(x) << 32) ^ uint64_t(uint32_t(y))); }
  int64_t cell_of(Vec2 at, int dx = 0, int dy = 0) const {
    return key(int64_t(std::floor(double(at.x) / cell)) + dx, int64_t(std::floor(double(at.y) / cell)) + dy);
  }
  void notice(int row, Notice kind, Result &result) const {
    result.notices.push_back(row);
    result.notices.push_back(kind);
  }
  void rally_into(int code, Result &result) const {
    for (int32_t known : result.rallied)
      if (known == code)
        return;
    result.rallied.push_back(code);
  }

  // Morale._side_grids, built on the first question: rows of the live fighters (not dead or gone) of each side.
  void build_grids() {
    pursuers[0].clear();
    pursuers[1].clear();
    for (int row = 0; row < count; ++row) {
      if (i(I_DEAD, row) || i(I_GONE, row))
        continue;
      pursuers[i(I_SIDE, row)][cell_of(positions[row])].push_back(row);
    }
    grids_ready = true;
  }

  // Morale._pursued: a ready enemy (not fleeing) within MORALE_PURSUIT_RADIUS.
  bool pursued(const Cells &enemies, Vec2 at) {
    const int64_t cx = int64_t(std::floor(double(at.x) / cell)), cy = int64_t(std::floor(double(at.y) / cell));
    for (int dx = -1; dx <= 1; ++dx)
      for (int dy = -1; dy <= 1; ++dy) {
        const auto bucket = enemies.find(key(cx + dx, cy + dy));
        if (bucket == enemies.end())
          continue;
        for (int row : bucket->second)
          if (!i(I_FLEEING, row) && double(distance(positions[row], at)) < p(morale::MORALE_PURSUIT_RADIUS))
            return true;
      }
    return false;
  }

  // Morale._rout_step: a fleeing fighter recovers unless pursued and turns back once he has recovered enough (only
  // into a group). True when he rallied.
  bool rout_step(int row, int side, bool collapsed, bool grouped, Result &result) {
    if (double(i(I_RALLIES, row)) >= p(morale::MORALE_RALLY_LIMIT))
      return false;
    const Vec2 at = positions[row];
    if (!grids_ready)
      build_grids();
    if (pursued(pursuers[1 - side], at))
      return false;
    double recovery = p(morale::MORALE_ROUT_RECOVERY);
    for (Vec2 leader : leaders[side])
      if (double(distance(leader, at)) < p(morale::MORALE_RALLY_LEADER_RADIUS)) {
        recovery += p(morale::MORALE_RALLY_LEADER_BONUS);
        break;
      }
    double &morale = r(R_MORALE, row);
    const double base = r(R_BASE_MORALE, row);
    morale = minimum(base, morale + recovery);
    if (morale < base * p(morale::MORALE_RALLY_SHARE) || collapsed || !grouped)
      return false;
    if (double(at.x) < p(morale::MORALE_RALLY_EDGE) || double(at.x) > arena - p(morale::MORALE_RALLY_EDGE))
      return false;
    i(I_FLEEING, row) = 0;
    i(I_WAVERING, row) = 1;
    i(I_RALLIES, row) += 1;
    notice(row, RALLIED, result);
    return true;
  }

  // Morale._panic: every new flight costs the ready friends within MORALE_PANIC_RADIUS MORALE_PANIC_LOSS, at most
  // MORALE_PANIC_CAP per fighter and check, fugitive after fugitive in the reference's order.
  void panic() {
    if (routed.empty())
      return;
    for (int side = 0; side < 2; ++side) {
      routers[side].clear();
      near[side].clear();
    }
    for (int row : routed) {
      const Vec2 at = positions[row];
      const int side = int(i(I_SIDE, row));
      routers[side][cell_of(at)].push_back(at);
      for (int dx = -1; dx <= 1; ++dx)
        for (int dy = -1; dy <= 1; ++dy)
          near[side][cell_of(at, dx, dy)] = true;
    }
    const double cap = p(morale::MORALE_PANIC_CAP);
    for (int row = 0; row < count; ++row) {
      if (i(I_DEAD, row) || i(I_GONE, row) || i(I_FLEEING, row) || i(I_HERO, row))
        continue;
      const int side = int(i(I_SIDE, row));
      const Vec2 at = positions[row];
      if (near[side].find(cell_of(at)) == near[side].end())
        continue;
      if (i(I_MORALE_IMMUNE, row) || i(I_COMPANION, row))
        continue;
      double taken = 0.0;
      double &morale = r(R_MORALE, row);
      for (int dx = -1; dx <= 1; ++dx)
        for (int dy = -1; dy <= 1; ++dy) {
          const auto bucket = routers[side].find(cell_of(at, dx, dy));
          if (bucket == routers[side].end())
            continue;
          for (Vec2 from : bucket->second) {
            if (taken >= cap)
              break;
            if (double(distance(at, from)) > p(morale::MORALE_PANIC_RADIUS))
              continue;
            const double loss = minimum(p(morale::MORALE_PANIC_LOSS), cap - taken);
            taken += loss;
            morale -= loss;
          }
        }
    }
  }
};

} // namespace iron::battle
