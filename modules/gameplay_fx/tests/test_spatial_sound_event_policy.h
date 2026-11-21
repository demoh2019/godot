// SPDX-License-Identifier: MIT
#pragma once
#include "../spatial_sound_event_policy.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestSpatialSoundEventPolicy {
TEST_CASE("[SpatialSoundEventPolicy] repeated same-location foley is coalesced") {
	Ref<SpatialSoundEventPolicy> policy;
	policy.instantiate();
	const Vector3 listener(0, 0, 0);
	const Vector3 source(8, 0, 0);
	CHECK(policy->should_emit(listener, source, Vector3(), 100.0, -1.0, .075, 3.5, 90.0));
	CHECK_FALSE(policy->should_emit(listener, source, source, 100.04, 100.0, .075, 3.5, 90.0));
	CHECK(policy->should_emit(listener, source, source, 100.075, 100.0, .075, 3.5, 90.0));
	CHECK(policy->should_emit(listener, source + Vector3(4, 0, 0), source, 100.01, 100.0, .075, 3.5, 90.0));
	CHECK(policy->should_emit(listener, source, source, 100.01, 100.0, 0.0, 3.5, 90.0));
	CHECK(policy->should_emit(listener, source, source, 99.0, 100.0, .075, 3.5, 90.0));
}

TEST_CASE("[SpatialSoundEventPolicy] far-only cull, invalid input, and no listener") {
	Ref<SpatialSoundEventPolicy> policy;
	policy.instantiate();
	const Vector3 listener;
	CHECK(policy->should_emit(listener, Vector3(92, 0, 0), Vector3(), 5, -1, 0, 3.5, 90));
	CHECK_FALSE(policy->should_emit(listener, Vector3(92.1, 0, 0), Vector3(), 5, -1, 0, 3.5, 90));
	CHECK(policy->should_emit(listener, Vector3(120, 0, 0), Vector3(), 5, -1, 0, 3.5, 90, false));
	CHECK(policy->should_emit(Vector3(Math::INF, 0, 0), Vector3(120, 0, 0),
			Vector3(), 5, -1, 0, 3.5, 90));
	CHECK_FALSE(policy->should_emit(listener, Vector3(Math::INF, 0, 0),
			Vector3(), 5, -1, 0, 3.5, 90));
	CHECK(policy->should_emit(listener, Vector3(8, 0, 0), Vector3(8, 0, 0),
			5, 4.99, Math::NaN, 3.5, 90));
	CHECK(policy->should_emit(listener, Vector3(8, 0, 0), Vector3(8, 0, 0),
			5, 4.99, .075, -1.0, 90));
}
} // namespace TestSpatialSoundEventPolicy
