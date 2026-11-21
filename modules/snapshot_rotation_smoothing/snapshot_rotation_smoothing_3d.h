// SPDX-License-Identifier: MIT
#pragma once

#include "core/object/ref_counted.h"

// Pure simulated-proxy yaw smoothing, independent of networking/scene state.
// Endpoints follow the shortest angular arc; Hermite derivatives are bounded
// against overshoot and large turns preserve old linear interpolation.
class SnapshotRotationSmoothing3D : public RefCounted {
	GDCLASS(SnapshotRotationSmoothing3D, RefCounted);

protected:
	static void _bind_methods();

public:
	double interpolate_yaw(double p_from_yaw, double p_to_yaw,
			double p_from_angular_velocity, double p_to_angular_velocity,
			double p_snapshot_span, double p_fraction) const;
};
