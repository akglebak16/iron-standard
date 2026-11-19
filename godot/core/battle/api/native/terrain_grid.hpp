#pragma once
// Terrain of the battlefield (TERRAIN.md 3.4, stage Р0б): the C++ reader of core/battle/model/terrain_grid.gd.
// One cover byte and one height byte per cell of `cell` field units, row-major, read in O(1). The index must match
// the GDScript one bit for bit (floor of x / cell, clamped to the edge cells); test_native_terrain_grid.gd checks it.
#include <algorithm>
#include <cmath>
#include <cstdint>

namespace iron::battle {

// TerrainGrid.Cover in core/battle/model/terrain_grid.gd: the byte stored per cell. Append, never reorder.
enum Cover : uint8_t { OPEN, BRUSH, FOREST, FIELD, ROAD, FORD, BRIDGE, WATER, ROCK, COVER_COUNT };

struct TerrainGrid {
    int width = 0;
    int height = 0;
    double cell = 32.0;
    const uint8_t *cover = nullptr;
    const uint8_t *elevation = nullptr;

    bool valid() const { return width > 0 && height > 0 && cell > 0.0 && cover && elevation; }

    int index(double x, double y) const {
        // Clamped in double before the cast: a far point must not overflow int (GDScript floors to int64).
        const int cx = static_cast<int>(std::clamp(std::floor(x / cell), 0.0, static_cast<double>(width - 1)));
        const int cy = static_cast<int>(std::clamp(std::floor(y / cell), 0.0, static_cast<double>(height - 1)));
        return cy * width + cx;
    }
    uint8_t cover_at(double x, double y) const { return cover[index(x, y)]; }
    uint8_t height_at(double x, double y) const { return elevation[index(x, y)]; }
};

} // namespace iron::battle
