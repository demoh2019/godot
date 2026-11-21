// SPDX-License-Identifier: MIT
#pragma once

#include "core/math/vector3.h"
#include "core/object/ref_counted.h"

// Pure Unreal-style spatial retrigger gate before any 3D audio allocation.
class SpatialSoundEventPolicy : public RefCounted {
	GDCLASS(SpatialSoundEventPolicy, RefCounted);

protected:
	static void _bind_methods();

public:
	bool should_emit(const Vector3 &p_listener, const Vector3 &p_source,
			const Vector3 &p_previous_source, double p_now_seconds,
			double p_last_seconds, double p_retrigger_seconds,
			double p_merge_radius, double p_max_distance,
			bool p_listener_ready = true) const;
};
