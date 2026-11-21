// SPDX-License-Identifier: MIT
#include "spatial_sound_event_policy.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void SpatialSoundEventPolicy::_bind_methods() {
	ClassDB::bind_method(D_METHOD("should_emit", "listener", "source",
					"previous_source", "now_seconds", "last_seconds",
					"retrigger_seconds", "merge_radius", "max_distance",
					"listener_ready"),
			&SpatialSoundEventPolicy::should_emit, DEFVAL(true));
}

bool SpatialSoundEventPolicy::should_emit(const Vector3 &p_listener,
		const Vector3 &p_source, const Vector3 &p_previous_source,
		double p_now_seconds, double p_last_seconds, double p_retrigger_seconds,
		double p_merge_radius, double p_max_distance,
		bool p_listener_ready) const {
	if (!p_source.is_finite()) {
		return false; // Never write invalid data into a 3D transform.
	}
	if (!p_listener_ready || !p_listener.is_finite()) {
		return true; // Missing listener keeps the legacy audio behavior.
	}
	// Fail open on malformed optional timing and limits.
	if (!Math::is_finite(p_now_seconds) || !Math::is_finite(p_last_seconds) ||
			!Math::is_finite(p_retrigger_seconds) ||
			!Math::is_finite(p_merge_radius) || !Math::is_finite(p_max_distance) ||
			p_now_seconds < 0.0 || p_now_seconds > 1.0e10 ||
			p_retrigger_seconds < 0.0 || p_retrigger_seconds > 2.0 ||
			p_merge_radius < 0.0 || p_merge_radius > 100.0 ||
			p_max_distance < 1.0 || p_max_distance > 10000.0) {
		return true;
	}
	const double cutoff = p_max_distance + 2.0; // Safe border around 90 m sound fade.
	if (p_listener.distance_squared_to(p_source) > cutoff * cutoff) {
		return false;
	}
	if (p_retrigger_seconds == 0.0 || p_last_seconds < 0.0 ||
			p_last_seconds > p_now_seconds || !p_previous_source.is_finite()) {
		return true;
	}
	return !(p_now_seconds - p_last_seconds < p_retrigger_seconds &&
			p_previous_source.distance_squared_to(p_source) <=
					p_merge_radius * p_merge_radius);
}
