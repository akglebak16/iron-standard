#pragma once
#include "trial_geometry.hpp"

namespace iron::overworld {
enum class Illustration { Ridge, Wood, Hill, Town, Village, Company, Spur, Peak, Saddle, Copse, Trees, Fields, Range, Summit, Pasture, Bluff };
struct Landmark { Illustration kind; float x, y, width; };

inline std::vector<Landmark> landmarks(ChunkKey key) {
  std::vector<Landmark> pieces;
  auto place = [&](Illustration kind, float x, float y, float width) {
    if (int(x) / chunk_size != key.x || int(y) / chunk_size != key.y) return;
    const float footprint=width*.37f;
    if (y>std::min({coast_y(x),coast_y(x-footprint),coast_y(x+footprint)})-4) return;
    pieces.push_back({kind,x,y,width});
  };
  // Build overlapping spurs up the gradient. The pass is a low saddle in the
  // same field used by the ground material and by the woodland distribution.
  for (int rank=0;rank<3;++rank) for (int i=0;i<10;++i) {
    float x=1150+i*150.f+rank*38;
    float y=ridge_axis(x)+(rank-1)*82+37*std::sin(i*.91f+rank);
    float strength=massif(x,y);
    if(strength<.13f || std::abs(x-river_x(y))<144 || std::abs(x-1750)<81) continue;
    const float variation=terrain_hash(i,rank,91);
    auto peak=variation>.5f ? Illustration::Range : Illustration::Summit;
    if(rank==0 && variation>.65f) peak=Illustration::Saddle;
    if(rank==2 || strength<.28f) peak=variation<.55f ? Illustration::Spur : Illustration::Bluff;
    float pass_clearance=2*(std::abs(x-1750)-34);
    place(peak,x,y,std::min(pass_clearance,145+strength*(rank==2?158:270)+58*variation));
  }
  // Jitter a world lattice once per chunk. Thresholding the continuous habitat
  // field gives shared forest margins across chunk boundaries.
  constexpr int spacing=40;
  for(int j=key.y*8;j<(key.y+1)*8;++j) for(int i=key.x*8;i<(key.x+1)*8;++i) {
    float x=(i+.12f+.76f*terrain_hash(i,j,4))*spacing;
    float y=(j+.12f+.76f*terrain_hash(i,j,5))*spacing;
    float w=woodland(x,y), h=massif(x,y), r=terrain_hash(i,j,19);
    if(y>coast_y(x)-26 || std::abs(x-river_x(y))<40 ||
       std::abs(y-road_y(x))<46 || h>.67f ||
       (x>=680 && x<=925 && std::abs(y-side_road_y(x,false))<33) ||
       (x>=1460 && x<=1750 && std::abs(y-side_road_y(x,true))<36) ||
       (x>260 && x<625 && std::abs(y-road_y(west_gate))<145) ||
       (x>1880 && x<2110 && std::abs(y-road_y(east_gate))<85)) continue;
    if(w>.59f && r<(w-.48f)*2.9f)
      place(w>.70f?Illustration::Wood:Illustration::Copse,x,y,36+62*w+22*r);
    else if(w>.47f && r>.92f)
      place(Illustration::Trees,x,y,31+17*w);
    else if(h>.14f && h<.48f && r>.89f)
      place(Illustration::Bluff,x,y,64+140*h);
    else if(w<.48f && r>.967f && relief(x,y)>.19f && std::abs(y-road_y(x))>76)
      place(i%3?Illustration::Pasture:Illustration::Bluff,x,y,68+82*r);
  }
  // Project the illustrated gate onto the simulation endpoint. Both anchors are
  // measured inside the trimmed atlas rectangle (town 480x405, village 444x271).
  place(Illustration::Town,west_gate-(.90f-.5f)*352,
        road_y(west_gate)+(1.f-.89f)*352*405/480,352);
  place(Illustration::Village,east_gate-(.21f-.5f)*157,
        road_y(east_gate)+(1.f-.90f)*157*271/444,157);
  place(Illustration::Fields,east_gate+120,road_y(east_gate)+22,120);
  place(Illustration::Fields,949,540,112);
  place(Illustration::Village,922,537,103);
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
