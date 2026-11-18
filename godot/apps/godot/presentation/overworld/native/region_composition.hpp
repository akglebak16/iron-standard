#pragma once
#include "trial_geometry.hpp"

namespace iron::overworld {
enum class Illustration { Ridge, Wood, Hill, Town, Village, Company, Spur, Peak, Saddle, Copse, Trees, Fields };
struct Landmark { Illustration kind; float x, y, width; };

inline std::vector<Landmark> landmarks(ChunkKey key) {
  std::vector<Landmark> pieces;
  auto place = [&](Illustration kind, float x, float y, float width) {
    if (int(x) / chunk_size == key.x && int(y) / chunk_size == key.y)
      pieces.push_back({kind,x,y,width});
  };
  // Two connected arms of one ridge leave a saddle at x=1740.
  for (int i = 0; i < 12; ++i) {
    float x = 1380 + i * 92.f;
    if (i == 4 || i == 5) continue;
    float y = 385 + 75 * std::sin(i * .68f) + i * 8;
    place(i % 3 == 0 ? Illustration::Hill : Illustration::Spur, x - 54, y + 80, 195 + 40*std::cos(i));
    constexpr Illustration summits[] = {Illustration::Spur,Illustration::Saddle,Illustration::Peak,Illustration::Ridge};
    place(summits[i%4], x, y, 240 + 100 * std::sin(i * 1.3f));
  }
  // Each woodland has a dense interior and a broken outer edge.
  constexpr Point groves[] = {{310,360},{810,430},{1030,580},{1530,565},
      {2150,640},{530,890},{1630,860},{2310,930},{920,205},{1950,210}};
  for (const Point center : groves) {
    for (int i = 0; i < 15; ++i) {
      const float angle = i * 2.4f + center.x * .01f;
      const float radius = std::sqrt(float(i)) * 28;
      float x = center.x + radius * std::cos(angle);
      float y = center.y + radius * .55f * std::sin(angle);
      if (y > coast_y(x)-50 || std::abs(x-river_x(y)) < 110 ||
          std::abs(y-road_y(x)) < 65) continue;
      const auto kind = i < 5 ? Illustration::Wood : (i%3 ? Illustration::Copse : Illustration::Trees);
      place(kind,x,y,106 - 3*i + 23*std::cos(angle));
    }
  }
  // Project the illustrated gate onto the simulation endpoint. Both anchors are
  // measured inside the trimmed atlas rectangle (town 480x405, village 444x271).
  place(Illustration::Town,west_gate-(.90f-.5f)*352,
        road_y(west_gate)+(1.f-.89f)*352*405/480,352);
  place(Illustration::Village,east_gate-(.21f-.5f)*157,
        road_y(east_gate)+(1.f-.90f)*157*271/444,157);
  place(Illustration::Fields,east_gate+120,road_y(east_gate)+22,120);
  place(Illustration::Fields,west_gate-202,road_y(west_gate)-30,108);
  constexpr Point outskirts[] = {{670,640},{850,673},{730,827},{1520,704},
      {1840,610},{2050,788},{1160,885},{990,858},{490,605},{1680,932}};
  for (Point p : outskirts)
    if (std::abs(p.y-road_y(p.x))>20) place(Illustration::Trees,p.x,p.y,32+8*std::sin(p.x));
  place(Illustration::Spur,846,coast_y(846)-40,165);
  place(Illustration::Hill,422,939,118);
  constexpr Point skirts[] = {{1620,552},{1675,571},{2080,521},{2180,555},
      {679,391},{609,425},{831,823},{880,808},{1540,934},{1600,920},{2230,820}};
  for (Point p : skirts)
    place(Illustration::Spur,p.x,p.y,102+38*std::cos(p.x));
  return pieces;
}
} // namespace iron::overworld
