// SPDX-License-Identifier: MIT
#include "decal_visibility_admission_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void DecalVisibilityAdmission3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("should_spawn", "camera_position", "decal_position",
					"diameter_m", "max_distance_m", "viewport_height_px",
					"vertical_fov_deg", "min_diameter_px"),
			&DecalVisibilityAdmission3D::should_spawn, DEFVAL(3.0));
}

bool DecalVisibilityAdmission3D::should_spawn(const Vector3 &p_camera_position,
		const Vector3 &p_decal_position, double p_diameter_m,
		double p_max_distance_m, double p_viewport_height_px,
		double p_vertical_fov_deg, double p_min_diameter_px) const {
	// Fail closed on NaN/Inf and out-of-range values. The client only calls
	// this when a valid perspective Camera3D exists; missing cameras should
	// bypass admission in the game rather than silently discard decals.
	if (!p_camera_position.is_finite() || !p_decal_position.is_finite() ||
			!Math::is_finite(p_diameter_m) || !Math::is_finite(p_max_distance_m) ||
			!Math::is_finite(p_viewport_height_px) || !Math::is_finite(p_vertical_fov_deg) ||
			!Math::is_finite(p_min_diameter_px) ||
			p_diameter_m < 0.01 || p_diameter_m > 128.0 ||
			p_max_distance_m < 0.5 || p_max_distance_m > 10000.0 ||
			p_viewport_height_px < 32.0 || p_viewport_height_px > 16384.0 ||
			p_vertical_fov_deg < 5.0 || p_vertical_fov_deg > 170.0 ||
			p_min_diameter_px < 0.0 || p_min_diameter_px > 128.0 ||
			Math::abs(double(p_camera_position.x)) > 10000000.0 ||
			Math::abs(double(p_camera_position.y)) > 10000000.0 ||
			Math::abs(double(p_camera_position.z)) > 10000000.0 ||
			Math::abs(double(p_decal_position.x)) > 10000000.0 ||
			Math::abs(double(p_decal_position.y)) > 10000000.0 ||
			Math::abs(double(p_decal_position.z)) > 10000000.0) {
		return false;
	}
	const double distance = double(p_camera_position.distance_to(p_decal_position));
	// Use the decal sphere radius in the distance rejection. This retains
	// partially visible large scorch volumes near the native fade boundary.
	if (distance > p_max_distance_m + p_diameter_m * 0.5) {
		return false;
	}
	// Perspective projection, conservative: don't reject by camera forward
	// vector because a near camera turn should not erase recent footprints.
	const double focal = p_viewport_height_px /
			(2.0 * Math::tan(Math::deg_to_rad(p_vertical_fov_deg * 0.5)));
	const double projected_diameter_px =
			p_diameter_m * focal / MAX(distance, 0.1);
	return projected_diameter_px >= p_min_diameter_px;
}
