// SPDX-License-Identifier: MIT
#include "register_types.h"

#include "debris_simulation_lod_3d.h"
#include "core/object/class_db.h"

#ifdef TESTS_ENABLED
#include "tests/test_debris_simulation_lod_3d.h"
#endif

void initialize_debris_simulation_lod_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(DebrisSimulationLOD3D);
}

void uninitialize_debris_simulation_lod_module(ModuleInitializationLevel p_level) {
}
