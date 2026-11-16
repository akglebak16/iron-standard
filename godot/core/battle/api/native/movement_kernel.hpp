#pragma once
#include "../../../../runtime/simulation/native/contact_solver.hpp"
#include "../../simulation/native/movement_parameters.hpp"
#include "../../simulation/native/unit_columns.hpp"
#include <functional>
#include <unordered_map>
namespace iron::battle {
// Sequential batch, yielding only at observable rule interactions.
class MovementKernel {
public:
  enum Reason { DONE, CHARGE, ATTACK, GONE };
  struct Result {
    int reason, unit, target;
  };
  struct Group {
    Vec2 center, lateral, forward;
    double direction;
    bool charge, backing;
  };
  std::vector<Vec2> positions, velocities, vectors, gaps, all_gaps;
  std::vector<Group> groups;
  std::vector<double> parameters;
  double *reals = nullptr;
  int64_t *integers = nullptr;
  int capacity = 0;
  double dt = 0, width = 0, height = 0, wall_x = INFINITY, wall_half = 0;
  std::function<double()> random;
  std::function<double(Vec2)> angle;

private:
  int cursor = 0, stage = 0, target = -1;
  Vec2 destination;
  double velocity_scale = 1, face = 0, distance = INFINITY;
  struct Cell {
    int x, y;
    std::vector<int> units;
  };
  std::vector<Cell> cells;
  std::unordered_map<int64_t, int> cell_map;
  std::vector<int64_t> slot_handles;
  std::vector<int> slot_rows;
  std::vector<int> locations;
  double &r(R f, int row) { return reals[int(f) * capacity + row]; }
  int64_t &i(I f, int row) { return integers[int(f) * capacity + row]; }
  Vec2 &v(V f, int row) { return vectors[int(f) * capacity + row]; }
  double p(Parameter f) const { return parameters[f]; }
  bool live(int row) { return row >= 0 && !i(I_DEAD, row) && !i(I_GONE, row); }
  int resolve(int64_t handle) {
    int64_t slot = (handle & 0xffffffffLL) - 1;
    if (handle <= 0 || slot < 0 || slot >= int64_t(slot_handles.size()) ||
        slot_handles[slot] != handle)
      return -1;
    int row = slot_rows[slot];
    return live(row) ? row : -1;
  }
  static Vec2 normalized(Vec2 a) {
    float d = a.length();
    return d == 0 ? a : a / d;
  }
  int cell(Vec2 at) {
    int x = int(std::floor(at.x / p(SPATIAL_CELL_SIZE))),
        y = int(std::floor(at.y / p(SPATIAL_CELL_SIZE)));
    int64_t key = int64_t((uint64_t(uint32_t(x)) << 32) | uint32_t(y));
    auto f = cell_map.find(key);
    if (f != cell_map.end())
      return f->second;
    int k = int(cells.size());
    cell_map[key] = k;
    cells.push_back({x, y, {}});
    return k;
  }
  void move(int row) {
    int c = cell(positions[row]), old = locations[row];
    if (c == old)
      return;
    auto &b = cells[old].units;
    b.erase(std::find(b.begin(), b.end(), row));
    cells[c].units.push_back(row);
    locations[row] = c;
  }
  int choose(int row, int previous) {
    Vec2 at = positions[row];
    int best = -1;
    double score = INFINITY;
    bool cavalry = i(I_MOUNTED, row) && r(R_ATTACK_RANGE, row) <= 0;
    auto consider = [&](int e) {
      if (!live(e) || i(I_SIDE, e) == i(I_SIDE, row))
        return;
      double d = (at - positions[e]).length();
      if (i(I_FLEEING, e))
        d *= p(TARGET_FLEE_DISTANCE_MULTIPLIER);
      if (cavalry && r(R_ATTACK_RANGE, e) > 0 && !i(I_MOUNTED, e))
        d *= p(CAVALRY_ARCHER_TARGET_MULTIPLIER);
      if (e == previous)
        d *= p(CURRENT_TARGET_MULTIPLIER);
      if (d < score || (d == score && (best < 0 || e < best))) {
        score = d;
        best = e;
      }
    };
    if (previous >= 0)
      consider(previous);
    double minimum = cavalry ? p(CAVALRY_ARCHER_TARGET_MULTIPLIER) : 1;
    for (const auto &c : cells) {
      if (c.units.empty())
        continue;
      double x = c.x * p(SPATIAL_CELL_SIZE), y = c.y * p(SPATIAL_CELL_SIZE);
      double dx = std::max({x - at.x, at.x - x - p(SPATIAL_CELL_SIZE), 0.0}),
             dy = std::max({y - at.y, at.y - y - p(SPATIAL_CELL_SIZE), 0.0});
      if (std::sqrt(dx * dx + dy * dy) * minimum > score + 1e-6)
        continue;
      for (int e : c.units)
        consider(e);
    }
    return best;
  }
  void plan(int row, const Group &g, Vec2 slot) {
    Vec2 at = positions[row], enemy = target >= 0 ? positions[target] : Vec2{};
    double sd = (at - slot).length();
    distance = target >= 0 ? (at - enemy).length() : INFINITY;
    double reach = r(R_COLLISION_RADIUS, row) +
                   (target >= 0 ? r(R_COLLISION_RADIUS, target) : 0) +
                   r(R_MELEE_REACH, row);
    int mode = SLOT;
    bool mounted = i(I_MOUNTED, row);
    double range = r(R_ATTACK_RANGE, row);
    if (g.backing && sd > p(AI_BACKING_SLOT_DISTANCE)) {
    } else if (range > 0) {
      if (mounted) {
        if (target >= 0 &&
            (g.charge || distance < range * p(AI_MOUNTED_SKIRMISH_TRIGGER)))
          mode = SKIRMISH;
      } else if (target >= 0 && distance < reach + p(AI_ARCHER_MELEE_BUFFER))
        mode = MELEE;
      else if (target >= 0 && g.charge)
        mode = SHOOT;
      else if (target >= 0 && distance < range &&
               sd < p(AI_ARCHER_SLOT_DISTANCE))
        mode = SHOOT_SLOT;
    } else if (target >= 0) {
      if (g.charge)
        mode = MELEE;
      else if (distance < p(mounted ? AI_MOUNTED_ENGAGE_DISTANCE
                                    : AI_FOOT_ENGAGE_DISTANCE) &&
               (enemy - slot).length() < p(mounted ? AI_MOUNTED_LEASH_DISTANCE
                                                   : AI_FOOT_LEASH_DISTANCE))
        mode = MELEE;
    }
    destination = slot;
    face = sd < p(AI_SLOT_FACE_DISTANCE) ? g.direction : angle(slot - at);
    velocity_scale = 1;
    if (mode == MELEE) {
      face = angle(enemy - at);
      destination = distance > reach ? enemy : at;
    } else if (mode == SHOOT || mode == SHOOT_SLOT) {
      face = angle(enemy - at);
      if (mode == SHOOT)
        destination =
            distance > range * p(AI_SHOOT_APPROACH_RANGE) ? enemy : at;
    } else if (mode == SKIRMISH) {
      face = angle(enemy - at);
      Vec2 away = normalized(at - enemy), side = {-away.y, away.x};
      double sign = i(I_ID, row) % 2 ? 1 : -1;
      if (distance < range * p(AI_SKIRMISH_CLOSE_RANGE))
        destination = at + away * p(AI_SKIRMISH_BACK_OFFSET) +
                      side * p(AI_SKIRMISH_LATERAL_OFFSET) * sign;
      else if (distance > range * p(AI_SKIRMISH_APPROACH_RANGE))
        destination = enemy;
      else
        destination = at + side * p(AI_SKIRMISH_ORBIT_OFFSET) * sign;
      double margin = p(AI_SKIRMISH_EDGE_MARGIN);
      if (destination.x < margin || destination.x > width - margin ||
          destination.y < margin || destination.y > height - margin)
        destination = Vec2{float(width), float(height)} * .5;
      velocity_scale = p(AI_SKIRMISH_SPEED_MULTIPLIER);
    }
    i(I_MODE, row) = mode;
    v(V_PLAN_DESTINATION, row) = destination;
    r(R_PLAN_FACE, row) = face;
    r(R_PLAN_SPEED, row) = velocity_scale;
    r(R_PLAN_DISTANCE, row) = distance;
  }
  Vec2 route(int row, Vec2 dest) {
    if (!std::isfinite(wall_x))
      return dest;
    Vec2 at = positions[row];
    double side = at.x < wall_x ? -1 : 1;
    if (side == (dest.x < wall_x ? -1 : 1))
      return dest;
    double spread = double((i(I_ID, row) * int64_t(p(SIEGE_ROUTE_ID_FACTOR))) %
                           int64_t(p(SIEGE_ROUTE_ID_SPREAD)));
    if (gaps.empty()) {
      Vec2 nearest;
      double cost = INFINITY;
      for (Vec2 gap : all_gaps) {
        double candidate =
            std::abs((double(gap.x) + gap.y) * .5 - at.y) + spread;
        if (candidate < cost) {
          cost = candidate;
          nearest = gap;
        }
      }
      double radius = r(R_COLLISION_RADIUS, row);
      return {float(wall_x + side * (wall_half + radius + 2.0)),
              float(std::min(std::max(double(at.y), double(nearest.x) + radius),
                             double(nearest.y) - radius))};
    }
    Vec2 best;
    double cost = INFINITY;
    for (Vec2 gap : gaps) {
      double center = (double(gap.x) + gap.y) * .5,
             c = std::abs(center - at.y) +
                 std::abs(center - dest.y) * p(SIEGE_ROUTE_DESTINATION_WEIGHT) +
                 spread;
      if (c < cost) {
        cost = c;
        best = gap;
      }
    }
    double center = (double(best.x) + best.y) * .5,
           half = (double(best.y) - best.x) * .5 - r(R_COLLISION_RADIUS, row);
    double entry =
               std::min(std::max(double(at.y), center - half), center + half),
           d = std::abs(at.x - wall_x);
    if (d < wall_half + p(SIEGE_ROUTE_CROSS_READY_DISTANCE) &&
        std::abs(at.y - center) < half)
      return {float(wall_x - side * p(SIEGE_ROUTE_CROSS_DISTANCE)),
              float(entry)};
    return {float(wall_x + side * (wall_half + p(SIEGE_ROUTE_APPROACH_OFFSET))),
            float(d < p(SIEGE_ROUTE_CENTERING_DISTANCE) ? center : entry)};
  }

public:
  void begin() {
    cursor = stage = 0;
    for (auto &c : cells)
      c.units.clear();
    int64_t slots = 0;
    for (int row = 0; row < int(positions.size()); ++row)
      slots = std::max(slots, i(I_UNIT_HANDLE, row) & 0xffffffffLL);
    slot_handles.resize(slots);
    slot_rows.resize(slots);
    std::fill(slot_handles.begin(), slot_handles.end(), 0);
    locations.resize(positions.size());
    for (int row = 0; row < int(positions.size()); ++row) {
      int c = cell(positions[row]);
      locations[row] = c;
      cells[c].units.push_back(row);
      int64_t handle = i(I_UNIT_HANDLE, row),
              slot = (handle & 0xffffffffLL) - 1;
      slot_handles[slot] = handle;
      slot_rows[slot] = row;
    }
  }
  Result run() {
    for (; cursor < int(positions.size()); ++cursor) {
      int row = cursor;
      if (stage == 0) {
        if (!live(row) || i(I_HERO, row))
          continue;
        r(R_CHARGE_COOLDOWN, row) -= dt;
        r(R_ATTACK_COOLDOWN, row) -= dt;
        const Group &g = groups[i(I_SIDE, row) * 3 + i(I_GROUP_KIND, row)];
        Vec2 slot = g.center + g.lateral * v(V_SLOT_OFFSET, row).x +
                    g.forward * v(V_SLOT_OFFSET, row).y;
        slot.x = std::clamp(slot.x, float(p(SLOT_EDGE)),
                            float(width - p(SLOT_EDGE)));
        slot.y = std::clamp(slot.y, float(p(SLOT_EDGE)),
                            float(height - p(SLOT_EDGE)));
        destination = slot;
        velocity_scale = 1;
        face = r(R_FACING, row);
        target = -1;
        distance = INFINITY;
        if (i(I_FLEEING, row)) {
          destination = {float(i(I_SIDE, row) == 1
                                   ? width + p(FLEE_DESTINATION_PADDING)
                                   : -p(FLEE_DESTINATION_PADDING)),
                         positions[row].y};
          velocity_scale = p(FLEE_SPEED_MULTIPLIER);
        } else {
          r(R_TARGET_TIMER, row) -= dt;
          target = resolve(i(I_TARGET_HANDLE, row));
          if (target >= 0 && i(I_SIDE, target) == i(I_SIDE, row))
            target = -1;
          if (r(R_TARGET_TIMER, row) <= 0 ||
              (i(I_TARGET_HANDLE, row) != 0 && target < 0)) {
            r(R_TARGET_TIMER, row) =
                p(RETARGET_MIN_SECONDS) + random() * p(RETARGET_RANDOM_SECONDS);
            target = choose(row, target);
            i(I_TARGET_HANDLE, row) =
                target >= 0 ? i(I_UNIT_HANDLE, target) : 0;
          }
          plan(row, g, slot);
          if (i(I_MODE, row) == MELEE && target >= 0 && i(I_MOUNTED, row) &&
              r(R_ATTACK_RANGE, row) <= 0 && r(R_CHARGE_COOLDOWN, row) <= 0 &&
              velocities[row].length() > p(CHARGE_MIN_SPEED) &&
              distance < r(R_COLLISION_RADIUS, row) +
                             r(R_COLLISION_RADIUS, target) +
                             r(R_MELEE_REACH, row) + p(CHARGE_EXTRA_REACH)) {
            r(R_FACING, row) = face;
            stage = 1;
            return {CHARGE, row, target};
          }
        }
        stage = 2;
      }
      if (stage == 1) {
        if (destination.x != positions[row].x ||
            destination.y != positions[row].y)
          destination = positions[target];
        move(target);
        stage = 2;
      }
      if (stage == 2) {
        destination = route(row, destination);
        Vec2 delta = destination - positions[row], desired;
        double d = delta.length(), speed = r(R_SPEED, row) * velocity_scale;
        if (d > p(ARRIVAL_DISTANCE) && speed > 0)
          desired = delta / d * std::min(speed, d * p(ARRIVAL_BRAKE));
        float weight =
            float(std::min(1.0, p(i(I_MOUNTED, row) ? HORSE_STEERING_RATE
                                                    : FOOT_STEERING_RATE) *
                                    dt));
        velocities[row] =
            velocities[row] + (desired - velocities[row]) * weight;
        if (velocities[row].squared() > 0)
          r(R_FACING, row) = angle(velocities[row]);
        stage = 3;
        if (i(I_FLEEING, row)) {
          r(R_FACING, row) = angle(velocities[row]);
          if (positions[row].x < -p(FLEE_EXIT_PADDING) ||
              positions[row].x > width + p(FLEE_EXIT_PADDING))
            return {GONE, row, -1};
        } else {
          r(R_FACING, row) = face;
          if (live(row) && !i(I_HERO, row)) {
            bool ready = target >= 0 && r(R_ATTACK_COOLDOWN, row) <= 0;
            bool melee = ready && i(I_MODE, row) == MELEE &&
                         distance <= r(R_COLLISION_RADIUS, row) +
                                         r(R_COLLISION_RADIUS, target) +
                                         r(R_MELEE_REACH, row) &&
                         r(R_AI_WINDUP, row) < 0;
            bool shoot =
                ready && r(R_ATTACK_RANGE, row) > 0 &&
                distance < r(R_ATTACK_RANGE, row) &&
                (i(I_MODE, row) == SKIRMISH ||
                 ((i(I_MODE, row) == SHOOT || i(I_MODE, row) == SHOOT_SLOT) &&
                  velocities[row].length() < p(SHOOT_MOVE_SPEED_LIMIT)));
            bool wind =
                r(R_AI_WINDUP, row) >= 0 && r(R_AI_WINDUP, row) - dt < 0;
            if (melee || shoot || wind)
              return {ATTACK, row, target};
            if (r(R_AI_WINDUP, row) >= 0)
              r(R_AI_WINDUP, row) -= dt;
          }
        }
      }
      positions[row] = positions[row] + velocities[row] * dt;
      move(row);
      stage = 0;
    }
    return {DONE, -1, -1};
  }
};
} // namespace iron::battle
