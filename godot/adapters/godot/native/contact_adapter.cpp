#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include "../../../runtime/simulation/native/contact_solver.hpp"

namespace godot {
class IronContactKernel : public RefCounted {
    GDCLASS(IronContactKernel, RefCounted)
    iron::ContactSolver solver;
    bool configured = false;
    static std::vector<iron::Vec2> vectors(const PackedVector2Array &array) {
        std::vector<iron::Vec2> out(array.size());
        const Vector2 *values = array.ptr();
        for (int i = 0; i < array.size(); ++i) out[i] = {values[i].x, values[i].y};
        return out;
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("configure", "parameters", "obstacles", "radii", "gaps"), &IronContactKernel::configure);
        ClassDB::bind_method(D_METHOD("solve", "positions", "velocities", "radii", "masses", "sides", "live", "fleeing"), &IronContactKernel::solve);
    }
public:
    bool configure(const PackedFloat64Array &parameters, const PackedVector2Array &obstacles,
                   const PackedFloat64Array &radii, const PackedVector2Array &gaps) {
        configured = false;
        if (parameters.size() != 15 || obstacles.size() != radii.size() || obstacles.size() > 100000) return false;
        const double *p = parameters.ptr();
        for (int i = 0; i < 15; ++i) if (i != 11 && !std::isfinite(p[i])) return false;
        if (p[0] <= 0 || p[1] <= 0 || p[0] > 10000 || p[1] > 10000 || p[2] < 0 || p[2] > 10000 || p[3] < 10 || p[4] < 0 || p[5] <= 0 || std::isnan(p[11])) return false;
        for (int i = 0; i < obstacles.size(); ++i) if (!obstacles[i].is_finite() || !std::isfinite(radii[i]) || radii[i] < 0) return false;
        for (int i = 0; i < gaps.size(); ++i) if (!gaps[i].is_finite() || gaps[i].x > gaps[i].y) return false;
        iron::ContactParameters config{p[0],p[1],p[2],p[3],p[4],p[5],p[6],p[7],p[8],p[9],p[10],p[11],p[12],p[13],p[14]};
        std::vector<double> obstacle_radii;
        if (radii.size()) obstacle_radii.assign(radii.ptr(), radii.ptr() + radii.size());
        solver.configure(config, vectors(obstacles), std::move(obstacle_radii), vectors(gaps));
        configured = true;
        return true;
    }
    Array solve(const PackedVector2Array &positions, const PackedVector2Array &velocities,
                const PackedFloat64Array &radii, const PackedFloat64Array &masses,
                const PackedInt32Array &sides, const PackedByteArray &live, const PackedByteArray &fleeing) {
        const int64_t n = positions.size();
        if (!configured || n > 100000 || velocities.size() != n || radii.size() != n || masses.size() != n || sides.size() != n || live.size() != n || fleeing.size() != n) return {};
        solver.resize(int(n));
        const Vector2 *pos = positions.ptr(), *vel = velocities.ptr();
        const double *rad = radii.ptr(), *mass = masses.ptr();
        const int32_t *side = sides.ptr(); const uint8_t *active = live.ptr(), *flee = fleeing.ptr();
        for (int i = 0; i < n; ++i) {
            if (!pos[i].is_finite() || !vel[i].is_finite() || !std::isfinite(rad[i]) || rad[i] < 0 || !std::isfinite(mass[i]) || mass[i] <= 0 || side[i] < 0 || side[i] > 1) return {};
            solver.positions[i] = {pos[i].x,pos[i].y}; solver.velocities[i] = {vel[i].x,vel[i].y};
            solver.radii[i] = rad[i]; solver.masses[i] = mass[i]; solver.sides[i] = side[i];
            solver.live[i] = active[i]; solver.fleeing[i] = flee[i];
        }
        solver.solve();
        PackedVector2Array result_positions, result_velocities;
        result_positions.resize(n); result_velocities.resize(n);
        Vector2 *out_pos = result_positions.ptrw(), *out_vel = result_velocities.ptrw();
        for (int i = 0; i < n; ++i) {
            out_pos[i] = Vector2(solver.positions[i].x,solver.positions[i].y);
            out_vel[i] = Vector2(solver.velocities[i].x,solver.velocities[i].y);
        }
        Array result; result.push_back(result_positions); result.push_back(result_velocities); return result;
    }
};
void initialize_contacts(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<IronContactKernel>();
}
void terminate_contacts(ModuleInitializationLevel) {}
}

extern "C" GDExtensionBool GDE_EXPORT iron_contacts_init(GDExtensionInterfaceGetProcAddress get_address,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    godot::GDExtensionBinding::InitObject binding(get_address,library,initialization);
    binding.register_initializer(godot::initialize_contacts);
    binding.register_terminator(godot::terminate_contacts);
    binding.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return binding.init();
}
