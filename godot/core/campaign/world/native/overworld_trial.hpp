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

inline float road_y(float x) {
  const float offset = x - std::clamp(x, west_bank, east_bank);
  return crossing_y + 63 * std::sin(offset / 151) + 26 * std::sin(offset / 59)
         + 28*(terrain_noise(x,410,120,15)-.5f)*std::min(std::abs(offset)/80,1.f);
}

inline float coast_y(float x) {
  return 1025 + 156 * std::sin(x / 201) + 78 * std::cos(x / 112)
      + 40*(terrain_noise(x,730,56,222)-.5f)
      + 13*(terrain_noise(x,730,19,301)-.5f);
}

inline float river_x(float y) {
  const float offset = y - std::clamp(y, crossing_y - 30, crossing_y + 30);
  return 1280 + 66 * std::sin(offset / 117) + 18 * std::sin(offset / 48);
}

// Farm access and the saddle trail share their first tangent with the trunk.
inline float side_road_y(float x, bool pass) {
  float from=pass?1460.f:680.f, to=pass?1750.f:925.f;
  float t=std::clamp((x-from)/(to-from),0.f,1.f);
  float blend=t*t*(3-2*t);
  return (1-blend)*road_y(x)+blend*(pass?ridge_axis(to)+58:542.f)
      + 18*std::sin(t*7)*std::sin(t*3.14159f);
}

struct Geography {
  std::uint64_t world_id;
  std::uint64_t revision = 0;
  bool bridge = false;
};

// Simulation fixture for the standalone scene. The renderer receives copies.
class TrialWorld {
  Geography geography_{1};
  float company_x_ = west_gate;
  double hour_ = 12;

public:
  Geography snapshot() const { return geography_; }
  double hour() const { return hour_; }
  void set_hour(double value) { hour_ = value - 24 * std::floor(value / 24); }
  Point company() const { return {company_x_, road_y(company_x_)}; }

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
    geography_ = {geography_.world_id + 1, 0, geography_.bridge};
    company_x_ = west_gate;
  }
};
} // namespace iron::overworld
