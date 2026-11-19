#pragma once
// Campaign world kernel (ADR-025): the threat-map stamp and the contact-pair search of the world step.
// Standalone C++: no engine headers, no clocks, files or mutable static state. The GDScript code in
// threat_map.gd and party_ai.gd stays the reference; every operation repeats its order and number types
// (double arithmetic, float32 grid cells and Vector2 lengths) so both backends give the same campaign.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace iron::campaign {

struct StampResult {
  std::vector<std::vector<float>> layers;
  int64_t stamped_cells = 0;
  int64_t sources = 0;
};

// threat_map.gd rebuild/_stamp: sources come in list order, each with the index of its faction layer
// (factions sorted by name on the GDScript side); a source without strength is skipped.
inline StampResult stamp_layers(const double *xs, const double *ys, const double *strengths,
                                const int32_t *layer, int count, int layer_count, int cols,
                                int rows, double cell, double radius) {
  StampResult out;
  out.layers.assign(static_cast<size_t>(layer_count),
                    std::vector<float>(static_cast<size_t>(cols) * rows, 0.0f));
  for (int k = 0; k < count; ++k) {
    const double strength = strengths[k];
    if (!(strength > 0.0) || layer[k] < 0 || layer[k] >= layer_count)
      continue;
    std::vector<float> &grid = out.layers[static_cast<size_t>(layer[k])];
    const double x = xs[k], y = ys[k];
    const int64_t c0 = std::max<int64_t>(0, static_cast<int64_t>(std::floor((x - radius) / cell)));
    const int64_t c1 = std::min<int64_t>(cols - 1, static_cast<int64_t>(std::floor((x + radius) / cell)));
    const int64_t r0 = std::max<int64_t>(0, static_cast<int64_t>(std::floor((y - radius) / cell)));
    const int64_t r1 = std::min<int64_t>(rows - 1, static_cast<int64_t>(std::floor((y + radius) / cell)));
    for (int64_t cy = r0; cy <= r1; ++cy) {
      const double dy = (static_cast<double>(cy) + 0.5) * cell - y;
      const int64_t row = cy * cols;
      for (int64_t cx = c0; cx <= c1; ++cx) {
        const double dx = (static_cast<double>(cx) + 0.5) * cell - x;
        const double d = std::sqrt(dx * dx + dy * dy);
        ++out.stamped_cells;
        if (d < radius) {
          float &v = grid[static_cast<size_t>(row + cx)];
          v = static_cast<float>(static_cast<double>(v) + strength * (1.0 - d / radius));
        }
      }
    }
    ++out.sources;
  }
  return out;
}

// party_ai.gd step: pairs (i < j) closer than `reach`, in the order of the reference double loop.
// Only geometry: flags, roster membership and hostility change during the contact phase and stay in GDScript.
inline std::vector<int32_t> contact_pairs(const double *xs, const double *ys, int count, double reach) {
  std::vector<int32_t> pairs;
  const float limit = static_cast<float>(reach);
  for (int i = 0; i < count; ++i) {
    const double ax = xs[i], ay = ys[i];
    for (int j = i + 1; j < count; ++j) {
      const double dx = ax - xs[j];
      if (std::fabs(dx) >= reach)
        continue;
      // Vector2(dx, ay - b.y).length(): float32 components, float32 square root
      const float fx = static_cast<float>(dx), fy = static_cast<float>(ay - ys[j]);
      if (!(std::sqrt(fx * fx + fy * fy) < limit))
        continue;
      pairs.push_back(i);
      pairs.push_back(j);
    }
  }
  return pairs;
}

} // namespace iron::campaign
