#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {
class IronOverworldRenderProbe final : public Node2D {
  GDCLASS(IronOverworldRenderProbe, Node2D)

protected:
  static void _bind_methods() {}

public:
  void _draw() override {
    draw_rect(Rect2(0, 0, 960, 540), Color(0.08, 0.24, 0.29));
    const Vector2 coast[] = {
        {0, 0}, {960, 0}, {960, 420}, {810, 369}, {700, 384},
        {551, 298}, {478, 316}, {368, 247}, {216, 279}, {0, 194}};
    PackedVector2Array land;
    for (const Vector2 &point : coast) {
      land.push_back(point);
    }
    draw_colored_polygon(land, Color(0.57, 0.51, 0.28));
    PackedVector2Array shoreline = land.slice(2);
    draw_polyline(shoreline, Color(0.84, 0.70, 0.45), 4.0, true);
  }
};

void register_overworld_render_probe() {
  ClassDB::register_class<IronOverworldRenderProbe>();
}
} // namespace godot
