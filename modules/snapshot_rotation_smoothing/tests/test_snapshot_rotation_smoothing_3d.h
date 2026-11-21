// SPDX-License-Identifier: MIT
#pragma once

#include "../snapshot_rotation_smoothing_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestSnapshotRotationSmoothing3D {

TEST_CASE("[SnapshotRotationSmoothing3D] linear with equal tangents and exact endpoints") {
	Ref<SnapshotRotationSmoothing3D> p;
	p.instantiate();
	for (int i = 0; i <= 100; ++i) {
		const double t = double(i) / 100.0;
		const double yaw = p->interpolate_yaw(0.2, 0.9, 7.0, 7.0, 0.1, t);
		CHECK(Math::abs(yaw - (0.2 + 0.7 * t)) < 0.000001);
	}
	CHECK(p->interpolate_yaw(0.2, 0.9, 7.0, 7.0, 0.1, -5.0) == 0.2);
	CHECK(Math::abs(p->interpolate_yaw(0.2, 0.9, 7.0, 7.0, 0.1, 5.0) - 0.9) < 0.000001);
	CHECK(p->interpolate_yaw(0.2, 0.9, 7.0, 7.0, 0.1, Math::NaN) == 0.2);
}

TEST_CASE("[SnapshotRotationSmoothing3D] wrap-around, no overshoot and abrupt turns") {
	Ref<SnapshotRotationSmoothing3D> p;
	p.instantiate();
	const double from = Math::deg_to_rad(179.0);
	const double to = Math::deg_to_rad(-179.0);
	double last = from;
	for (int i = 0; i <= 100; ++i) {
		const double t = double(i) / 100.0;
		const double yaw = p->interpolate_yaw(from, to, 20.0, -30.0, 0.1, t);
		if (i < 100) {
			CHECK(yaw >= from - 0.000001);
			CHECK(yaw <= from + Math::deg_to_rad(2.0) + 0.000001);
			CHECK(yaw >= last - 0.000001);
		}
		last = yaw;
	}
	CHECK(Math::abs(p->interpolate_yaw(from, to, 0.0, 0.0, 0.1, 0.5) - Math_PI) < 0.00001);
	const double linear = p->interpolate_yaw(0.0, 3.0, 100.0, -100.0, 0.1, 0.5);
	CHECK(Math::abs(linear - 1.5) < 0.000001); // Large turns preserve linear smoothing.
	CHECK(Math::abs(p->interpolate_yaw(0.0, 1.0, 5.0, 0.0, 1.0, 0.5) - 0.5) < 0.000001);
}

TEST_CASE("[SnapshotRotationSmoothing3D] monotone bounded extreme tangents") {
	Ref<SnapshotRotationSmoothing3D> p;
	p.instantiate();
	for (int turn_pct = -200; turn_pct <= 200; turn_pct += 20) {
		if (turn_pct == 0) {
			continue;
		}
		const double turn = turn_pct / 100.0;
		for (int a = -20; a <= 20; a += 5) {
			for (int b = -20; b <= 20; b += 5) {
				for (int i = 1; i < 100; ++i) {
					const double t = double(i) / 100.0;
					const double yaw = p->interpolate_yaw(0.0, turn, a, b, 0.1, t);
					CHECK(Math::is_finite(yaw));
					CHECK(yaw >= MIN(0.0, turn) - 0.000001);
					CHECK(yaw <= MAX(0.0, turn) + 0.000001);
				}
			}
		}
	}
	// Invalid network samples fail without leaking NaN into a render transform.
	CHECK(p->interpolate_yaw(Math::NaN, 0.7, 1.0, 1.0, 0.1, 0.5) == 0.7);
	CHECK(p->interpolate_yaw(0.7, Math::INF, 1.0, 1.0, 0.1, 0.5) == 0.7);
	CHECK(p->interpolate_yaw(Math::INF, Math::NaN, 1.0, 1.0, 0.1, 0.5) == 0.0);
}

} // namespace TestSnapshotRotationSmoothing3D
