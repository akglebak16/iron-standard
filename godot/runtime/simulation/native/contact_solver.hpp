#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
#include <utility>

// Engine-independent contact kernel. Inputs/outputs are values; no Godot headers.
namespace iron {
struct Vec2 {
    float x = 0, y = 0;
    Vec2 operator+(Vec2 b) const { return {x + b.x, y + b.y}; }
    Vec2 operator-(Vec2 b) const { return {x - b.x, y - b.y}; }
    Vec2 operator*(double n) const { float f = float(n); return {x * f, y * f}; }
    Vec2 operator/(double n) const { float f = float(n); return {x / f, y / f}; }
    float squared() const { return x * x + y * y; }
    float length() const { return std::sqrt(squared()); }
};

struct ContactParameters {
    double width, height, pad, cell, slack, minimum_distance;
    double friend_push, enemy_push, horizontal_margin, top_margin, bottom_margin;
    double wall_x, wall_half_width, wall_radius_padding, gap_radius_padding;
};

class Grid {
    int width = 0, height = 0;
    double pad = 0, cell = 1;
    std::vector<std::vector<int>> buckets;
    std::vector<int> locations;
    int column(double x) const { return std::clamp(int(std::floor((x + pad) / cell)), 0, width - 1); }
    int row(double y) const { return std::clamp(int(std::floor((y + pad) / cell)), 0, height - 1); }
    int at(Vec2 p) const { return row(p.y) * width + column(p.x); }
public:
    void reset(const std::vector<Vec2> &positions, double arena_w, double arena_h,
               double padding, double cell_size, const std::vector<uint8_t> *live = nullptr) {
        pad = padding; cell = cell_size;
        int w = int(std::ceil((arena_w + 2 * pad) / cell)) + 1;
        int h = int(std::ceil((arena_h + 2 * pad) / cell)) + 1;
        if (w != width || h != height) { buckets.clear(); buckets.resize(w * h); width = w; height = h; }
        else for (auto &bucket : buckets) bucket.clear();
        locations.resize(positions.size());
        for (int i = 0; i < int(positions.size()); ++i) {
            if (live && !(*live)[i]) { locations[i] = -1; continue; }
            int c = at(positions[i]); locations[i] = c; buckets[c].push_back(i);
        }
    }
    void move(int i, Vec2 p) {
        int c = at(p), old = locations[i];
        if (c == old) return;
        if (old >= 0) { auto &b = buckets[old]; auto found = std::find(b.begin(), b.end(), i); if (found != b.end()) b.erase(found); }
        buckets[c].push_back(i); locations[i] = c;
    }
    void query(Vec2 p, double radius, int first, std::vector<int> &out) const {
        out.clear();
        int x0 = column(double(p.x) - radius), x1 = column(double(p.x) + radius);
        int y0 = row(double(p.y) - radius), y1 = row(double(p.y) + radius);
        for (int y = y0; y <= y1; ++y) for (int x = x0; x <= x1; ++x)
            for (int i : buckets[y * width + x]) if (i >= first) out.push_back(i);
        std::sort(out.begin(), out.end());
    }
};

class ContactSolver {
    ContactParameters config{};
    Grid moving, obstacles;
    std::vector<Vec2> trunks, gaps;
    std::vector<double> trunk_radii;
    std::vector<int> candidates, obstacle_candidates;
    double max_trunk_radius = 0;

