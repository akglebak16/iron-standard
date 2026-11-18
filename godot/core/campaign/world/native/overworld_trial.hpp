#pragma once

#include <algorithm>
#include <cstdint>

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

struct Geography {
  std::uint64_t world_id;
  std::uint64_t revision = 0;
  bool bridge = false;
};

// Simulation fixture for the standalone scene. The renderer receives copies.
class TrialWorld {
  Geography geography_{1};
  float company_x_ = west_gate;

public:
  Geography snapshot() const { return geography_; }
  Point company() const { return {company_x_, crossing_y}; }

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
