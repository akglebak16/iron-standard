#include "unit_painter.h"
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/transform2d.hpp>
#include <algorithm>
#include <cmath>
#include <map>
#include <unordered_map>
#include <unordered_set>
#include <tuple>
#include <vector>

using namespace godot;

namespace {

struct P {
	Vector2 anchor, pivot, mount_weapon_offset;
	double sprite_scale, phase_step, breath_rate, breath_scale, walk_rate, walk_bob, gallop_bob, moving_speed, lean, spring,
			flash, windup_angle, swing_angle, block_angle, thrust, fleeing_opacity;
	Color shadow;
	double ring_flatten, ring_padding, standard_width, leader_width;
	Color ally_selected, ally_idle, enemy_ring;
	double health_width_per_radius, health_height, health_frame, foot_health_y, mount_health_y;
	Color health_frame_color, ally_health, enemy_health;
	Vector2 flee_flag_offset, flee_flag_size, flee_flag_pole;
	Color flee_flag_color, pole_color;
	int64_t all_groups = 3;
	bool ready = false;
};
P C;

struct Look {
	Ref<Texture2D> body, weapon;
	bool thrust = false;
};

struct Refs {
	String k_position = "position", k_body = "body", k_weapon = "weapon", k_kind = "weapon_kind", k_texture = "texture", k_bounds = "bounds";
	std::map<std::tuple<float, float, uint32_t>, Ref<ImageTexture>> rings;
	std::unordered_map<int64_t, Look> looks;
	std::unordered_set<int64_t> baked;
	std::vector<int> ordinary;
	PackedFloat64Array render;
};
Refs *R = nullptr;
const int S = 12; // BattleCore.render_data stride
enum { F_MOUNTED = 1, F_FLEEING = 2, F_DEAD = 4, F_GONE = 8, F_HERO = 16, F_COMPANION = 32, F_LEADER = 64, F_BLOCKING = 128 };

bool thrust_kind(const String &k) {
	return k == "spear" || k == "halberd" || k == "lance" || k == "bow" || k == "xbow" || k == "throw";
}

// UnitMarkers._ring_texture
Ref<ImageTexture> ring_texture(double radius, double width, const Color &color) {
	auto key = std::make_tuple((float)radius, (float)width, color.to_rgba32());
	auto it = R->rings.find(key);
	if (it != R->rings.end()) return it->second;
	double a = radius, b = radius * C.ring_flatten;
	int w = (int)std::ceil(2.0 * (a + width) + 4.0), h = (int)std::ceil(2.0 * (b + width) + 4.0);
	Ref<Image> image = Image::create(w, h, false, Image::FORMAT_RGBA8);
	Vector2 center = Vector2(w, h) * 0.5;
	for (int y = 0; y < h; y++) {
		for (int x = 0; x < w; x++) {
			Vector2 p = Vector2(x + 0.5, y + 0.5) - center;
			double f = (p.x * p.x) / (a * a) + (p.y * p.y) / (b * b) - 1.0;
			double grad = Vector2(2.0 * p.x / (a * a), 2.0 * p.y / (b * b)).length();
			double distance = std::abs(f) / std::max(grad, 0.0001);
			double alpha = std::clamp(width * 0.5 + 0.5 - distance, 0.0, 1.0);
			image->set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha));
		}
	}
	Ref<ImageTexture> tex = ImageTexture::create_from_image(image);
	R->rings[key] = tex;
	return tex;
}

void texture_at(RenderingServer *rs, const RID &canvas, const Ref<Texture2D> &tex, const Vector2 &pos, const Color &tint) {
	if (tex.is_null()) return;
	rs->canvas_item_add_texture_rect(canvas, Rect2(pos, tex->get_size()), tex->get_rid(), false, tint);
}

} // namespace

