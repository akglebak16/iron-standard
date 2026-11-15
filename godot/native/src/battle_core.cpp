#include "battle_core.h"
#include "battle_unit.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

using namespace godot;

namespace {

const double INF = std::numeric_limits<double>::infinity();

struct Cfg {
	bool ready = false;
	double slot_edge, flee_dest_pad, flee_speed, flee_exit_pad, arrival_distance, arrival_brake, foot_steer, horse_steer;
	double retarget_min, retarget_random, target_flee_mult, cav_archer_mult, current_mult;
	double backing_slot, mounted_skirm_trigger, archer_melee_buffer, archer_slot_distance, foot_engage, mounted_engage,
			foot_leash, mounted_leash, slot_face, shoot_approach, skirm_close, skirm_approach, skirm_back, skirm_lateral,
			skirm_orbit, skirm_edge, skirm_speed;
	double charge_min_speed, charge_extra_reach, shoot_move_limit, melee_windup, melee_cd_min, melee_cd_max, shoot_cd_min,
			shoot_cd_max, wind_extra;
	double friend_push, enemy_push, min_distance, field_lr, field_top, field_bottom;
} C;

// Engine types cannot be global statics: they would be built at library load, before the engine interface exists.
struct Refs {
	String order_charge;
	Variant k_position = "position", k_radius = "radius", k_group_kind = "group_kind", k_leader = "leader", k_mounted = "mounted",
			k_health = "health_fraction", k_dead = "dead", k_gone = "gone", k_fleeing = "fleeing", k_facing = "facing", k_speed = "speed",
			k_blocking = "blocking", k_windup = "windup", k_look = "look";
	Variant charge, combat;
};
// Variant keys: a String key would be converted to a Variant on every dictionary access.
Refs *R = nullptr;

double num(const Dictionary &d, const char *k) {
	ERR_FAIL_COND_V_MSG(!d.has(k), 0.0, String("BattleCore: missing config ") + k);
	return double(d[k]);
}

enum Mode { UNASSIGNED = 0, SLOT = 1, MELEE = 2, SHOOT = 3, SHOOT_SLOT = 4, SKIRMISH = 5 };
const char *MODE_NAMES[] = { "", "slot", "melee", "shoot", "shootslot", "skirm" };

struct GroupData {
	Vector2 center;
	double direction = 0.0;
	bool charge = false;
	bool backing = false;
};

inline BattleUnit *unit_at(const std::vector<BattleUnit *> &u, int64_t i) {
	return (i >= 0 && i < (int64_t)u.size()) ? u[i] : nullptr;
}

// Group.slot_position
inline Vector2 slot_position(const GroupData &g, const BattleUnit *unit, const Vector2 &arena) {
	Vector2 offset = unit->slot_offset;
	Vector2 pos = g.center + Vector2(-std::sin(g.direction), std::cos(g.direction)) * offset.x + Vector2(std::cos(g.direction), std::sin(g.direction)) * offset.y;
	return pos.clamp(Vector2(1, 1) * C.slot_edge, arena - Vector2(1, 1) * C.slot_edge);
}

// Targeting.current
inline BattleUnit *current_target(const std::vector<BattleUnit *> &u, const BattleUnit *unit) {
	BattleUnit *t = unit_at(u, unit->target_index);
	return (t && t->side != unit->side && !t->dead && !t->gone) ? t : nullptr;
}

// Targeting.choose (linear, lowest index on ties)
BattleUnit *choose(const std::vector<BattleUnit *> &u, const BattleUnit *unit) {
	BattleUnit *previous = current_target(u, unit);
	BattleUnit *best = nullptr;
	double best_distance = INF;
	const bool melee_cavalry = unit->mounted && unit->attack_range <= 0.0;
	for (BattleUnit *enemy : u) {
		if (enemy->side == unit->side || enemy->dead || enemy->gone) continue;
		double distance = unit->position.distance_to(enemy->position);
		if (enemy->fleeing) distance *= C.target_flee_mult;
		if (melee_cavalry && enemy->attack_range > 0.0 && !enemy->mounted) distance *= C.cav_archer_mult;
		if (enemy == previous) distance *= C.current_mult;
		if (distance < best_distance) {
			best_distance = distance;
			best = enemy;
		}
	}
	return best;
}

// Targeting.refresh
BattleUnit *refresh(const std::vector<BattleUnit *> &u, BattleUnit *unit, double dt, RandomNumberGenerator *rng) {
	unit->target_timer -= dt;
	BattleUnit *target = current_target(u, unit);
	if (unit->target_timer <= 0.0 || (unit->target_index >= 0 && target == nullptr)) {
		unit->target_timer = C.retarget_min + rng->randf() * C.retarget_random;
		target = choose(u, unit);
		unit->target_index = target ? target->battle_index : -1;
	}
	return target;
}

// AiDecision.plan_into
void plan_into(BattleUnit *unit, const GroupData &group, BattleUnit *enemy, const Vector2 &arena, const Vector2 &slot) {
	double slot_distance = unit->position.distance_to(slot);
	double distance = enemy ? (double)unit->position.distance_to(enemy->position) : INF;
	double reach = unit->collision_radius + (enemy ? enemy->collision_radius : 0.0) + unit->melee_reach;
	int mode = SLOT;
	if (group.backing && slot_distance > C.backing_slot) {
	} else if (unit->attack_range > 0.0) {
		if (unit->mounted) {
			if (enemy && (group.charge || distance < unit->attack_range * C.mounted_skirm_trigger)) mode = SKIRMISH;
		} else if (enemy && distance < reach + C.archer_melee_buffer) {
			mode = MELEE;
		} else if (enemy && group.charge) {
			mode = SHOOT;
		} else if (enemy && distance < unit->attack_range && slot_distance < C.archer_slot_distance) {
			mode = SHOOT_SLOT;
		}
	} else if (enemy) {
		if (group.charge) {
			mode = MELEE;
		} else {
			double engage = unit->mounted ? C.mounted_engage : C.foot_engage;
			double leash = unit->mounted ? C.mounted_leash : C.foot_leash;
			if (distance < engage && (double)enemy->position.distance_to(slot) < leash) mode = MELEE;
		}
	}
	Vector2 destination = slot;
	double face = slot_distance < C.slot_face ? group.direction : (double)(slot - unit->position).angle();
	double speed_scale = 1.0;
	if (mode == MELEE) {
		face = (enemy->position - unit->position).angle();
		destination = distance > reach ? enemy->position : unit->position;
	} else if (mode == SHOOT || mode == SHOOT_SLOT) {
		face = (enemy->position - unit->position).angle();
		if (mode == SHOOT) destination = distance > unit->attack_range * C.shoot_approach ? enemy->position : unit->position;
	} else if (mode == SKIRMISH) {
		face = (enemy->position - unit->position).angle();
		Vector2 away = (unit->position - enemy->position).normalized();
		double side = (unit->id % 2) ? 1.0 : -1.0;
		if (distance < unit->attack_range * C.skirm_close) {
			destination = unit->position + away * C.skirm_back + Vector2(-away.y, away.x) * C.skirm_lateral * side;
		} else if (distance > unit->attack_range * C.skirm_approach) {
			destination = enemy->position;
		} else {
			destination = unit->position + Vector2(-away.y, away.x) * C.skirm_orbit * side;
		}
		double margin = C.skirm_edge;
		if (destination.x < margin || destination.x > arena.x - margin || destination.y < margin || destination.y > arena.y - margin) destination = arena * 0.5;
		speed_scale = C.skirm_speed;
	}
	if (unit->ai_mode_code != mode || unit->ai_mode.is_empty() != (mode == UNASSIGNED)) unit->set_ai_mode(MODE_NAMES[mode]);
	unit->plan_destination = destination;
	unit->plan_face = face;
	unit->plan_speed = speed_scale;
	unit->plan_distance = distance;
}

// Charge.can_hit
inline bool can_charge(const BattleUnit *a, const BattleUnit *t) {
	if (!a->mounted || a->attack_range > 0.0 || a->charge_cooldown > 0.0 || (double)a->velocity.length() <= C.charge_min_speed) return false;
	if (!t || t->side == a->side || t->dead || t->gone) return false;
	return (double)a->position.distance_to(t->position) < a->collision_radius + t->collision_radius + a->melee_reach + C.charge_extra_reach;
}

// Movement._steer
inline void steer(BattleUnit *unit, const Vector2 &destination, double speed, double dt) {
	Vector2 delta = destination - unit->position;
	double distance = delta.length();
	Vector2 desired;
	if (distance > C.arrival_distance && speed > 0.0) desired = delta / distance * MIN(speed, distance * C.arrival_brake);
	double rate = unit->mounted ? C.horse_steer : C.foot_steer;
	unit->velocity = unit->velocity.lerp(desired, MIN(1.0, rate * dt));
	if (unit->velocity.length_squared() > 0.0) unit->facing = unit->velocity.angle();
}

// CombatStep._can_shoot
inline bool can_shoot(const BattleUnit *unit, double distance) {
	if (unit->attack_range <= 0.0 || distance >= unit->attack_range) return false;
	if (unit->ai_mode_code == SKIRMISH) return true;
	return (unit->ai_mode_code == SHOOT || unit->ai_mode_code == SHOOT_SLOT) && (double)unit->velocity.length() < C.shoot_move_limit;
}

// CombatStep.advance_unit for AI units (ai_mode is always assigned here)
void advance_unit(Object *battle, const std::vector<BattleUnit *> &u, BattleUnit *unit, BattleUnit *target, double distance, double dt, const Ref<RandomNumberGenerator> &rng) {
	if (unit->dead || unit->gone || unit->fleeing || unit->hero) return;
	if (target && unit->attack_cooldown <= 0.0) {
		if (unit->ai_mode_code == MELEE && distance <= unit->collision_radius + target->collision_radius + unit->melee_reach && unit->ai_windup < 0.0) {
			unit->ai_windup = C.melee_windup;
			unit->ai_wind_target_index = target->battle_index;
			unit->attack_cooldown = unit->attack_interval * rng->randf_range(C.melee_cd_min, C.melee_cd_max);
		} else if (can_shoot(unit, distance)) {
			Variant shot = R->combat.call("shoot", unit, target, rng);
			battle->call("launch_projectile", shot);
			unit->attack_cooldown = unit->attack_interval * rng->randf_range(C.shoot_cd_min, C.shoot_cd_max);
		}
	}
	// CombatStep._advance_wind
	if (unit->ai_windup < 0.0) return;
	unit->ai_windup -= dt;
	if (unit->ai_windup >= 0.0) return;
	BattleUnit *t = unit_at(u, unit->ai_wind_target_index);
	if (t && !t->dead && !t->gone && (double)unit->position.distance_to(t->position) < unit->collision_radius + t->collision_radius + unit->melee_reach + C.wind_extra) {
		R->combat.call("strike", battle, unit, t, rng);
	}
	unit->ai_wind_target_index = -1;
}

// collision_grid.gd
struct Grid {
	const double PAD = 480.0, CELL = 40.0;
	int w = 0, h = 0;
	std::vector<std::vector<int>> cells;
	std::vector<int> at;
	int cell(const Vector2 &p) const {
		int x = CLAMP((int)std::floor((p.x + PAD) / CELL), 0, w - 1);
		int y = CLAMP((int)std::floor((p.y + PAD) / CELL), 0, h - 1);
		return y * w + x;
	}
	void init(const std::vector<Vector2> &pos, const Vector2 &arena) {
		w = (int)std::ceil((arena.x + PAD * 2.0) / CELL) + 1;
		h = (int)std::ceil((arena.y + PAD * 2.0) / CELL) + 1;
		cells.assign(w * h, {});
		at.resize(pos.size());
		for (size_t i = 0; i < pos.size(); i++) {
			at[i] = cell(pos[i]);
			cells[at[i]].push_back((int)i);
		}
	}
	void move(int i, const Vector2 &p) {
		int c = cell(p);
		if (c == at[i]) return;
		auto &b = cells[at[i]];
		b.erase(std::find(b.begin(), b.end(), i));
		cells[c].push_back(i);
		at[i] = c;
	}
	void query(const Vector2 &p, double r, int first, std::vector<int> &out) const {
		out.clear();
		int x0 = CLAMP((int)std::floor((p.x - r + PAD) / CELL), 0, w - 1), x1 = CLAMP((int)std::floor((p.x + r + PAD) / CELL), 0, w - 1);
		int y0 = CLAMP((int)std::floor((p.y - r + PAD) / CELL), 0, h - 1), y1 = CLAMP((int)std::floor((p.y + r + PAD) / CELL), 0, h - 1);
		for (int y = y0; y <= y1; y++)
			for (int x = x0; x <= x1; x++)
				for (int i : cells[y * w + x])
					if (i >= first) out.push_back(i);
		std::sort(out.begin(), out.end());
	}
};

// Movement._resolve_packed: the plain pair loop, same pair order and Vector2 arithmetic.
void collide(Object *battle, const std::vector<BattleUnit *> &u, const Vector2 &arena, Object *wall, const PackedVector2Array &trunk_pos, const PackedFloat64Array &trunk_rad) {
	const double SLACK = 10.0;
	const size_t n = u.size();
	std::vector<Vector2> pos(n);
	double max_radius = 0.0;
	for (size_t i = 0; i < n; i++) {
		pos[i] = u[i]->position;
		max_radius = MAX(max_radius, u[i]->collision_radius);
	}
	Grid grid;
	grid.init(pos, arena);
	std::vector<int> cand;
	const double slack2 = SLACK * SLACK;
	for (size_t i = 0; i < n; i++) {
		BattleUnit *a = u[i];
		if (a->dead || a->gone) continue;
		Vector2 pa = pos[i];
		const double ra = a->collision_radius, ma = a->mass;
		size_t next = i + 1;
		while (next < n) {
			Vector2 origin = pa;
			grid.query(origin, ra + max_radius + SLACK, (int)next, cand);
			bool moved_far = false;
			for (int j : cand) {
				next = j + 1;
				BattleUnit *b = u[j];
				if (b->dead || b->gone) continue;
				Vector2 pb = pos[j];
				Vector2 difference = pb - pa;
				double radius = ra + b->collision_radius;
				if (std::abs((double)difference.x) >= radius || std::abs((double)difference.y) >= radius || (double)difference.length_squared() >= radius * radius) continue;
				double distance = MAX((double)difference.length(), C.min_distance);
				Vector2 normal = difference / distance;
				double strength = a->side == b->side ? C.friend_push : C.enemy_push;
				double overlap = (radius - distance) * strength;
				double mb = b->mass;
				double total = ma + mb;
				pa -= normal * overlap * mb / total;
				pb += normal * overlap * ma / total;
				pos[j] = pb;
				grid.move(j, pb);
				if ((double)pa.distance_squared_to(origin) > slack2) {
					moved_far = true;
					break;
				}
			}
			if (!moved_far) break;
		}
		a->position = pa;
		if (wall) {
			wall->call("constrain", a);
		}
		// Movement._resolve_trunk_collisions
		for (int t = 0; t < trunk_pos.size(); t++) {
			double reach = a->collision_radius + trunk_rad[t];
			Vector2 offset = a->position - trunk_pos[t];
			double d2 = offset.length_squared();
			if (d2 >= reach * reach) continue;
			Vector2 normal = d2 == 0.0 ? Vector2(1, 0) : offset / std::sqrt(d2);
			a->position = trunk_pos[t] + normal * reach;
		}
		if (!a->fleeing) a->position.x = CLAMP((double)a->position.x, C.field_lr, (double)arena.x - C.field_lr);
		a->position.y = CLAMP((double)a->position.y, C.field_top, (double)arena.y - C.field_bottom);
		pos[i] = a->position;
		grid.move((int)i, a->position);
	}
}

} // namespace

