#pragma once

#include "../../../../../core/campaign/world/native/overworld_trial.hpp"
#include <array>
#include <utility>
#include <vector>

namespace iron::overworld {
enum class Paint { Sea, Shore, Land, River, Verge, Road, DeckEdge, Deck };

using Polygon = std::vector<Point>;

struct Patch {
  Paint paint;
  Polygon points;
};

struct ChunkKey {
  int x;
  int y;
};

inline Polygon clip(Polygon polygon, ChunkKey key) {
  // Clip all layers in world coordinates. Adjacent chunks sample the same edge.
  const std::array<float, 4> edges{
      float(key.x * chunk_size), float((key.x + 1) * chunk_size),
      float(key.y * chunk_size), float((key.y + 1) * chunk_size)};
  for (int side = 0; side < 4 && !polygon.empty(); ++side) {
    const auto coordinate = [side](Point point) { return side < 2 ? point.x : point.y; };
    const auto inside = [&](Point point) {
      return side % 2 == 0 ? coordinate(point) >= edges[side]
                           : coordinate(point) <= edges[side];
    };
    Polygon result;
    Point previous = polygon.back();
    for (Point current : polygon) {
      if (inside(previous) != inside(current)) {
        const float t = (edges[side] - coordinate(previous)) /
                        (coordinate(current) - coordinate(previous));
        result.push_back(side < 2
            ? Point{edges[side], previous.y + t * (current.y - previous.y)}
            : Point{previous.x + t * (current.x - previous.x), edges[side]});
      }
      if (inside(current))
        result.push_back(current);
      previous = current;
    }
    polygon = std::move(result);
  }
  return polygon;
}

inline Polygon rectangle(float x, float y, float right, float bottom) {
  return {{x, y}, {right, y}, {right, bottom}, {x, bottom}};
}

inline std::vector<Patch> build_chunk(Geography geography, ChunkKey key) {
  const float left = float(key.x * chunk_size);
  const float top = float(key.y * chunk_size);
  std::vector<Patch> output;
  const auto append = [&](Paint paint, Polygon points) {
    points = clip(std::move(points), key);
    if (points.size() >= 3)
      output.push_back({paint, std::move(points)});
  };

  append(Paint::Sea, rectangle(left, top, left + chunk_size, top + chunk_size));
  // Monotone coastline in X. Draw trapezoids so clipping preserves convexity.
  constexpr std::array<Point, 9> coast{{
      {0, 1070}, {320, 977}, {640, 1026}, {960, 1113}, {1280, 1048},
      {1600, 1215}, {1920, 1110}, {2240, 1220}, {2560, 1130}}};
  const Point a = coast[key.x];
  const Point b = coast[key.x + 1];
  append(Paint::Shore, {{a.x, 0}, {b.x, 0}, {b.x, b.y}, {a.x, a.y}});
  append(Paint::Land, {{a.x, 0}, {b.x, 0}, {b.x, b.y - 9}, {a.x, a.y - 9}});

  // Shared bank coordinates at each junction keep the segments continuous.
  constexpr std::array<Point, 7> river{{
      {1150, 0}, {1130, 240}, {1250, 430}, {1280, 650},
      {1280, 800}, {1210, 910}, {1280, 1048}}};
  constexpr std::array<float, 7> widths{{13, 18, 24, 31, 32, 33, 36}};
  for (std::size_t i = 1; i < river.size(); ++i) {
    const Point start = river[i - 1];
    const Point end = river[i];
    const auto ribbon = [&](Paint paint, float margin) {
      const float start_width = widths[i - 1] + margin;
      const float end_width = widths[i] + margin;
      append(paint, {{start.x - start_width, start.y}, {start.x + start_width, start.y},
                     {end.x + end_width, end.y}, {end.x - end_width, end.y}});
    };
    ribbon(Paint::Shore, 4);
    ribbon(Paint::River, 0);
  }

  const auto road = [&](float from, float to) {
    append(Paint::Verge, rectangle(from, crossing_y - 10, to, crossing_y + 10));
    append(Paint::Road, rectangle(from, crossing_y - 6, to, crossing_y + 6));
  };
  road(west_gate, west_bank);
  road(east_bank, east_gate);
  if (geography.bridge) {
    append(Paint::DeckEdge, rectangle(west_bank, crossing_y - 13, east_bank, crossing_y + 13));
    append(Paint::Deck, rectangle(west_bank, crossing_y - 8, east_bank, crossing_y + 8));
  }
  return output;
}
} // namespace iron::overworld