void UnitPainter::configure(const Dictionary &d) {
	if (!R) R = memnew(Refs);
	C.anchor = d["ANCHOR"];
	C.pivot = d["PIVOT"];
	C.mount_weapon_offset = d["MOUNT_WEAPON_OFFSET"];
	C.sprite_scale = d["SPRITE_SCALE"];
	C.phase_step = d["PHASE_STEP"];
	C.breath_rate = d["BREATH_RATE"];
	C.breath_scale = d["BREATH_SCALE"];
	C.walk_rate = d["WALK_RATE"];
	C.walk_bob = d["WALK_BOB"];
	C.gallop_bob = d["GALLOP_BOB"];
	C.moving_speed = d["MOVING_SPEED"];
	C.lean = d["LEAN"];
	C.spring = d["ATTACK_SPRING_SECONDS"];
	C.flash = d["FLASH_BRIGHTNESS"];
	C.windup_angle = d["WINDUP_ANGLE"];
	C.swing_angle = d["SWING_ANGLE"];
	C.block_angle = d["BLOCK_ANGLE"];
	C.thrust = d["WEAPON_THRUST"];
	C.fleeing_opacity = d["FLEEING_OPACITY"];
	C.shadow = d["SHADOW"];
	C.ring_flatten = d["RING_FLATTEN"];
	C.ring_padding = d["RING_PADDING"];
	C.standard_width = d["STANDARD_WIDTH"];
	C.leader_width = d["LEADER_WIDTH"];
	C.ally_selected = d["ALLY_SELECTED_RING"];
	C.ally_idle = d["ALLY_IDLE_RING"];
	C.enemy_ring = d["ENEMY_RING"];
	C.health_width_per_radius = d["HEALTH_WIDTH_PER_RADIUS"];
	C.health_height = d["HEALTH_HEIGHT"];
	C.health_frame = d["HEALTH_FRAME"];
	C.foot_health_y = d["FOOT_HEALTH_Y"];
	C.mount_health_y = d["MOUNT_HEALTH_Y"];
	C.health_frame_color = d["HEALTH_FRAME_COLOR"];
	C.ally_health = d["ALLY_HEALTH"];
	C.enemy_health = d["ENEMY_HEALTH"];
	C.flee_flag_offset = d["FLEE_FLAG_OFFSET"];
	C.flee_flag_size = d["FLEE_FLAG_SIZE"];
	C.flee_flag_pole = d["FLEE_FLAG_POLE"];
	C.flee_flag_color = d["FLEE_FLAG_COLOR"];
	C.pole_color = d["POLE_COLOR"];
	C.all_groups = d["ALL_GROUPS"];
	C.ready = true;
}

void UnitPainter::release() {
	if (R) {
		memdelete(R);
		R = nullptr;
	}
	C.ready = false;
}

Array UnitPainter::prepare(const PackedFloat64Array &render, const Array &frame, const Rect2 &visible, Object *art) {
	if (!R) R = memnew(Refs);
	R->render = render;
	R->ordinary.clear();
	PackedInt32Array dead, special;
	const double *r = render.ptr();
	const int n = (int)(render.size() / S);
	for (int i = 0; i < n; i++) {
		const double *u = r + i * S;
		int flags = (int)u[10];
		if ((flags & F_GONE) || !visible.has_point(Vector2(u[1], u[2]))) continue;
		if (flags & F_DEAD) {
			if (!(flags & (F_HERO | F_COMPANION)) && !R->baked.count((int64_t)u[0])) dead.push_back(i);
		} else if (flags & (F_HERO | F_COMPANION | F_LEADER)) {
			special.push_back(i);
		} else {
			int64_t id = (int64_t)u[0];
			if (!R->looks.count(id) && art) {
				Dictionary entry = art->call("layers", frame[i]);
				Look look;
				look.body = entry.get(R->k_body, Variant());
				look.weapon = entry.get(R->k_weapon, Variant());
				look.thrust = thrust_kind(entry.get(R->k_kind, String()));
				R->looks[id] = look;
			}
			R->ordinary.push_back(i);
		}
	}
	Array out;
	out.push_back(dead);
	out.push_back(special);
	return out;
}

