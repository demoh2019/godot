/**************************************************************************/
/* test_streaming_safety_margin_policy.h                                  */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "../streaming_safety_margin_policy.h"
#include "tests/test_macros.h"
#include <initializer_list>

namespace TestStreamingSafetyMarginPolicy {

using TextureStreamingSafetyMarginPolicy::bounded_percent;
using TextureStreamingSafetyMarginPolicy::reserve_bytes;
using TextureStreamingSafetyMarginPolicy::usable_budget_bytes;

TEST_CASE("[TextureStreaming] Unreal MemoryMargin-style safety pool math") {
	constexpr uint64_t MB = 1024ull * 1024ull;
	CHECK(bounded_percent(-50) == 0);
	CHECK(bounded_percent(0) == 0);
	CHECK(bounded_percent(8) == 8);
	CHECK(bounded_percent(25) == 25);
	CHECK(bounded_percent(1000) == 25);
	CHECK(reserve_bytes(512 * MB, 0) == 0);
	CHECK(usable_budget_bytes(512 * MB, 0) == 512 * MB);
	CHECK(reserve_bytes(100 * MB, 8) == 8 * MB);
	CHECK(usable_budget_bytes(100 * MB, 8) == 92 * MB);
	CHECK(reserve_bytes(100 * MB, 40) == 25 * MB);
	CHECK(usable_budget_bytes(100 * MB, -10) == 100 * MB);
	CHECK(reserve_bytes(0, 25) == 0);
	CHECK(usable_budget_bytes(0, 25) == 0);
}

TEST_CASE("[TextureStreaming] reserve calculations never overflow or overreserve") {
	constexpr uint64_t HUGE = UINT64_MAX;
	for (int pct = -10; pct <= 110; ++pct) {
		for (uint64_t total : { uint64_t(0), uint64_t(1), uint64_t(19),
				uint64_t(99), uint64_t(100), uint64_t(101),
				uint64_t(1024ull * 1024ull), uint64_t(65535ull * 1024ull * 1024ull),
				HUGE - 1, HUGE }) {
			const uint64_t reserved = reserve_bytes(total, pct);
			const uint64_t usable = usable_budget_bytes(total, pct);
			CHECK(reserved <= total);
			CHECK(usable <= total);
			CHECK(reserved + usable == total);
			CHECK(reserved <= total / 4);
		}
	}
}

} // namespace TestStreamingSafetyMarginPolicy
