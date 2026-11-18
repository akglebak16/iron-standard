#include "trial_geometry.hpp"

#include <chrono>
#include <cmath>
#include <condition_variable>
#include <limits>
#include <mutex>
#include <optional>
#include <thread>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {
namespace map = iron::overworld;

class IronWorldMapRenderer final : public Node2D {
  GDCLASS(IronWorldMapRenderer, Node2D)

  struct ResidentChunk {
    RID canvas;
    std::uint64_t requested_revision = 0;
    std::uint64_t applied_revision = 0;
  };
  struct PreparedChunk {
    map::ChunkKey key;
    std::uint64_t world_id;
    std::uint64_t revision;
    std::vector<map::Patch> patches;
  };
  struct BuildRequest {
    map::ChunkKey key;
    map::Geography geography;
    std::uint64_t chunk_revision;
  };

  std::array<ResidentChunk, map::columns * map::rows> chunks_{};
  map::TrialWorld trial_;
  Rect2i retained_;
  mutable std::mutex worker_mutex_;
  std::condition_variable has_request_;
  std::optional<BuildRequest> request_;
  std::optional<PreparedChunk> completed_;
  bool stopping_ = false;
  bool building_ = false;
  std::thread worker_;
  RID company_canvas_;
  int uploads_ = 0;
  int evictions_ = 0;
  int discarded_ = 0;
  float accumulated_ = 0;
  map::Point previous_company_{map::west_gate, map::crossing_y};

  static RenderingServer *server() { return RenderingServer::get_singleton(); }

  void prepare_chunks() {
    std::unique_lock<std::mutex> lock(worker_mutex_);
    while (true) {
      has_request_.wait(lock, [&] { return stopping_ || request_.has_value(); });
      if (stopping_)
        return;
      const auto request = *request_;
      request_.reset();
      lock.unlock();
      auto patches = map::build_chunk(request.geography, request.key);
      lock.lock();
      completed_ = PreparedChunk{request.key, request.geography.world_id,
                                 request.chunk_revision, std::move(patches)};
      building_ = false;
    }
  }

  ResidentChunk &chunk(map::ChunkKey key) {
    return chunks_[key.y * map::columns + key.x];
  }

  void release(ResidentChunk &entry) {
    if (!entry.canvas.is_valid())
      return;
    server()->free_rid(entry.canvas);
    entry.canvas = RID();
    ++evictions_;
  }

  static void draw_patch(RID canvas, const map::Patch &patch) {
    // Collinear polygons arise when a feature touches a chunk edge.
    double area = 0;
    for (std::size_t i = 0; i < patch.points.size(); ++i) {
      const auto a = patch.points[i];
      const auto b = patch.points[(i + 1) % patch.points.size()];
      area += double(a.x) * b.y - double(b.x) * a.y;
    }
    if (std::abs(area) < 0.01)
      return;
    static const std::array<Color, 8> palette{{
        {0.08, 0.24, 0.29}, {0.76, 0.65, 0.42}, {0.54, 0.51, 0.28},
        {0.15, 0.40, 0.46}, {0.40, 0.32, 0.18}, {0.82, 0.64, 0.35},
        {0.32, 0.23, 0.17}, {0.55, 0.40, 0.25}}};
    PackedVector2Array points;
    for (const map::Point point : patch.points)
      points.push_back(Vector2(point.x, point.y));
    PackedColorArray color;
    color.push_back(palette[static_cast<int>(patch.paint)]);
    server()->canvas_item_add_polygon(canvas, points, color);
  }

  void publish(PreparedChunk result, const Rect2i &keep) {
    auto &entry = chunk(result.key);
    if (result.world_id != trial_.snapshot().world_id ||
        result.revision != entry.requested_revision ||
        !keep.has_point(Vector2i(result.key.x, result.key.y))) {
      ++discarded_;
      return;
    }
    if (!entry.canvas.is_valid()) {
      entry.canvas = server()->canvas_item_create();
      server()->canvas_item_set_parent(entry.canvas, get_canvas_item());
    }
    server()->canvas_item_clear(entry.canvas);
    for (const auto &patch : result.patches)
      draw_patch(entry.canvas, patch);
    entry.applied_revision = result.revision;
    ++uploads_;
  }

  void stream(const Rect2 &visible) {
    const Vector2 first = (visible.position / map::chunk_size).floor();
    const Vector2 last = (visible.get_end() / map::chunk_size).ceil();
    const Rect2i bounds(0, 0, map::columns, map::rows);
    const Rect2i view(Vector2i(first), Vector2i(last - first));
    const Rect2i keep = view.grow(1).intersection(bounds);

    if (keep != retained_) {
      for (int y = retained_.position.y; y < retained_.get_end().y; ++y)
        for (int x = retained_.position.x; x < retained_.get_end().x; ++x)
          if (!keep.has_point(Vector2i(x, y)))
            release(chunk({x, y}));
      retained_ = keep;
    }

    std::optional<PreparedChunk> ready;
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      if (building_)
        return;
      ready = std::move(completed_);
      completed_.reset();
    }
    if (ready)
      publish(std::move(*ready), keep);

