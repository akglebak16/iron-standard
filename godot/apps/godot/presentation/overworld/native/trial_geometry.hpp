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

inline std::vector<Patch> build_chunk(Geography geography, ChunkKey key, bool illustrated) {
  const float left = float(key.x * chunk_size);
  const float top = float(key.y * chunk_size);
  std::vector<Patch> output;
  const auto append = [&](Paint paint, Polygon points) {
    points = clip(std::move(points), key);
    if (points.size() >= 3)
      output.push_back({paint, std::move(points)});
  };

  append(Paint::Sea, rectangle(left, top, left + chunk_size, top + chunk_size));
  constexpr int stride = 16;
  for (int i = 0; i < chunk_size; i += stride) {
    float x = left + i, r = x + stride;
    float a = coast_y(x), b = coast_y(r);
    append(Paint::Shore, {{x,0},{r,0},{r,b},{x,a}});
    append(Paint::Land, {{x,0},{r,0},{r,b-5},{x,a-5}});
  }
  for (int i = 0; i < chunk_size; i += stride) {
    float y = top + i, b = y + stride;
    float a = river_x(y), z = river_x(b);
    float wa = 5 + y * 0.017f, wb = 5 + b * 0.017f;
    const auto ribbon = [&](Paint paint, float m) {
      append(paint, {{a-wa-m,y},{a+wa+m,y},{z+wb+m,b},{z-wb-m,b}});
    };
    ribbon(Paint::Shore, 2.5f);
    ribbon(Paint::River, 0);
  }
  for (int i = 0; i < chunk_size; i += stride) {
    float x = left + i, r = x + stride;
    append(Paint::Sea, {{x,coast_y(x)},{r,coast_y(r)},{r,rows*chunk_size},{x,rows*chunk_size}});
  }
  // Offshore skerries share the material sequence of the mainland coastline.
  for(int island=0;island<8;++island) {
    float cx=245+island*284+75*terrain_hash(island,0,17);
    float cy=coast_y(cx)+66+102*terrain_hash(island,2,91);
    float width=20+46*terrain_hash(island,1,19);
    if(cx+width<left || cx-width>left+chunk_size || cy+width<top || cy-width>top+chunk_size) continue;
    for(int band=0;band<2;++band) {
      for(int i=0;i<16;++i) {
        auto corner=[&](int v) {
          float angle=(v%16)*.3926991f;
          float radius=width*(.73f+.27f*terrain_hash(v%16,island,484))-band*4;
          return Point{cx+radius*std::cos(angle),cy+.47f*radius*std::sin(angle)-.16f*radius*std::cos(angle)};
        };
        append(band==0?Paint::Shore:Paint::Land,{{cx,cy},corner(i),corner(i+1)});
      }
    }
  }
  const auto road = [&](float from, float to, int route) {
    for (int i = 0; i < chunk_size; i += stride) {
      float x = std::max(from,left+i), r = std::min(to,left+i+stride);
      if (x >= r) continue;
      auto axis=[route](float at){return route==0?road_y(at):side_road_y(at,route==2);};
      float a = axis(x), b = axis(r);
      const auto ribbon = [&](Paint paint, float width) {
        append(paint, {{x,a-width},{r,b-width},{r,b+width},{x,a+width}});
      };
      float width=(route==0?7.f:3.3f)+1.4f*terrain_noise(x,114,80,71);
      ribbon(Paint::Verge, width+1.6f);
      ribbon(Paint::Road, width);
      if (illustrated && route==0) {
        // The exposed crown narrows on poorly worn sections of the trunk.
        float crown=width*(.37f+.18f*terrain_noise(x,61,115,87));
        ribbon(Paint::Shore,crown);
      }
    }
  };
  road(680,925,1);
  road(1460,1750,2);
  road(west_gate, west_bank,0);
  road(east_bank, east_gate,0);
  if (geography.bridge && !illustrated) {
    append(Paint::DeckEdge, rectangle(west_bank, crossing_y - 13, east_bank, crossing_y + 13));
    append(Paint::Deck, rectangle(west_bank, crossing_y - 8, east_bank, crossing_y + 8));
  }
  return output;
}
} // namespace iron::overworld
