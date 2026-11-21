"""Cgame native texture safety pool source contracts (not a native test)."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "modules/texture_streaming"
GAME = ROOT / "game/scripts/client"


class TextureStreamingSafetyPoolContract(unittest.TestCase):
    def test_fitter_reserves_before_prefetch_and_quality_reduction(self):
        cpp = (MOD / "texture_streaming.cpp").read_text()
        h = (MOD / "texture_streaming.h").read_text()
        policy = (MOD / "streaming_safety_margin_policy.h").read_text()
        reg = (MOD / "register_types.cpp").read_text()
        markers = [
            "const uint64_t configured_budget_bytes",
            "const uint64_t reserve_bytes = ",
            "const uint64_t budget_bytes = configured_budget_bytes - reserve_bytes",
            "TextureStreamingFeedbackPolicy::adaptive_prefetch_mips(",
            "const uint64_t budget_high = ",
            "while (assigned_bytes > budget_low",
        ]
        offsets = [cpp.index(s) for s in markers]
        self.assertEqual(offsets, sorted(offsets))
        self.assertIn("streaming_configured_budget_bytes.store(configured_budget_bytes", cpp)
        self.assertIn("streaming_safety_reserve_bytes.store(reserve_bytes", cpp)
        self.assertIn("streaming_budget_bytes.store(budget_bytes", cpp)
        self.assertIn("streaming_safety_reserve_bytes.store(0", cpp)
        self.assertIn("std::atomic<uint8_t> safety_margin_percent{ 0 }", h)
        self.assertIn("get_streaming_safety_reserve_bytes", h)
        self.assertIn("p_configured_budget_bytes / 100ull", policy)
        self.assertIn("bounded_percent(p_percent)", policy)
        self.assertIn("tests/test_streaming_safety_margin_policy.h", reg)

    def test_real_preset_and_godot_profiler_integration(self):
        game = (GAME / "graphics_texture_streaming.gd").read_text()
        quality = (GAME / "graphics_quality.gd").read_text()
        online = (GAME / "online_main.gd").read_text()
        tests = (ROOT / "game/tests/test_graphics_texture_streaming.gd").read_text()
        self.assertIn("SAFETY_MARGIN_PERCENT := [0, 4, 6, 8]", game)
        self.assertIn("method != \"forward_plus\"", game)
        self.assertIn('server.call("set_safety_margin_percent", safety_margin_percent(level, method))', game)
        self.assertIn("Albion/TextureStreamingConfiguredBudgetBytes", game)
        self.assertIn("Albion/TextureStreamingSafetyReserveBytes", game)
        self.assertIn("GraphicsTextureStreaming.apply(_level", quality)
        self.assertIn("GraphicsTextureStreaming.register_profiler_monitors()", online)
        self.assertIn("get_safety_margin_percent", tests)
        self.assertIn("get_streaming_safety_reserve_bytes", tests)


if __name__ == "__main__":
    unittest.main()
