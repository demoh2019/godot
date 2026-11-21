// SPDX-License-Identifier: MIT
#pragma once

#include "core/object/ref_counted.h"

// Pure Chaos-style cosmetic rigid-body LOD: simulation near the viewer,
// frozen visual representation farther away, and eventual pool retirement.
// No Node, PhysicsServer, game-authority, state or allocations.
class DebrisSimulationLOD3D : public RefCounted {
	GDCLASS(DebrisSimulationLOD3D, RefCounted);

protected:
	static void _bind_methods();

public:
	enum Tier {
		TIER_INVALID = -1,
		TIER_SIMULATE = 0,
		TIER_FREEZE = 1,
		TIER_RETIRE = 2,
	};

	int classify(double p_distance_m, bool p_in_water, int p_previous_tier,
			double p_simulate_radius_m = 24.0, double p_retire_radius_m = 56.0,
			double p_hysteresis_m = 2.0) const;
};