void BattleCore::configure(const Dictionary &d, const Variant &charge_rules, const Variant &combat_rules) {
	C.slot_edge = num(d, "SLOT_EDGE");
	C.flee_dest_pad = num(d, "FLEE_DESTINATION_PADDING");
	C.flee_speed = num(d, "FLEE_SPEED_MULTIPLIER");
	C.flee_exit_pad = num(d, "FLEE_EXIT_PADDING");
	C.arrival_distance = num(d, "ARRIVAL_DISTANCE");
	C.arrival_brake = num(d, "ARRIVAL_BRAKE");
	C.foot_steer = num(d, "FOOT_STEERING_RATE");
	C.horse_steer = num(d, "HORSE_STEERING_RATE");
	C.retarget_min = num(d, "RETARGET_MIN_SECONDS");
	C.retarget_random = num(d, "RETARGET_RANDOM_SECONDS");
	C.target_flee_mult = num(d, "TARGET_FLEE_DISTANCE_MULTIPLIER");
	C.cav_archer_mult = num(d, "CAVALRY_ARCHER_TARGET_MULTIPLIER");
	C.current_mult = num(d, "CURRENT_TARGET_MULTIPLIER");
	C.backing_slot = num(d, "AI_BACKING_SLOT_DISTANCE");
	C.mounted_skirm_trigger = num(d, "AI_MOUNTED_SKIRMISH_TRIGGER");
	C.archer_melee_buffer = num(d, "AI_ARCHER_MELEE_BUFFER");
	C.archer_slot_distance = num(d, "AI_ARCHER_SLOT_DISTANCE");
	C.foot_engage = num(d, "AI_FOOT_ENGAGE_DISTANCE");
	C.mounted_engage = num(d, "AI_MOUNTED_ENGAGE_DISTANCE");
	C.foot_leash = num(d, "AI_FOOT_LEASH_DISTANCE");
	C.mounted_leash = num(d, "AI_MOUNTED_LEASH_DISTANCE");
	C.slot_face = num(d, "AI_SLOT_FACE_DISTANCE");
	C.shoot_approach = num(d, "AI_SHOOT_APPROACH_RANGE");
	C.skirm_close = num(d, "AI_SKIRMISH_CLOSE_RANGE");
	C.skirm_approach = num(d, "AI_SKIRMISH_APPROACH_RANGE");
	C.skirm_back = num(d, "AI_SKIRMISH_BACK_OFFSET");
	C.skirm_lateral = num(d, "AI_SKIRMISH_LATERAL_OFFSET");
	C.skirm_orbit = num(d, "AI_SKIRMISH_ORBIT_OFFSET");
	C.skirm_edge = num(d, "AI_SKIRMISH_EDGE_MARGIN");
	C.skirm_speed = num(d, "AI_SKIRMISH_SPEED_MULTIPLIER");
	C.charge_min_speed = num(d, "CHARGE_MIN_SPEED");
	C.charge_extra_reach = num(d, "CHARGE_EXTRA_REACH");
	C.shoot_move_limit = num(d, "SHOOT_MOVE_SPEED_LIMIT");
	C.melee_windup = num(d, "AI_MELEE_WINDUP_SECONDS");
	C.melee_cd_min = num(d, "AI_MELEE_COOLDOWN_MIN");
	C.melee_cd_max = num(d, "AI_MELEE_COOLDOWN_MAX");
	C.shoot_cd_min = num(d, "AI_SHOOT_COOLDOWN_MIN");
	C.shoot_cd_max = num(d, "AI_SHOOT_COOLDOWN_MAX");
	C.wind_extra = num(d, "AI_WIND_HIT_EXTRA_REACH");
	C.friend_push = num(d, "FRIEND_COLLISION_PUSH");
	C.enemy_push = num(d, "ENEMY_COLLISION_PUSH");
	C.min_distance = num(d, "MIN_COLLISION_DISTANCE");
	C.field_lr = num(d, "FIELD_LEFT_RIGHT_MARGIN");
	C.field_top = num(d, "FIELD_TOP_MARGIN");
	C.field_bottom = num(d, "FIELD_BOTTOM_MARGIN");
	if (!R) R = memnew(Refs);
	R->order_charge = d["ORDER_CHARGE"];
	R->charge = charge_rules;
	R->combat = combat_rules;
	C.ready = true;
}

