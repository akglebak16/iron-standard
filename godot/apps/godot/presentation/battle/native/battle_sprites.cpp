#include <algorithm>
#include <array>
#include <cmath>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <unordered_map>
#include <vector>
namespace godot {
// Main-thread Godot presentation adapter. Only detached snapshot columns and
// visual resources.
class IronBattleSprites : public RefCounted {
  GDCLASS(IronBattleSprites, RefCounted)
  static constexpr double PI = 3.14159265358979323846;
  struct Look {
    Ref<Texture2D> body, weapon, flash;
    Vector2 anchor, pivot;
    double scale, phase;
    int kind;
    std::array<Ref<Texture2D>, 4> rings, fills;
  };
  struct Row {
    int index;
    int64_t key;
    Vector2 position;
  };
  std::unordered_map<int64_t, Look> looks;
  std::unordered_map<int64_t, double> winds;
  std::unordered_map<int64_t, Vector2> previous_positions, directions;
  std::vector<Row> ordered;
  Ref<Texture2D> shadow, white;
  static Vector3 swing(int kind, double bump) {
    double p = 1 - bump, a = 0, x = 0, y = 0;
    auto mix = [](double from, double to, double weight) {
      return from + (to - from) * weight;
    };
    if (kind == 3) {
      double q = std::clamp(1 - bump * 2, 0.0, 1.0);
      x = -5 * (1 - q) * (1 - q);
      a = -.12 * (1 - q);
    } else if (kind == 2) {
      if (p < .25) {
        double q = p / .25;
        a = .1 * q;
        x = -7 * q;
        y = 3 * q;
      } else if (p < .5) {
        double q = (p - .25) / .25, ease = 1 - (1 - q) * (1 - q);
        a = mix(.1, .5, ease);
        x = mix(-7, 16, ease);
        y = mix(3, 2, ease);
      } else {
        double q = (p - .5) / .5;
        a = mix(.5, 0, q);
        x = mix(16, 0, q);
        y = mix(2, 0, q);
      }
    } else {
      if (p < .28)
        a = -.55 * std::sin((p / .28) * PI / 2);
      else if (p < .55) {
        double q = (p - .28) / .27, ease = 1 - std::pow(1 - q, 3);
        a = mix(-.55, 1.25, ease);
      } else {
        double q = (p - .55) / .45;
        a = mix(1.25, 0, q * q * (3 - 2 * q));
      }
    }
    return Vector3(a, x, y);
  }
  static Transform2D body_pose(Vector2 at, double time, double phase,
                               double speed, bool mounted, double facing,
                               double bump, double scale) {
    double direction = std::cos(facing) < 0 ? -1 : 1,
           breath = 1 + std::sin(time * 2.1 + phase) * .012;
    double lean = speed > 12 ? std::clamp(speed / 90, 0.0, 1.0) * .055 : 0;
    Vector2 offset;
    if (speed > 12)
      offset.y =
          std::sin(time * (mounted ? 15 : 11) + phase) * (mounted ? 2 : 1.3);
    if (bump > 0)
      offset +=
          Vector2::from_angle(facing) * float(std::sin((1 - bump) * PI) * 7);
    double horse = 0;
    if (mounted && speed > 12) {
      double hp = time * (7 + std::clamp(speed / 60, 0.0, 3.0)) + phase;
      offset.y -= std::abs(std::sin(hp)) * 2.6;
      horse = std::sin(hp) * .018 * direction;
    }
    Vector2 x = Vector2(direction * scale * std::cos(lean),
                        scale * breath * std::sin(lean))
                    .rotated(horse);
    Vector2 y = Vector2(-direction * scale * std::sin(lean),
                        scale * breath * std::cos(lean))
                    .rotated(horse);
    return Transform2D(x, y, at + offset);
  }

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("draw_minimap", "canvas", "positions",
                                  "flags", "sides", "bounds", "scale", "sizes",
                                  "colors"),
                         &IronBattleSprites::draw_minimap);
    ClassDB::bind_method(D_METHOD("configure", "entries", "shadow", "white"),
                         &IronBattleSprites::configure);
    ClassDB::bind_method(D_METHOD("draw", "canvas", "columns", "visible",
                                  "vegetation", "time", "interpolation",
                                  "selection", "demo", "bumps", "flashes",
                                  "fallback", "snow"),
                         &IronBattleSprites::draw);
    ClassDB::bind_method(D_METHOD("sample_body", "at", "time", "phase", "speed",
                                  "mounted", "facing", "bump", "scale"),
                         &IronBattleSprites::sample_body);
    ClassDB::bind_method(D_METHOD("sample_swing", "kind", "bump"),
                         &IronBattleSprites::sample_swing);
  }

