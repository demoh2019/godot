// SPDX-License-Identifier: MIT
#pragma once

#include "../debris_simulation_lod_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestDebrisSimulationLOD3D {

TEST_CASE("[DebrisSimulationLOD3D] active, frozen, retired and water rules") {
	Ref<DebrisSimulationLOD3D> lod;
	lod.instantiate();
	CHECK(lod->classify(0.0, false, 0) == 0);
	CHECK(lod->classify(24.0, false, 0) == 0);
	CHECK(lod->classify(25.99, false, 0) == 0);
	CHECK(lod->classify(26.0, false, 0) == 1);
	CHECK(lod->classify(40.0, false, 0) == 1);
	CHECK(lod->classify(56.0, false, 0) == 2);
	CHECK(lod->classify(100.0, false, 1) == 2);
	CHECK(lod->classify(24.0, false, 1) == 1);
	CHECK(lod->classify(22.01, false, 1) == 1);
	CHECK(lod->classify(22.0, false, 1) == 0);
	CHECK(lod->classify(30.0, true, 0) == 0);
	CHECK(lod->classify(30.0, true, 1) == 0);
	CHECK(lod->classify(70.0, true, 1) == 2);
}

TEST_CASE("[DebrisSimulationLOD3D] finite input and safe radius constraints") {
	Ref<DebrisSimulationLOD3D> lod;
	lod.instantiate();
	CHECK(lod->classify(Math::NaN, false, 0) == -1);
	CHECK(lod->classify(Math::INF, false, 0) == -1);
	CHECK(lod->classify(-1.0, false, 0) == -1);
	CHECK(lod->classify(10000001.0, false, 0) == -1);
	CHECK(lod->classify(2.0, false, 2) == -1);
	CHECK(lod->classify(2.0, false, -1) == -1);
	CHECK(lod->classify(2.0, false, 0, 0.0, 56.0, 2.0) == -1);
	CHECK(lod->classify(2.0, false, 0, 24.0, 24.0, 0.0) == -1);
	CHECK(lod->classify(2.0, false, 0, 24.0, 56.0, 11.0) == -1);
	CHECK(lod->classify(2.0, false, 0, 24.0, 26.0, 2.0) == -1);
	CHECK(lod->classify(2.0, false, 0, Math::NaN, 56.0, 2.0) == -1);
	CHECK(lod->classify(2.0, false, 0, 24.0, Math::NaN, 2.0) == -1);
	CHECK(lod->classify(2.0, false, 0, 24.0, 56.0, Math::NaN) == -1);
}

TEST_CASE("[DebrisSimulationLOD3D] hysteresis avoids oscillation and recovers when approaching") {
	Ref<DebrisSimulationLOD3D> lod;
	lod.instantiate();
	int tier = 0;
	for (int frame = 0; frame < 300; ++frame) {
		const double distance = frame % 2 == 0 ? 25.0 : 25.8;
		tier = lod->classify(distance, false, tier);
		CHECK(tier == 0); // Never crosses 26 m freeze threshold.
	}
	tier = lod->classify(26.1, false, tier);
	CHECK(tier == 1);
	for (int frame = 0; frame < 300; ++frame) {
		const double distance = frame % 2 == 0 ? 23.0 : 25.8;
		tier = lod->classify(distance, false, tier);
		CHECK(tier == 1); // Frozen until within 22 m.
	}
	CHECK(lod->classify(21.0, false, tier) == 0);
	CHECK(lod->classify(29.0, true, tier) == 0);
}

} // namespace TestDebrisSimulationLOD3D
