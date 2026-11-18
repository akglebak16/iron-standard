#pragma once

#include <algorithm>
#include <cstdint>
#include <cmath>
#include "region_terrain.hpp"

namespace iron::overworld {
struct Point {
  float x;
  float y;
};

inline constexpr int chunk_size = 320;
inline constexpr int columns = 8;
inline constexpr int rows = 5;
inline constexpr float crossing_y = 720;
inline constexpr float west_bank = 1238;
inline constexpr float east_bank = 1322;
inline constexpr float west_gate = 600;
inline constexpr float east_gate = 1970;

inline float base_road(float x) {
  const float offset = x - std::clamp(x, west_bank, east_bank);
  return crossing_y + 63 * std::sin(offset / 151) + 26 * std::sin(offset / 59)
         + 28*(terrain_noise(x,410,120,15)-.5f)*std::min(std::abs(offset)/80,1.f);
}

inline float coast_y(float x) {
  // Two resistant headlands enclose the bay. Lower-frequency erosion controls
  // the shore between them; the river outlet keeps its original catchment.
  float cape=(x-1510)/104, inlet=(x-1730)/116;
  float coast=216*std::exp(-cape*cape)-71*std::exp(-inlet*inlet)+1025 + 156 * std::sin(x / 201) + 78 * std::cos(x / 112)
      + 40*(terrain_noise(x,730,56,222)-.5f)
      + 13*(terrain_noise(x,730,19,301)-.5f);
  // At the mouth, two low banks meet an inlet across the direction of flow.
  float mouth=(x-river_x(1080))/94;
  float inlet_weight=std::exp(-mouth*mouth);
  return coast+(1080-coast)*inlet_weight;
}

// Select an alignment from bounded alternatives on each bank. The authored
// gates and bridge stay fixed. Cost integrates slope across the track as well
// as grades along it, avoiding steep traverses of the valley wall.
inline float road_envelope(float x,float start,float end) {
  float wave=std::sin(3.14159265f*std::clamp((x-start)/(end-start),0.f,1.f));
  return wave*wave;
}
inline float select_alignment(const RegionShape &region,float start,float end) {
  float best=1e9f, chosen=0;
  for (float offset : {-108.f,-72.f,-36.f,0.f,36.f,72.f,108.f}) {
    float cost=.003f*std::abs(offset);
    float previous=region.relief(start,base_road(start));
    for (int i=1;i<=24;++i) {
      float x=start+(end-start)*i/24;
      float y=base_road(x)+offset*road_envelope(x,start,end);
      float elevation=region.relief(x,y);
      cost+=8*std::abs(elevation-previous)+3*std::abs(region.relief(x,y+14)-region.relief(x,y-14));
      if(y>coast_y(x)-20) cost+=100;
      previous=elevation;
    }
    if(cost<best) { best=cost; chosen=offset; }
  }
  return chosen;
}
inline float road_y(float x,const RegionShape &region) {
  return base_road(x)+region.west_detour*road_envelope(x,west_gate,west_bank)
      +region.east_detour*road_envelope(x,east_bank,east_gate);
}
// Farm access and the saddle trail share their first tangent with the trunk.
inline float side_road_y(float x, bool pass, const RegionShape &region) {
  float from=pass?1460.f:680.f, to=pass?region.pass:925.f;
  if(pass && x>to) {
    float north=std::clamp((x-to)/175.f,0.f,1.f);
    return (region.ridge_axis(to)-55)*(1-north*north*(3-2*north))-8*north;
  }
  float t=std::clamp((x-from)/(to-from),0.f,1.f);
  float blend=t*t*(3-2*t);
  return (1-blend)*road_y(x,region)+blend*(pass?region.ridge_axis(to)-55:542.f)
      + 18*std::sin(t*7)*std::sin(t*3.14159f);
}

struct Geography {
  std::uint64_t world_id;
  std::uint64_t revision = 0;
  bool bridge = false;
  RegionShape region{};
};

// Simulation fixture for the standalone scene. The renderer receives copies.
class TrialWorld {
  Geography geography_{1};
  float company_x_ = west_gate;
  double hour_ = 12;

public:
  void set_region(RegionShape shape) {
    shape.west_detour=select_alignment(shape,west_gate,west_bank);
    shape.east_detour=select_alignment(shape,east_bank,east_gate);
    geography_.region=shape;
  }
  Geography snapshot() const { return geography_; }
  double hour() const { return hour_; }
  void set_hour(double value) { hour_ = value - 24 * std::floor(value / 24); }
  Point company() const { return {company_x_, road_y(company_x_,geography_.region)}; }

  bool set_bridge(bool open) {
    if (open == geography_.bridge)
      return false;
    geography_.bridge = open;
    ++geography_.revision;
    if (!open && company_x_ > west_bank && company_x_ < east_bank)
      company_x_ = company_x_ < (west_bank + east_bank) / 2 ? west_bank : east_bank;
    return true;
  }

  void advance(float seconds) {
    set_hour(hour_ + seconds / 45);
    const float target = geography_.bridge || company_x_ >= east_bank ? east_gate : west_bank;
    company_x_ = std::min(target, company_x_ + seconds * 140);
  }

  void reload() {
    // Reload the same geography and reset the trial company's movement.
    geography_ = {geography_.world_id + 1, 0, geography_.bridge, geography_.region};
    company_x_ = west_gate;
  }
};
} // namespace iron::overworld
