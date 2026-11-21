// SPDX-License-Identifier: MIT
#pragma once

#include "core/math/vector3.h"
#include "core/object/ref_counted.h"

// Pure, camera-aware admission for expensive ephemeral 3D decals.
// Inspired by Unreal's decal screen-size fade and distance bounds.
// This does not modify nodes, query physics, or alter gameplay authority.
class DecalVisibilityAdmission3D : public RefCounted {
	GDCLASS(DecalVisibilityAdmission3D, RefCounted);

protected:
	static void _bind_methods();

public:
	// Conservative projected diameter in screen pixels. Invalid input and
	// negligible projected size are rejected without modifying decal pools.
	bool should_spawn(const Vector3 &p_camera_position, const Vector3 &p_decal_position,
			double p_diameter_m, double p_max_distance_m,
			double p_viewport_height_px, double p_vertical_fov_deg,
			double p_min_diameter_px = 3.0) const;
};