bool BattleCore::is_configured() { return C.ready; }

void BattleCore::release() {
	if (R) {
		memdelete(R);
		R = nullptr;
	}
	C.ready = false;
}

// Movement._step with the battle RNG (AI units); the hero is driven by HeroControl.
void BattleCore::step(Object *battle, const Array &units, const Array &groups, const Vector2 &arena, double dt,
		const Ref<RandomNumberGenerator> &rng, Object *wall, const PackedVector2Array &trunk_pos, const PackedFloat64Array &trunk_rad) {
	ERR_FAIL_COND_MSG(!C.ready, "BattleCore.configure was not called");
	if (dt <= 0.0) return;
	const int64_t n = units.size();
	std::vector<BattleUnit *> u((size_t)n);
	for (int64_t i = 0; i < n; i++) {
		u[i] = Object::cast_to<BattleUnit>(units[i].operator Object *());
		ERR_FAIL_NULL_MSG(u[i], "BattleCore.step: every unit must extend BattleUnit");
	}
	GroupData g[2][3];
	for (int s = 0; s < 2; s++) {
		Array side_groups = groups[s];
		for (int k = 0; k < 3 && k < side_groups.size(); k++) {
			Object *o = side_groups[k];
			g[s][k].center = o->get("center");
			g[s][k].direction = o->get("direction");
			g[s][k].charge = String(o->get("order")) == R->order_charge;
			g[s][k].backing = o->get("backing");
		}
	}
	RandomNumberGenerator *r = rng.ptr();
	for (int64_t i = 0; i < n; i++) {
		BattleUnit *unit = u[i];
		if (unit->dead || unit->gone || unit->hero) continue;
		unit->charge_cooldown -= dt;
		unit->attack_cooldown -= dt;
		const GroupData &group = g[unit->side][unit->group_kind];
		Vector2 destination = slot_position(group, unit, arena);
		double velocity_scale = 1.0;
		double ai_face = unit->facing;
		BattleUnit *target = nullptr;
		double target_distance = INF;
		if (unit->fleeing) {
			destination = Vector2(unit->side == 1 ? arena.x + C.flee_dest_pad : -C.flee_dest_pad, unit->position.y);
			velocity_scale = C.flee_speed;
		} else {
			target = refresh(u, unit, dt, r);
			plan_into(unit, group, target, arena, destination);
			destination = unit->plan_destination;
			velocity_scale = unit->plan_speed;
			ai_face = unit->plan_face;
			target_distance = unit->plan_distance;
			if (unit->ai_mode_code == MELEE && target && can_charge(unit, target)) {
				unit->facing = ai_face;
				R->charge.call("hit", battle, unit, target, rng);
				if (destination != unit->position) destination = target->position;
			}
		}
		if (wall) destination = wall->call("route", unit, destination);
		steer(unit, destination, unit->speed * velocity_scale, dt);
		if (unit->fleeing) {
			unit->facing = unit->velocity.angle();
			if (unit->position.x < -C.flee_exit_pad || unit->position.x > arena.x + C.flee_exit_pad) unit->gone = true;
		} else {
			unit->facing = ai_face;
			advance_unit(battle, u, unit, target, target_distance, dt, rng);
		}
		unit->position += unit->velocity * dt;
	}
	collide(battle, u, arena, wall, trunk_pos, trunk_rad);
}