public:
  void draw_minimap(const RID &canvas, const PackedVector2Array &positions,
                    const PackedInt32Array &flags,
                    const PackedInt32Array &sides, Rect2 bounds, Vector2 scale,
                    Vector3 sizes, const PackedColorArray &colors) {
    if (flags.size() != positions.size() || sides.size() != positions.size() ||
        colors.size() != 3)
      return;
    auto *server = RenderingServer::get_singleton();
    const auto *points = positions.ptr();
    const auto *bits = flags.ptr();
    const auto *teams = sides.ptr();
    for (int row = 0; row < positions.size(); ++row) {
      if (bits[row] & 3)
        continue;
      Vector2 at = bounds.position + points[row] * scale;
      if (!bounds.has_point(at))
        continue;
      bool hero = bits[row] & 4;
      float size = hero ? sizes.x : (bits[row] & 16 ? sizes.y : sizes.z);
      Color color = colors[teams[row] != 0 ? 2 : (hero ? 0 : 1)];
      server->canvas_item_add_rect(
          canvas,
          Rect2(at - Vector2(size, size) * .5, Vector2(size, size))
              .intersection(bounds),
          color);
    }
  }
  Transform2D sample_body(Vector2 at, double time, double phase, double speed,
                          bool mounted, double facing, double bump,
                          double scale) {
    return body_pose(at, time, phase, speed, mounted, facing, bump, scale);
  }
  Vector3 sample_swing(int kind, double bump) { return swing(kind, bump); }
  void configure(const Array &entries, const Ref<Texture2D> &p_shadow,
                 const Ref<Texture2D> &p_white) {
    shadow = p_shadow;
    white = p_white;
    for (int n = 0; n < entries.size(); ++n) {
      Dictionary entry = entries[n], art = entry["art"];
      int64_t id = entry["id"];
      Look l;
      l.body = art["body"];
      l.weapon = art["weapon"];
      l.flash = art.get("flash", Variant());
      l.anchor = art.get("anchor", Vector2(37, 76));
      l.pivot = art.get("pivot", Vector2(53, 52));
      l.scale = art.get("scale", .43);
      l.phase = entry["phase"];
      String weapon = art.get("weapon_kind", "");
      l.kind = weapon == "bow" || weapon == "xbow" ? 3
               : weapon == "spear" || weapon == "halberd" || weapon == "lance"
                   ? 2
               : weapon.is_empty() ? 0
                                   : 1;
      Array assets = entry["rings"];
      for (int k = 0; k < 4; ++k) {
        Array pair = assets[k];
        l.rings[k] = pair[0];
        l.fills[k] = pair[1];
      }
      looks[id] = l;
    }
  }
  void draw(const RID &canvas, const Array &columns, const Rect2 &visible,
            const Array &vegetation, double time, double interpolation,
            int selection, bool demo, Dictionary bumps,
            const Dictionary &flashes, const Callable &fallback, bool snow) {
    if (columns.size() != 7 || selection < 0 || selection > 3 ||
        shadow.is_null() || white.is_null())
      return;
    PackedVector2Array positions = columns[0], previous = columns[1];
    PackedInt32Array flags = columns[2], sides = columns[3],
                     groups = columns[4];
    PackedFloat64Array dynamic = columns[5];
    PackedInt64Array ids = columns[6];
    int n = int(positions.size());
    if (previous.size() != n || flags.size() != n || sides.size() != n ||
        groups.size() != n || dynamic.size() != n * 5 || ids.size() != n)
      return;
    ordered.clear();
    const Vector2 *p = positions.ptr(), *old = previous.ptr();
    const int32_t *bits = flags.ptr(), *side = sides.ptr();
    const int64_t *identity = ids.ptr();
    const double *data = dynamic.ptr();
    for (int row = 0; row < n; ++row) {
      if (bits[row] & 3 || (demo && (bits[row] & 12)))
        continue;
      Vector2 at = old[row].lerp(p[row], interpolation);
      if (!visible.has_point(at))
        continue;
      ordered.push_back(
          {row, (int64_t(std::floor(at.y * 16)) + 1048576) * 65536 + row, at});
    }
    std::sort(ordered.begin(), ordered.end(),
              [](const Row &a, const Row &b) { return a.key < b.key; });
    auto *server = RenderingServer::get_singleton();
    int plant_index = 0;
    auto plant = [&](const Dictionary &value) {
      Rect2 bounds = value["bounds"];
      if (visible.intersects(bounds)) {
        Ref<Texture2D> texture = value["texture"];
        texture->draw(canvas, bounds.position);
      }
    };
    for (const Row &row : ordered) {
      int index = row.index;
      int64_t id = identity[index];
      const double *d = data + index * 5;
      Vector2 at = row.position;
      while (plant_index < vegetation.size()) {
        Dictionary value = vegetation[plant_index];
        Vector2 where = value["position"];
        if (where.y >= at.y)
          break;
        plant(value);
        ++plant_index;
      }
      double windup = d[4];
      auto w = winds.find(id);
      double old_wind = w == winds.end() ? -1 : w->second;
      if (windup >= 0 && (old_wind < 0 || windup > old_wind + .0001))
        bumps[id] = 1.0;
      winds[id] = windup;
      auto old_pos = previous_positions.find(id);
      if (old_pos != previous_positions.end() && old_pos->second != at)
        directions[id] = old_pos->second.direction_to(at);
      previous_positions[id] = at;
      bool mounted = bits[index] & 16;
      auto found = looks.find(id);
      if (found == looks.end() || (bits[index] & (4 | 8 | 128))) {
        auto direction = directions.find(id);
        fallback.call(index, direction == directions.end()
                                 ? Vector2::from_angle(d[2])
                                 : direction->second);
        continue;
      }
      const Look &l = found->second;
      double radius = d[0], bump = bumps.get(id, 0.0);
      Color tint(1, 1, 1, bits[index] & 32 ? .75 : 1);
      Vector2 extent(radius * 1.65, radius * .72);
      shadow->draw_rect(canvas, Rect2(at + Vector2(4, 3) - extent, extent * 2),
                        false);
      if (!demo) {
        if (l.fills[selection].is_valid()) {
          Vector2 size = l.fills[selection]->get_size();
          l.fills[selection]->draw_rect(
              canvas, Rect2(at - size * .25, size * .5), false,
              Color(241. / 255, 210. / 255, 122. / 255, .15));
        }
        if (l.rings[selection].is_valid())
          l.rings[selection]->draw(canvas,
                                   at - l.rings[selection]->get_size() * .5);
      }
      const bool flashing = flashes.has(id);
      if (!demo) {
        if (mounted && d[3] > 35 && id % 3 == 0) {
          double t = std::fmod(time * 2.3 + l.phase, 1.0);
          auto found_direction = directions.find(id);
          Vector2 back =
              -(found_direction == directions.end() ? Vector2::from_angle(d[2])
                                                    : found_direction->second);
          Color color = snow ? Color(241. / 255, 246. / 255, 247. / 255, .28)
                             : Color(191. / 255, 168. / 255, 113. / 255, .24);
          // Keep the three antialiased circles together at this exact depth
          // slot.
          PackedVector2Array points;
          PackedColorArray colors;
          PackedInt32Array indices;
          points.resize(588);
          colors.resize(588);
          indices.resize(1728);
          auto *vp = points.ptrw();
          auto *cp = colors.ptrw();
          auto *ip = indices.ptrw();
          Vector2 scale(3 + t * 5, 1.5 + t * 2);
          for (int puff = 0; puff < 3; ++puff) {
            Vector2 origin =
                at + back * float(t * 30 + puff * 5) + Vector2(puff * 3, 0);
            int base = puff * 196, offset = puff * 576;
            vp[base + 65] = origin;
            cp[base + 65] = color;
            const float step = float(2 * PI / 64);
            for (int k = 0; k <= 64; ++k) {
              float angle = k * step;
              Vector2 direction(std::cos(angle), std::sin(angle));
              vp[base + k] = origin + direction * .6875f * scale;
              cp[base + k] = color;
              vp[base + 66 + k * 2] = vp[base + k];
              cp[base + 66 + k * 2] = color;
              vp[base + 67 + k * 2] = origin + direction * 1.9375f * scale;
              cp[base + 67 + k * 2] = Color(color, 0);
            }
            for (int k = 0; k < 64; ++k) {
              ip[offset + k * 3] = base + 65;
              ip[offset + k * 3 + 1] = base + k;
              ip[offset + k * 3 + 2] = base + k + 1;
              int q = offset + 192 + k * 6, v = base + 66 + k * 2;
              ip[q] = v;
              ip[q + 1] = v + 1;
              ip[q + 2] = v + 2;
              ip[q + 3] = v + 2;
              ip[q + 4] = v + 1;
              ip[q + 5] = v + 3;
            }
          }
          server->canvas_item_add_triangle_array(canvas, indices, points,
                                                 colors);
        }
        if (flashing) {
          double alpha =
              std::clamp((double(flashes[id]) - time) / .13, 0.0, 1.0) * .8;
          Vector2 origin = at + Vector2(-std::cos(d[2]) * 7, -22);
          for (int k = 0; k < 3; ++k) {
            Vector2 direction = Vector2::from_angle(l.phase + k * 2.1);
            server->canvas_item_add_line(
                canvas, origin + direction * 4, origin + direction * 10,
                Color(1, 229. / 255, 160. / 255, alpha), 1.5, true);
          }
        }
      }
      Transform2D body =
          body_pose(at, time, l.phase, d[3], mounted, d[2], bump, l.scale);
      server->canvas_item_add_set_transform(canvas, body);
      if (flashing && l.flash.is_valid())
        l.flash->draw(canvas, -l.anchor, tint);
      else
        l.body->draw(canvas, -l.anchor, tint);
      if (!(flashing && l.flash.is_valid()) && l.weapon.is_valid()) {
        if (bump > 0 && l.kind > 0) {
          Vector3 pose = swing(l.kind, bump);
          Transform2D weapon =
              body *
              Transform2D(pose.x, l.pivot - l.anchor + Vector2(pose.y, pose.z));
          server->canvas_item_add_set_transform(canvas, weapon);
          l.weapon->draw(canvas, -l.pivot, tint);
          if (l.kind == 1 && pose.x > .1) {
            server->canvas_item_add_set_transform(canvas,
                                                  weapon.rotated_local(-.28));
            l.weapon->draw(canvas, -l.pivot, Color(1, 1, 1, tint.a * .35));
          }
        } else
          l.weapon->draw(canvas, -l.anchor, tint);
      }
      server->canvas_item_add_set_transform(canvas, Transform2D());
      if (!demo) {
        if (d[1] < 1) {
          double width = radius * 1.9;
          Rect2 bar(at - Vector2(width * .5, mounted ? 70 : 52),
                    Vector2(width, 3));
          white->draw_rect(canvas, bar.grow(1), false,
                           Color(.06, .04, .02, .8));
          bar.size.x *= d[1];
          white->draw_rect(canvas, bar, false,
                           side[index] == 0 ? Color::html("7fb04a")
                                            : Color::html("c23a2c"));
        }
        if (bits[index] & 32) {
          white->draw_rect(canvas,
                           Rect2(at + Vector2(-2, -67), Vector2(1.5, 14)),
                           false, Color::html("3a2a18"));
          white->draw_rect(canvas, Rect2(at + Vector2(-1, -66), Vector2(9, 6)),
                           false, Color::html("f4f0e0"));
        }
      }
    }
    while (plant_index < vegetation.size()) {
      plant(vegetation[plant_index]);
      ++plant_index;
    }
  }
};
void register_battle_sprites() { ClassDB::register_class<IronBattleSprites>(); }
} // namespace godot
