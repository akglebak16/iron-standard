#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
namespace godot {
void register_contact_kernel();
void register_movement_kernel();
void register_column_kernel();
void register_battle_sprites();
void register_battle_effects();
void initialize_iron(ModuleInitializationLevel level) {
  if (level != MODULE_INITIALIZATION_LEVEL_SCENE)
    return;
  register_contact_kernel();
  register_movement_kernel();
  register_column_kernel();
  register_battle_sprites();
  register_battle_effects();
}
void terminate_iron(ModuleInitializationLevel) {}
} // namespace godot
extern "C" GDExtensionBool GDE_EXPORT
iron_contacts_init(GDExtensionInterfaceGetProcAddress get_address,
                   GDExtensionClassLibraryPtr library,
                   GDExtensionInitialization *initialization) {
  godot::GDExtensionBinding::InitObject binding(get_address, library,
                                                initialization);
  binding.register_initializer(godot::initialize_iron);
  binding.register_terminator(godot::terminate_iron);
  binding.set_minimum_library_initialization_level(
      godot::MODULE_INITIALIZATION_LEVEL_SCENE);
  return binding.init();
}
