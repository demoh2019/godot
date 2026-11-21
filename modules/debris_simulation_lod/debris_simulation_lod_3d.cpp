// SPDX-License-Identifier: MIT
#include "debris_simulation_lod_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void DebrisSimulationLOD3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("classify", "distance_m", "in_water", "previous_tier",
					"simulate_radius_m", "retire_radius_m", "hysteresis_m"),
			&DebrisSimulationLOD3D::classify, DEFVAL(24.0), DEFVAL(56.0), DEFVAL(2.0));
}

int DebrisSimulationLOD3D::classify(double p_distance_m, bool p_in_water,
		int p_previous_tier, double p_simulate_radius_m,
		double p_retire_radius_m, double p_hysteresis_m) const {
	// Numeric input is untrusted even if it comes from a cosmetic GDScript
	// node. Never freeze or release physics nodes based on invalid ranges.
	if (!Math::is_finite(p_distance_m) ||
			!Math::is_finite(p_simulate_radius_m) ||
			!Math::is_finite(p_retire_radius_m) ||
			!Math::is_finite(p_hysteresis_m) ||
			p_distance_m < 0.0 || p_distance_m > 10000000.0 ||
			p_simulate_radius_m < 1.0 || p_simulate_radius_m > 10000.0 ||
			p_retire_radius_m > 20000.0 ||
			p_hysteresis_m < 0.0 || p_hysteresis_m > 10.0 ||
			p_hysteresis_m >= p_simulate_radius_m ||
			p_simulate_radius_m + p_hysteresis_m >= p_retire_radius_m ||
			(p_previous_tier != TIER_SIMULATE && p_previous_tier != TIER_FREEZE)) {
		return TIER_INVALID;
	}
	if (p_distance_m >= p_retire_radius_m) {
		return TIER_RETIRE;
	}
	// Moving floating wood/sinking casings must not get stuck frozen while
	// within visual relevance. Water only exempts the medium freeze tier.
	if (p_in_water) {
		return TIER_SIMULATE;
	}
	if (p_previous_tier == TIER_FREEZE) {
		return p_distance_m <= p_simulate_radius_m - p_hysteresis_m ?
				TIER_SIMULATE : TIER_FREEZE;
	}
	return p_distance_m >= p_simulate_radius_m + p_hysteresis_m ?
			TIER_FREEZE : TIER_SIMULATE;
}