void UnitPainter::draw_ordinary(const RID &canvas, const Array &plants, const Rect2 &visible, int64_t selection, double time,
		const Dictionary &flashes_in, const Dictionary &attacks_in) {
	ERR_FAIL_COND_MSG(!C.ready || !R, "UnitPainter.configure was not called");
	RenderingServer *rs = RenderingServer::get_singleton();
	std::unordered_set<int64_t> flashes;
	Array fk = flashes_in.keys();
	for (int64_t i = 0; i < fk.size(); i++) flashes.insert((int64_t)fk[i]);
	std::unordered_map<int64_t, double> attacks;
	Array ak = attacks_in.keys();
	for (int64_t i = 0; i < ak.size(); i++) attacks[(int64_t)ak[i]] = (double)attacks_in[ak[i]];
	struct Plant {
		double y;
		Rect2 bounds;
		Ref<Texture2D> texture;
	};
	std::vector<Plant> plant_list;
	plant_list.reserve(plants.size());
	for (int64_t i = 0; i < plants.size(); i++) {
		Dictionary p = plants[i];
		Vector2 pp = p[R->k_position];
		plant_list.push_back({ pp.y, p[R->k_bounds], p[R->k_texture] });
	}
	const double *r = R->render.ptr();
	std::vector<std::pair<double, int>> order;
	order.reserve(R->ordinary.size());
	for (int i : R->ordinary) order.emplace_back(r[i * S + 2], i);
	std::stable_sort(order.begin(), order.end(), [](auto &a, auto &b) { return a.first < b.first; });
	size_t plant_index = 0;
	const Transform2D identity;
	const Color white(1, 1, 1);
	for (auto &o : order) {
		const double *u = r + o.second * S;
		Vector2 position(u[1], u[2]);
		while (plant_index < plant_list.size() && plant_list[plant_index].y < position.y) {
			if (visible.intersects(plant_list[plant_index].bounds)) texture_at(rs, canvas, plant_list[plant_index].texture, plant_list[plant_index].bounds.position, white);
			plant_index++;
		}
		int64_t id = (int64_t)u[0];
		double radius = u[3], facing = u[4], speed = u[5], windup = u[6], health = u[7];
		int64_t side = (int64_t)u[8], group = (int64_t)u[9];
		int flags = (int)u[10];
		bool mounted = flags & F_MOUNTED, fleeing = flags & F_FLEEING, blocking = flags & F_BLOCKING;
		// ring (UnitMarkers.draw_ring)
		Color ring_color = side != 0 ? C.enemy_ring : ((selection == C.all_groups || group == selection) ? C.ally_selected : C.ally_idle);
		Ref<ImageTexture> ring = ring_texture(radius + C.ring_padding, C.standard_width, ring_color);
		texture_at(rs, canvas, ring, position - ring->get_size() * 0.5, white);
		// body and weapon (UnitView._draw_unit)
		const Look &look = R->looks[id];
		double direction = std::cos(facing) < 0.0 ? -1.0 : 1.0;
		double phase = id * C.phase_step;
		double rotation = 0.0;
		Vector2 scale = Vector2(direction, 1.0) * C.sprite_scale;
		Color tint = white;
		rs->canvas_item_add_circle(canvas, position, radius, C.shadow);
		Vector2 drawn = position;
		scale.y *= 1.0 + std::sin(time * C.breath_rate + phase) * C.breath_scale;
		if (speed > C.moving_speed) {
			double bob = mounted ? C.gallop_bob : C.walk_bob;
			drawn.y -= std::abs(std::sin(time * C.walk_rate + phase)) * bob;
			rotation = direction * C.lean;
		}
		if (flashes.count(id)) tint = Color(1.0 + C.flash, 1.0 + C.flash, 1.0 + C.flash);
		if (fleeing) tint.a = C.fleeing_opacity;
		rs->canvas_item_add_set_transform(canvas, Transform2D(rotation, scale, 0.0, drawn));
		texture_at(rs, canvas, look.body, -C.anchor, tint);
		if (look.weapon.is_valid()) {
			Vector2 offset = mounted ? C.mount_weapon_offset : Vector2();
			double weapon_rotation = 0.0;
			double motion = 0.0;
			if (windup >= 0.0) {
				motion = C.windup_angle;
			} else {
				auto a = attacks.find(id);
				if (a != attacks.end()) motion = C.swing_angle * std::clamp((a->second - time) / C.spring, 0.0, 1.0);
			}
			if (blocking) motion = C.block_angle;
			if (look.thrust) offset.x += std::abs(motion) * C.thrust;
			else weapon_rotation = motion;
			Vector2 pivot = (C.pivot - C.anchor + offset) * scale;
			rs->canvas_item_add_set_transform(canvas, Transform2D(rotation + direction * weapon_rotation, scale, 0.0, drawn + pivot.rotated(rotation)));
			texture_at(rs, canvas, look.weapon, -C.pivot, tint);
		}
		rs->canvas_item_add_set_transform(canvas, identity);
		// health bar and flee flag (UnitMarkers.draw_status)
		if (health < 1.0) {
			double width = radius * C.health_width_per_radius;
			double y = mounted ? C.mount_health_y : C.foot_health_y;
			Rect2 bar(position - Vector2(width * 0.5, y), Vector2(width, C.health_height));
			rs->canvas_item_add_rect(canvas, bar.grow(C.health_frame), C.health_frame_color);
			rs->canvas_item_add_rect(canvas, Rect2(bar.position, Vector2(bar.size.x * health, C.health_height)), side == 0 ? C.ally_health : C.enemy_health);
		}
		if (fleeing) {
			Vector2 flag = position + C.flee_flag_offset;
			rs->canvas_item_add_rect(canvas, Rect2(flag - Vector2(C.flee_flag_pole.x, 0), C.flee_flag_pole), C.pole_color);
			rs->canvas_item_add_rect(canvas, Rect2(flag, C.flee_flag_size), C.flee_flag_color);
		}
	}
	for (; plant_index < plant_list.size(); plant_index++) {
		if (visible.intersects(plant_list[plant_index].bounds)) texture_at(rs, canvas, plant_list[plant_index].texture, plant_list[plant_index].bounds.position, white);
	}
}

void UnitPainter::mark_baked(int64_t id) {
	if (!R) R = memnew(Refs);
	R->baked.insert(id);
}

void UnitPainter::forget() {
	if (!R) return;
	R->looks.clear();
	R->baked.clear();
	R->ordinary.clear();
}

void UnitPainter::_bind_methods() {
	ClassDB::bind_static_method("UnitPainter", D_METHOD("configure", "config"), &UnitPainter::configure);
	ClassDB::bind_static_method("UnitPainter", D_METHOD("prepare", "render", "frame", "visible", "art"), &UnitPainter::prepare);
	ClassDB::bind_static_method("UnitPainter", D_METHOD("draw_ordinary", "canvas", "plants", "visible", "selection", "time", "flashes", "attacks"), &UnitPainter::draw_ordinary);
	ClassDB::bind_static_method("UnitPainter", D_METHOD("mark_baked", "id"), &UnitPainter::mark_baked);
	ClassDB::bind_static_method("UnitPainter", D_METHOD("forget"), &UnitPainter::forget);
}
