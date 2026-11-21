// SPDX-License-Identifier: MIT
#include "register_types.h"

#include "snapshot_rotation_smoothing_3d.h"
#include "core/object/class_db.h"

#ifdef TESTS_ENABLED
#include "tests/test_snapshot_rotation_smoothing_3d.h"
#endif

void initialize_snapshot_rotation_smoothing_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(SnapshotRotationSmoothing3D);
}

void uninitialize_snapshot_rotation_smoothing_module(ModuleInitializationLevel p_level) {
}
