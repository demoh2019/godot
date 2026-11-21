// SPDX-License-Identifier: MIT
#include "register_types.h"

#include "decal_visibility_admission_3d.h"
#include "core/object/class_db.h"

#ifdef TESTS_ENABLED
#include "tests/test_decal_visibility_admission_3d.h"
#endif

void initialize_decal_visibility_budget_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(DecalVisibilityAdmission3D);
}

void uninitialize_decal_visibility_budget_module(ModuleInitializationLevel p_level) {
}