    // Visible chunks come first. Each frame applies at most one prepared chunk.
    map::ChunkKey selected{-1, -1};
    double best = std::numeric_limits<double>::infinity();
    for (int y = keep.position.y; y < keep.get_end().y; ++y) {
      for (int x = keep.position.x; x < keep.get_end().x; ++x) {
        const auto &entry = chunk({x, y});
        if (entry.canvas.is_valid() && entry.applied_revision == entry.requested_revision)
          continue;
        const Vector2 center = Vector2(x + 0.5, y + 0.5) * map::chunk_size;
        const double score = center.distance_squared_to(visible.get_center()) +
                             (view.has_point(Vector2i(x, y)) ? 0 : 1e12);
        if (score < best) {
          selected = {x, y};
          best = score;
        }
      }
    }
    if (selected.x < 0)
      return;
    const auto geography = trial_.snapshot();
    const auto revision = chunk(selected).requested_revision;
    if (!worker_.joinable())
      worker_ = std::thread(&IronWorldMapRenderer::prepare_chunks, this);
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      request_ = BuildRequest{selected, geography, revision};
      building_ = true;
    }
    has_request_.notify_one();
  }

  void draw_company(Vector2 position) {
    if (!company_canvas_.is_valid()) {
      company_canvas_ = server()->canvas_item_create();
      server()->canvas_item_set_parent(company_canvas_, get_canvas_item());
      server()->canvas_item_set_z_index(company_canvas_, 1);
      server()->canvas_item_add_circle(company_canvas_, Vector2(), 13, Color(0.12, 0.14, 0.16));
      server()->canvas_item_add_circle(company_canvas_, Vector2(), 9, Color(0.87, 0.72, 0.39));
      server()->canvas_item_add_rect(company_canvas_, Rect2(7, -23, 3, 18), Color(0.12, 0.14, 0.16));
      server()->canvas_item_add_rect(company_canvas_, Rect2(10, -23, 13, 8), Color(0.57, 0.18, 0.12));
    }
    server()->canvas_item_set_transform(company_canvas_, Transform2D(0, position));
  }

protected:
  static void _bind_methods() {
    ClassDB::bind_method(D_METHOD("update_trial", "visible", "seconds"), &IronWorldMapRenderer::update_trial);
    ClassDB::bind_method(D_METHOD("set_bridge", "open"), &IronWorldMapRenderer::set_bridge);
    ClassDB::bind_method(D_METHOD("reload_trial"), &IronWorldMapRenderer::reload_trial);
    ClassDB::bind_method(D_METHOD("trial_status"), &IronWorldMapRenderer::trial_status);
  }

public:
  ~IronWorldMapRenderer() override {
    if (worker_.joinable()) {
      {
        std::lock_guard<std::mutex> lock(worker_mutex_);
        stopping_ = true;
      }
      has_request_.notify_one();
      worker_.join();
    }
    for (auto &entry : chunks_)
      release(entry);
    if (company_canvas_.is_valid())
      server()->free_rid(company_canvas_);
  }

  void update_trial(Rect2 visible, double seconds) {
    constexpr float step = 1.0f / 60;
    accumulated_ += std::clamp(float(seconds), 0.0f, 4 * step);
    while (accumulated_ >= step) {
      previous_company_ = trial_.company();
      trial_.advance(step);
      accumulated_ -= step;
    }
    const auto current = trial_.company();
    draw_company(Vector2(previous_company_.x, previous_company_.y).lerp(
        Vector2(current.x, current.y), accumulated_ / step));
    stream(visible);
  }

  void set_bridge(bool open) {
    if (!trial_.set_bridge(open))
      return;
    previous_company_ = trial_.company();
    for (int x = int(map::west_bank) / map::chunk_size; x <= int(map::east_bank) / map::chunk_size; ++x)
      chunk({x, int(map::crossing_y) / map::chunk_size}).requested_revision = trial_.snapshot().revision;
  }

  void reload_trial() {
    trial_.reload();
    accumulated_ = 0;
    previous_company_ = trial_.company();
    for (auto &entry : chunks_) {
      release(entry);
      entry = {};
    }
  }

  Dictionary trial_status() const {
    Dictionary status;
    int resident = 0;
    for (const auto &entry : chunks_)
      if (entry.canvas.is_valid())
        ++resident;
    status["resident"] = resident;
    status["uploaded"] = uploads_;
    status["evicted"] = evictions_;
    status["discarded"] = discarded_;
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      status["busy"] = building_ || completed_.has_value();
    }
    status["company_x"] = trial_.company().x;
    status["bridge"] = trial_.snapshot().bridge;
    return status;
  }
};

void register_overworld_trial() {
  ClassDB::register_class<IronWorldMapRenderer>();
}
} // namespace godot