// State.centroid: mean position of a side's fighting units (not dead, gone or fleeing).
Vector2 BattleCore::centroid(const Array &units, int64_t side) {
	Vector2 total;
	int64_t count = 0;
	for (int64_t i = 0; i < units.size(); i++) {
		BattleUnit *x = Object::cast_to<BattleUnit>(units[i].operator Object *());
		if (!x || x->side != side || x->dead || x->gone || x->fleeing) continue;
		total += x->position;
		count++;
	}
	return count ? total / count : Vector2(INFINITY, INFINITY);
}

double BattleCore::nearest_foe_distance(const Array &units, const Vector2 &point, int64_t side) {
	double best = INF;
	for (int64_t i = 0; i < units.size(); i++) {
		BattleUnit *x = Object::cast_to<BattleUnit>(units[i].operator Object *());
		if (!x || x->side != side || x->dead || x->gone || x->fleeing) continue;
		best = MIN(best, (double)point.distance_to(x->position));
	}
	return best;
}

// Group.active_units() is not empty: someone in the group still fights.
bool BattleCore::has_active(const Array &units) {
	for (int64_t i = 0; i < units.size(); i++) {
		BattleUnit *x = Object::cast_to<BattleUnit>(units[i].operator Object *());
		if (x && !x->dead && !x->gone && !x->fleeing && !x->hero) return true;
	}
	return false;
}

