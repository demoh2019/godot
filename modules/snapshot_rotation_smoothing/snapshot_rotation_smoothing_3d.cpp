// SPDX-License-Identifier: MIT
#include "snapshot_rotation_smoothing_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

namespace {
constexpr double MAX_SAMPLE_SECONDS = 0.5;
constexpr double MAX_SMOOTH_TURN_RADIANS = 2.4;
constexpr double MAX_YAW_ABS = 10000.0;
constexpr double MAX_ANGULAR_SPEED = 1000.0;

double shortest_yaw(double p_a, double p_b) {
	return Math::fposmod(p_b - p_a + Math_PI, Math_TAU) - Math_PI;
}
} // namespace

void SnapshotRotationSmoothing3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("interpolate_yaw", "from_yaw", "to_yaw",
					"from_angular_velocity", "to_angular_velocity",
					"snapshot_span", "fraction"),
			&SnapshotRotationSmoothing3D::interpolate_yaw);
}

double SnapshotRotationSmoothing3D::interpolate_yaw(double p_from_yaw,
		double p_to_yaw, double p_from_angular_velocity,
		double p_to_angular_velocity, double p_snapshot_span,
		double p_fraction) const {
	// Broken snapshots must not poison visual transforms. For a missing
	// target use the last valid authoritative angle, otherwise zero.
	if (!Math::is_finite(p_from_yaw) || Math::abs(p_from_yaw) > MAX_YAW_ABS) {
		return Math::is_finite(p_to_yaw) && Math::abs(p_to_yaw) <= MAX_YAW_ABS ?
				p_to_yaw : 0.0;
	}
	if (!Math::is_finite(p_to_yaw) || Math::abs(p_to_yaw) > MAX_YAW_ABS) {
		return p_from_yaw;
	}
	const double t = Math::is_finite(p_fraction) ? CLAMP(p_fraction, 0.0, 1.0) : 0.0;
	const double delta = shortest_yaw(p_from_yaw, p_to_yaw);
	if (t <= 0.0 || Math::abs(delta) <= 0.00001) {
		return p_from_yaw;
	}
	if (t >= 1.0) {
		// Equivalent to the server yaw modulo 2*pi, but avoid an
		// artificial full revolution on the exact sample boundary.
		return p_from_yaw + delta;
	}
	const double linear = p_from_yaw + delta * t;
	// Do not infer angular momentum from a teleport-like abrupt turn,
	// duplicate timestamp, unavailable tangent, or packet gap.
	if (!Math::is_finite(p_snapshot_span) || p_snapshot_span <= 0.00001 ||
			p_snapshot_span > MAX_SAMPLE_SECONDS ||
			Math::abs(delta) > MAX_SMOOTH_TURN_RADIANS ||
			!Math::is_finite(p_from_angular_velocity) ||
			!Math::is_finite(p_to_angular_velocity) ||
			Math::abs(p_from_angular_velocity) > MAX_ANGULAR_SPEED ||
			Math::abs(p_to_angular_velocity) > MAX_ANGULAR_SPEED) {
		return linear;
	}
	// Direction-clamp Hermite endpoint tangents to the *shortest* angular
	// chord. No winding, overshoot or fake 360-degree turn is possible.
	const double m0 = delta * CLAMP(p_from_angular_velocity * p_snapshot_span / delta, 0.0, 3.0);
	const double m1 = delta * CLAMP(p_to_angular_velocity * p_snapshot_span / delta, 0.0, 3.0);
	const double t2 = t * t;
	const double t3 = t2 * t;
	const double offset = (t3 - 2.0 * t2 + t) * m0 +
			(-2.0 * t3 + 3.0 * t2) * delta +
			(t3 - t2) * m1;
	return p_from_yaw + CLAMP(offset, MIN(0.0, delta), MAX(0.0, delta));
}
