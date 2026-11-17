#include <algorithm>
#include <array>
#include <cmath>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
namespace godot {
class IronBattleEffects : public RefCounted {
  GDCLASS(IronBattleEffects, RefCounted)
  static constexpr double PI = 3.14159265358979323846;
  Dictionary settings;

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("advance_particles", "particles", "dt",
                                  "gravity", "dust_kind"),
                         &IronBattleEffects::advance_particles);
    ClassDB::bind_method(D_METHOD("draw_particles", "canvas", "particles"),
                         &IronBattleEffects::draw_particles);
    ClassDB::bind_method(
        D_METHOD("draw_pools", "canvas", "pools", "segments", "alpha", "scale"),
        &IronBattleEffects::draw_pools);
    ClassDB::bind_method(D_METHOD("configure_parts", "settings"),
                         &IronBattleEffects::configure_parts);
    ClassDB::bind_method(
        D_METHOD("draw_parts", "canvas", "parts", "first", "visible", "air"),
        &IronBattleEffects::draw_parts);
  }

public:
  Array advance_particles(Array particles, double dt, double gravity,
                          int dust_kind) {
    Array expired;
    for (int i = int(particles.size()) - 1; i >= 0; --i) {
      Dictionary particle = particles[i];
      double remaining = double(particle["remaining"]) - dt;
      particle["remaining"] = remaining;
      if (remaining <= 0) {
        expired.push_back(particle);
        particles.remove_at(i);
        continue;
      }
      Vector2 position = particle["position"], velocity = particle["velocity"];
      particle["position"] = position + velocity * float(dt);
      if (int(particle["kind"]) != dust_kind) {
        velocity.y += gravity * dt;
        particle["velocity"] = velocity;
      }
    }
    return expired;
  }
  // Same 64-segment fans as Godot's canvas circles, submitted in particle
  // order. Reuse buffers; one mesh upload replaces hundreds of separate polygon
  // uploads.
  PackedVector2Array particle_points;
  PackedColorArray particle_colors;
  PackedInt32Array particle_indices;
  std::array<Vector2, 65> circle_points{};
  bool circle_ready = false;
  void draw_particles(const RID &canvas, const Array &particles) {
    int n = particles.size();
    if (!n)
      return;
    if (!circle_ready) {
      float step = float(2 * PI / 64);
      for (int k = 0; k <= 64; ++k) {
        float angle = k * step;
        circle_points[k] = Vector2(std::cos(angle), std::sin(angle));
      }
      circle_ready = true;
    }
    particle_points.resize(n * 66);
    particle_colors.resize(n * 66);
    if (particle_indices.size() != n * 192) {
      particle_indices.resize(n * 192);
      auto *indices = particle_indices.ptrw();
      for (int i = 0; i < n; ++i)
        for (int k = 0; k < 64; ++k) {
          int offset = i * 192 + k * 3;
          indices[offset] = i * 66 + 65;
          indices[offset + 1] = i * 66 + k;
          indices[offset + 2] = i * 66 + k + 1;
        }
    }
    auto *points = particle_points.ptrw();
    auto *colors = particle_colors.ptrw();
    for (int i = 0; i < n; ++i) {
      Dictionary p = particles[i];
      Color color = p["color"];
      Vector2 at = p["position"];
      float radius = p["radius"];
      color.a =
          std::clamp(double(p["remaining"]) / double(p["lifetime"]), 0.0, 1.0);
      for (int k = 0; k < 66; ++k) {
        points[i * 66 + k] = k == 65 ? at : at + circle_points[k] * radius;
        colors[i * 66 + k] = color;
      }
    }
    RenderingServer::get_singleton()->canvas_item_add_triangle_array(
        canvas, particle_indices, particle_points, particle_colors);
  }

  void draw_pools(const RID &canvas, const Array &pools, int segments,
                  double alpha, Vector2 scale) {
    if (pools.is_empty() || segments < 3)
      return;
    PackedVector2Array points;
    PackedColorArray colors;
    PackedInt32Array indices;
    points.resize(pools.size() * segments);
    colors.resize(points.size());
    indices.resize(pools.size() * (segments - 2) * 3);
    auto *v = points.ptrw();
    auto *c = colors.ptrw();
    auto *idx = indices.ptrw();
    for (int i = 0; i < pools.size(); ++i) {
      Dictionary pool = pools[i];
      Vector2 at = pool["position"];
      double radius = pool["radius"];
      Color color = pool["color"];
      color.a = alpha;
      for (int k = 0; k < segments; ++k) {
        v[i * segments + k] = at + Vector2::from_angle(2 * PI * k / segments) *
                                       scale * float(radius);
        c[i * segments + k] = color;
      }
      for (int k = 0; k < segments - 2; ++k) {
        int offset = (i * (segments - 2) + k) * 3;
        idx[offset] = i * segments;
        idx[offset + 1] = i * segments + k + 1;
        idx[offset + 2] = i * segments + k + 2;
      }
    }
    RenderingServer::get_singleton()->canvas_item_add_triangle_array(
        canvas, indices, points, colors);
  }
  void configure_parts(const Dictionary &value) {
    settings = value.duplicate();
  }
  void draw_parts(const RID &canvas, const Array &parts, int first,
                  Rect2 visible, bool air) {
    if (settings.is_empty())
      return;
    auto *server = RenderingServer::get_singleton();
    auto bone = [&](double half) {
      Vector2 left(-half, 0), right(half, 0);
      Color color = settings["bone_color"];
      server->canvas_item_add_line(canvas, left, right, color,
                                   settings["bone_width"], true);
      server->canvas_item_add_circle(canvas, left, settings["joint_radius"],
                                     color);
      server->canvas_item_add_circle(canvas, right, settings["joint_radius"],
                                     color);
    };
    for (int i = 0; i < parts.size(); ++i) {
      Dictionary part = parts[(first + i) % parts.size()];
      Vector2 ground = part["position"];
      if (!air && !visible.has_point(ground))
        continue;
      if (air)
        server->canvas_item_add_circle(canvas, ground,
                                       settings["shadow_radius"],
                                       settings["shadow_color"]);
      Vector2 at = ground - Vector2(0, double(part["height"]));
      double angle = part["angle"];
      server->canvas_item_add_set_transform(canvas, Transform2D(angle, at));
      switch (int(part["kind"])) {
      case 0:
      case 4: // severed leg: textured like the head
      case 5: { // upper torso
        double scale = part.get("scale", settings["scale"]);
        double direction = bool(part["mirrored"]) ? -1 : 1;
        server->canvas_item_add_set_transform(
            canvas,
            Transform2D(angle, Vector2(direction, 1) * float(scale), 0, at));
        Ref<Texture2D> texture = part["texture"];
        if (texture.is_valid())
          texture->draw(canvas,
                        -Vector2(part.get("anchor", settings["anchor"])));
        break;
      }
      case 1:
        if (bool(part["bony"]))
          bone(settings["arm_half"]);
        else {
          server->canvas_item_add_rect(canvas, settings["arm_sleeve"],
                                       part["sleeve"]);
          server->canvas_item_add_rect(canvas, settings["arm_skin"],
                                       part["skin"]);
          server->canvas_item_add_circle(
              canvas, Vector2(double(settings["arm_half"]), 0),
              settings["hand_radius"], part["skin"]);
        }
        break;
      case 2:
        bone(double(part["size"]) * .5);
        break;
      case 3:
        server->canvas_item_add_circle(canvas, Vector2(), part["size"],
                                       part["color"]);
        break;
      }
      server->canvas_item_add_set_transform(canvas, Transform2D());
    }
  }
};
void register_battle_effects() { ClassDB::register_class<IronBattleEffects>(); }
} // namespace godot