// The common part of State.kill: morale of everyone near a fallen unit.
void BattleCore::death_morale(const Array &units, Object *target_object, double radius, double leader_loss, double ally_loss, double ally_loss_per_tier, double enemy_bonus) {
	BattleUnit *target = Object::cast_to<BattleUnit>(target_object);
	ERR_FAIL_NULL(target);
	for (int64_t i = 0; i < units.size(); i++) {
		BattleUnit *unit = Object::cast_to<BattleUnit>(units[i].operator Object *());
		if (!unit || unit->dead || unit->gone || (double)unit->position.distance_to(target->position) > radius) continue;
		if (unit->side == target->side) {
			unit->morale -= (target->leader || target->hero) ? leader_loss : ally_loss + target->tier * ally_loss_per_tier;
		} else {
			unit->morale = MIN(unit->base_morale, unit->morale + enemy_bonus);
		}
	}
}

// Session._unit_values for every unit: a copy of the unit's template with the changing fields filled in.
static Dictionary unit_dictionary(BattleUnit *u, const Dictionary &t, const Dictionary &look) {
	Dictionary d = t.duplicate();
	d.set(R->k_position, u->position);
	d.set(R->k_radius, u->collision_radius);
	d.set(R->k_group_kind, u->group_kind);
	d.set(R->k_leader, u->leader);
	d.set(R->k_mounted, u->mounted);
	d.set(R->k_health, u->max_hp > 0.0 ? CLAMP(u->hp / u->max_hp, 0.0, 1.0) : 0.0);
	d.set(R->k_dead, u->dead);
	d.set(R->k_gone, u->gone);
	d.set(R->k_fleeing, u->fleeing);
	d.set(R->k_facing, u->facing);
	d.set(R->k_speed, (double)u->velocity.length());
	d.set(R->k_blocking, u->blocking);
	d.set(R->k_windup, u->hero ? u->attack_windup : u->ai_windup);
	d.set(R->k_look, look.duplicate());
	return d;
}

