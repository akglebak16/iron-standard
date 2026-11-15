# Native battle core (GDExtension). Build:
#   cmake -S godot/native -B build -DGODOT_CPP_DIR=/path/to/godot-cpp -DCMAKE_BUILD_TYPE=Release && cmake --build build -j
# The library lands in godot/bin/; godot/battle_core.gdextension points the engine at it.
cmake_minimum_required(VERSION 3.17)
project(battle_core LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(GODOT_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/godot-cpp" CACHE PATH "godot-cpp checkout (branch 4.5)")
set(GODOTCPP_TARGET template_release CACHE STRING "")
add_subdirectory(${GODOT_CPP_DIR} godot-cpp EXCLUDE_FROM_ALL)
add_library(battle_core SHARED src/register_types.cpp src/battle_unit.cpp src/battle_core.cpp src/unit_painter.cpp)
target_link_libraries(battle_core PRIVATE godot::cpp)
# Results must match GDScript bit for bit: no fast-math, no fused multiply-add.
if(MSVC)
	target_compile_options(battle_core PRIVATE /fp:precise)
else()
	target_compile_options(battle_core PRIVATE -ffp-contract=off -fno-fast-math)
endif()
if(APPLE)
	set(OUT_NAME "battle_core.macos")
elseif(WIN32)
	set(OUT_NAME "battle_core.windows.x86_64")
else()
	set(OUT_NAME "battle_core.linux.x86_64")
endif()
set_target_properties(battle_core PROPERTIES OUTPUT_NAME ${OUT_NAME} PREFIX "lib"
	LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../bin"
	RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../bin"
	LIBRARY_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/../bin"
	RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/../bin")
