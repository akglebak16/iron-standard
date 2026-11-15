#include "battle_core.h"
#include "battle_unit.h"
#include "unit_painter.h"
#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_battle_core(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
	GDREGISTER_CLASS(BattleUnit);
	GDREGISTER_CLASS(BattleCore);
	GDREGISTER_CLASS(UnitPainter);
}

void uninitialize_battle_core(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		BattleCore::release();
		UnitPainter::release();
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT battle_core_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_battle_core);
	init_obj.register_terminator(uninitialize_battle_core);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