Array BattleCore::unit_values(const Array &units, const Array &templates, const Array &looks) {
	if (!R) R = memnew(Refs);
	Array out;
	out.resize(units.size());
	for (int64_t i = 0; i < units.size(); i++) {
		BattleUnit *u = Object::cast_to<BattleUnit>(units[i].operator Object *());
		out[i] = unit_dictionary(u, templates[i], looks[i]);
	}
	return out;
}

// For the live view, which draws from render_data(): an ordinary living fighter keeps the dictionary it got when it
// last changed kind (its moving fields go stale), a corpse keeps its dictionary while it lies still. Heroes, companions
// and leaders get a fresh one every frame. Dictionaries are never changed once made, so held references stay valid.
// cache: dictionaries by unit index; kinds: PackedByteArray-like Array of the kind each was made for.
Array BattleCore::frame_values(const Array &units, const Array &templates, const Array &looks, Array cache, Array kinds) {
	if (!R) R = memnew(Refs);
	const int64_t n = units.size();
	if (cache.size() < n) {
		cache.resize(n);
		kinds.resize(n);
	}
	Array out;
	out.resize(n);
	for (int64_t i = 0; i < n; i++) {
		BattleUnit *u = Object::cast_to<BattleUnit>(units[i].operator Object *());
		int64_t kind = (u->hero || u->is_companion || u->leader) ? 0 : (u->gone ? 3 : (u->dead ? 2 : 1));
		Variant cached = cache[i];
		bool keep = kind != 0 && cached.get_type() == Variant::DICTIONARY && (int64_t)kinds[i] == kind;
		if (keep && kind == 2) keep = Vector2(Dictionary(cached).get(R->k_position, Vector2())) == u->position;
		if (!keep) {
			cached = unit_dictionary(u, templates[i], looks[i]);
			cache[i] = cached;
			kinds[i] = kind;
		}
		out[i] = cached;
	}
	return out;
}

