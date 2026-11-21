/**************************************************************************/
/* streaming_safety_margin_policy.h                                       */
/* Unreal-inspired bounded GPU streaming memory safety pool.              */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include <cstdint>

namespace TextureStreamingSafetyMarginPolicy {

// Reserve at most a quarter of the configured mip pool for transient,
/// non-streaming VRAM fluctuations. The default 0 preserves old behavior.
constexpr uint8_t bounded_percent(int p_percent) {
	return p_percent <= 0 ? uint8_t(0) :
			p_percent >= 25 ? uint8_t(25) : uint8_t(p_percent);
}

// Divide BEFORE multiplying to avoid overflow even for UINT64_MAX pools.
// 0 configured budget means disabled fitting, not "0 bytes available".
constexpr uint64_t reserve_bytes(uint64_t p_configured_budget_bytes, int p_percent) {
	const uint64_t percent = bounded_percent(p_percent);
	return (p_configured_budget_bytes / 100ull) * percent +
			((p_configured_budget_bytes % 100ull) * percent) / 100ull;
}

constexpr uint64_t usable_budget_bytes(uint64_t p_configured_budget_bytes, int p_percent) {
	return p_configured_budget_bytes - reserve_bytes(p_configured_budget_bytes, p_percent);
}

} // namespace TextureStreamingSafetyMarginPolicy
