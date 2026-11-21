extends RefCounted
## Portable Chaos-style cosmetic rigid-body LOD, matching native
## DebrisSimulationLOD3D; pure state transition with a hysteresis band.

const TIER_INVALID := -1
const TIER_SIMULATE := 0
const TIER_FREEZE := 1
const TIER_RETIRE := 2


static func classify(distance_m: float, in_water: bool, previous_tier: int,
		simulate_radius_m: float = 24.0, retire_radius_m: float = 56.0,
		hysteresis_m: float = 2.0) -> int:
	if not is_finite(distance_m) or not is_finite(simulate_radius_m) \
			or not is_finite(retire_radius_m) or not is_finite(hysteresis_m) \
			or distance_m < 0.0 or distance_m > 10000000.0 \
			or simulate_radius_m < 1.0 or simulate_radius_m > 10000.0 \
			or retire_radius_m > 20000.0 \
			or hysteresis_m < 0.0 or hysteresis_m > 10.0 \
			or hysteresis_m >= simulate_radius_m \
			or simulate_radius_m + hysteresis_m >= retire_radius_m \
			or (previous_tier != TIER_SIMULATE and previous_tier != TIER_FREEZE):
		return TIER_INVALID
	if distance_m >= retire_radius_m:
		return TIER_RETIRE
	# Floaters and sinking casings still need full buoyancy within range.
	if in_water:
		return TIER_SIMULATE
	if previous_tier == TIER_FREEZE:
		return TIER_SIMULATE if distance_m <= simulate_radius_m - hysteresis_m else TIER_FREEZE
	return TIER_FREEZE if distance_m >= simulate_radius_m + hysteresis_m else TIER_SIMULATE