// The totals Session.snapshot gathers in one pass: [counts, focus sums, focus counts, enemy strength, ally strength, group strengths].
Array BattleCore::frame_stats(const Array &units, int64_t group_kinds) {
	int64_t counts[2] = { 0, 0 }, focus_count[2] = { 0, 0 };
	Vector2 focus_sum[2];
	double enemy = 0.0, ally = 0.0;
	PackedFloat64Array groups;
	groups.resize(group_kinds);
	for (int64_t i = 0; i < units.size(); i++) {
		BattleUnit *u = Object::cast_to<BattleUnit>(units[i].operator Object *());
		if (!u || u->dead || u->gone) continue;
		counts[u->side] += 1;
		if (u->fleeing) continue;
		focus_sum[u->side] += u->position;
		focus_count[u->side] += 1;
		if (u->side == 1) {
			enemy += u->weight;
		} else {
			ally += u->weight;
			if (!u->hero && u->group_kind >= 0 && u->group_kind < group_kinds) groups[u->group_kind] = groups[u->group_kind] + u->weight;
		}
	}
	Array c, fs, fc;
	c.push_back(counts[0]);
	c.push_back(counts[1]);
	fs.push_back(focus_sum[0]);
	fs.push_back(focus_sum[1]);
	fc.push_back(focus_count[0]);
	fc.push_back(focus_count[1]);
	Array out;
	out.push_back(c);
	out.push_back(fs);
	out.push_back(fc);
	out.push_back(enemy);
	out.push_back(ally);
	out.push_back(groups);
	return out;
}