    Vec2 constrain_obstacles(Vec2 at, double radius) {
        int first = 0;
        while (first < int(trunks.size())) {
            obstacles.query(at, radius + max_trunk_radius, first, obstacle_candidates);
            bool moved = false;
            for (int i : obstacle_candidates) {
                first = i + 1;
                double reach = radius + trunk_radii[i];
                Vec2 offset = at - trunks[i]; double squared = offset.squared();
                if (squared >= reach * reach) continue;
                Vec2 normal = squared == 0 ? Vec2{1, 0} : offset / std::sqrt(squared);
                at = trunks[i] + normal * reach;
                moved = true; break;
            }
            if (!moved) break;
        }
        return at;
    }
    void constrain_wall(Vec2 &at, Vec2 &velocity, double radius) const {
        if (!std::isfinite(config.wall_x)) return;
        double clearance = config.wall_half_width + radius * config.wall_radius_padding;
        double offset = double(at.x) - config.wall_x;
        if (std::abs(offset) >= clearance) return;
        for (Vec2 gap : gaps) if (at.y > gap.x && at.y < gap.y) {
            double padding = radius * config.gap_radius_padding;
            // GDScript clampf is min(max(value, min), max), even for a narrow gap.
            at.y = float(std::min(std::max(double(at.y), gap.x + padding), gap.y - padding));
            return;
        }
        at.x = float(offset < 0 ? config.wall_x - clearance : config.wall_x + clearance);
        double sign = velocity.x > 0 ? 1 : (velocity.x < 0 ? -1 : 0);
        if (sign != (offset <= 0 ? -1 : 1)) velocity.x = 0;
    }
public:
    std::vector<Vec2> positions, velocities;
    std::vector<double> radii, masses;
    std::vector<int32_t> sides;
    std::vector<uint8_t> live, fleeing;

    void configure(ContactParameters parameters, std::vector<Vec2> geometry,
                   std::vector<double> geometry_radii, std::vector<Vec2> wall_gaps) {
        config = parameters; trunks = std::move(geometry); trunk_radii = std::move(geometry_radii); gaps = std::move(wall_gaps);
        max_trunk_radius = 0;
        for (double radius : trunk_radii) max_trunk_radius = std::max(max_trunk_radius, radius);
        obstacles.reset(trunks, config.width, config.height, config.pad, 128);
    }
    void resize(int count) {
        positions.resize(count); velocities.resize(count); radii.resize(count); masses.resize(count);
        sides.resize(count); live.resize(count); fleeing.resize(count);
    }
    void solve() {
        const int n = int(positions.size());
        double max_radius = 0;
        for (double radius : radii) max_radius = std::max(max_radius, radius);
        moving.reset(positions, config.width, config.height, config.pad, config.cell, &live);
        for (int i = 0; i < n; ++i) {
            if (!live[i]) continue;
            Vec2 pa = positions[i]; const double ra = radii[i], ma = masses[i];
            int next = i + 1;
            while (next < n) {
                Vec2 origin = pa;
                moving.query(pa, ra + max_radius + config.slack, next, candidates);
                bool moved_far = false;
                for (int j : candidates) {
                    next = j + 1;
                    Vec2 pb = positions[j], difference = pb - pa;
                    double radius = ra + radii[j];
                    if (std::abs(difference.x) >= radius || std::abs(difference.y) >= radius || double(difference.squared()) >= radius * radius) continue;
                    double distance = std::max(double(difference.length()), config.minimum_distance);
                    Vec2 normal = difference.x == 0 && difference.y == 0 ? Vec2{1, 0} : difference / distance;
                    double overlap = (radius - distance) * (sides[i] == sides[j] ? config.friend_push : config.enemy_push);
                    double mb = masses[j], total = ma + mb;
                    pa = pa - normal * overlap * mb / total;
                    pb = pb + normal * overlap * ma / total;
                    positions[j] = pb; moving.move(j, pb);
                    if ((pa - origin).squared() > config.slack * config.slack) { moved_far = true; break; }
                }
                if (!moved_far) break;
            }
            constrain_wall(pa, velocities[i], ra);
            pa = constrain_obstacles(pa, ra);
            if (!fleeing[i]) pa.x = float(std::clamp(double(pa.x), config.horizontal_margin, config.width - config.horizontal_margin));
            pa.y = float(std::clamp(double(pa.y), config.top_margin, config.height - config.bottom_margin));
            positions[i] = pa; moving.move(i, pa);
        }
    }
};
}
