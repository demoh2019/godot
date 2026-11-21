// SPDX-License-Identifier: MIT
#pragma once

#include "../decal_visibility_admission_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestDecalVisibilityAdmission3D {

TEST_CASE("[DecalVisibilityAdmission3D] near impacts persist, distant and subpixel impacts skip") {
	Ref<DecalVisibilityAdmission3D> c;
	c.instantiate();
	const Vector3 camera(0, 2, 0);
	CHECK(c->should_spawn(camera, Vector3(0, 2, 2), 1.0, 60.0, 1080.0, 60.0));
	CHECK(c->should_spawn(camera, Vector3(0, 2, 30), 1.0, 60.0, 1080.0, 60.0));
	CHECK_FALSE(c->should_spawn(camera, Vector3(0, 2, 80), 1.0, 60.0, 1080.0, 60.0));
	CHECK_FALSE(c->should_spawn(camera, Vector3(0, 2, 55), 0.05, 60.0, 720.0, 60.0, 3.0));
	CHECK(c->should_spawn(camera, Vector3(0, 2, 55), 1.4, 60.0, 720.0, 60.0, 3.0));
	// Border includes a decal's half-diameter, not just its center.
	CHECK(c->should_spawn(camera, Vector3(0, 2, 60.4), 1.0, 60.0, 1080.0, 60.0));
	CHECK_FALSE(c->should_spawn(camera, Vector3(0, 2, 60.6), 1.0, 60.0, 1080.0, 60.0));
	CHECK(c->should_spawn(camera, camera, 1.0, 60.0, 1080.0, 60.0));
	CHECK(c->should_spawn(camera, Vector3(0, 2, -3), 1.0, 60.0, 1080.0, 60.0));
}

TEST_CASE("[DecalVisibilityAdmission3D] malformed camera and projection data fail closed") {
	Ref<DecalVisibilityAdmission3D> c;
	c.instantiate();
	const Vector3 camera;
	const Vector3 position(0, 0, 5);
	CHECK_FALSE(c->should_spawn(camera, position, Math::NaN, 60, 1080, 60));
	CHECK_FALSE(c->should_spawn(camera, position, 1, Math::INF, 1080, 60));
	CHECK_FALSE(c->should_spawn(camera, position, 1, 60, 1080, 0));
	CHECK_FALSE(c->should_spawn(camera, position, 1, 60, 1080, 171));
	CHECK_FALSE(c->should_spawn(camera, position, 1, 60, 12, 60));
	CHECK_FALSE(c->should_spawn(camera, position, 1, 60, 1080, 60, -1));
	CHECK_FALSE(c->should_spawn(camera, position, 1, 60, 1080, 60, 129));
	CHECK_FALSE(c->should_spawn(Vector3(Math::INF, 0, 0), position, 1, 60, 1080, 60));
	CHECK_FALSE(c->should_spawn(camera, Vector3(10000001.0, 0, 0), 1, 60, 1080, 60));
	CHECK_FALSE(c->should_spawn(camera, position, 129, 60, 1080, 60));
}

TEST_CASE("[DecalVisibilityAdmission3D] expanding decals cannot become less visible") {
	Ref<DecalVisibilityAdmission3D> c;
	c.instantiate();
	const Vector3 camera;
	for (int distance = 1; distance < 110; ++distance) {
		for (int diameter_pct = 10; diameter_pct <= 120; diameter_pct += 10) {
			const double diameter = double(diameter_pct) / 100.0;
			const bool small = c->should_spawn(camera, Vector3(0, 0, distance), diameter,
					100.0, 720.0, 60.0, 4.0);
			const bool large = c->should_spawn(camera, Vector3(0, 0, distance),
					diameter + 0.1, 100.0, 720.0, 60.0, 4.0);
			CHECK_FALSE(small && !large);
		}
	}
}

} // namespace TestDecalVisibilityAdmission3D