// Drawing fields of every unit, RENDER_STRIDE values each (see unit_painter.h), for the native painter.
PackedFloat64Array BattleCore::render_data(const Array &units) {
	PackedFloat64Array out;
	const int S = 12;
	out.resize(units.size() * S);
	double *w = out.ptrw();
	for (int64_t i = 0; i < units.size(); i++) {
		BattleUnit *u = Object::cast_to<BattleUnit>(units[i].operator Object *());
		double *r = w + i * S;
		r[0] = (double)u->id;
		r[1] = u->position.x;
		r[2] = u->position.y;
		r[3] = u->collision_radius;
		r[4] = u->facing;
		r[5] = u->velocity.length();
		r[6] = u->hero ? u->attack_windup : u->ai_windup;
		r[7] = u->max_hp > 0.0 ? CLAMP(u->hp / u->max_hp, 0.0, 1.0) : 0.0;
		r[8] = (double)u->side;
		r[9] = (double)u->group_kind;
		r[10] = (double)((u->mounted ? 1 : 0) | (u->fleeing ? 2 : 0) | (u->dead ? 4 : 0) | (u->gone ? 8 : 0) | (u->hero ? 16 : 0) |
				(u->is_companion ? 32 : 0) | (u->leader ? 64 : 0) | (u->blocking ? 128 : 0));
		r[11] = 0.0;
	}
	return out;
}

void BattleCore::_bind_methods() {
	ClassDB::bind_static_method("BattleCore", D_METHOD("configure", "config", "charge_rules", "combat_rules"), &BattleCore::configure);
	ClassDB::bind_static_method("BattleCore", D_METHOD("is_configured"), &BattleCore::is_configured);
	ClassDB::bind_static_method("BattleCore", D_METHOD("step", "battle", "units", "groups", "arena", "dt", "rng", "wall", "trunk_positions", "trunk_radii"), &BattleCore::step);
	ClassDB::bind_static_method("BattleCore", D_METHOD("centroid", "units", "side"), &BattleCore::centroid);
	ClassDB::bind_static_method("BattleCore", D_METHOD("nearest_foe_distance", "units", "point", "side"), &BattleCore::nearest_foe_distance);
	ClassDB::bind_static_method("BattleCore", D_METHOD("has_active", "units"), &BattleCore::has_active);
	ClassDB::bind_static_method("BattleCore", D_METHOD("death_morale", "units", "target", "radius", "leader_loss", "ally_loss", "ally_loss_per_tier", "enemy_bonus"), &BattleCore::death_morale);
	ClassDB::bind_static_method("BattleCore", D_METHOD("unit_values", "units", "templates", "looks"), &BattleCore::unit_values);
	ClassDB::bind_static_method("BattleCore", D_METHOD("frame_values", "units", "templates", "looks", "cache", "kinds"), &BattleCore::frame_values);
	ClassDB::bind_static_method("BattleCore", D_METHOD("frame_stats", "units", "group_kinds"), &BattleCore::frame_stats);
	ClassDB::bind_static_method("BattleCore", D_METHOD("render_data", "units"), &BattleCore::render_data);
}
