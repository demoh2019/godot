"""Native yaw smoothing + real Albion simulated-proxy source contracts."""
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "modules/snapshot_rotation_smoothing"
GAME = ROOT / "game/scripts/client"
TEST = ROOT / "game/tests"


class SnapshotRotationSmoothingContract(unittest.TestCase):
    def test_native_pure_guarded_shortest_arc_math(self):
        h = (MOD / "snapshot_rotation_smoothing_3d.h").read_text()
        cpp = (MOD / "snapshot_rotation_smoothing_3d.cpp").read_text()
        reg = (MOD / "register_types.cpp").read_text()
        methods = ET.parse(MOD / "doc_classes/SnapshotRotationSmoothing3D.xml")
        self.assertIn("GDREGISTER_CLASS(SnapshotRotationSmoothing3D);", reg)
        self.assertIn("double interpolate_yaw(", h)
        self.assertIn("Math::fposmod(p_b - p_a + Math_PI, Math_TAU)", cpp)
        self.assertIn("MAX_SMOOTH_TURN_RADIANS = 2.4", cpp)
        self.assertIn("p_from_yaw + CLAMP(offset", cpp)
        self.assertIn("return p_from_yaw + delta;", cpp)
        self.assertIn("Math::is_finite(p_from_angular_velocity)", cpp)
        self.assertNotIn("Node3D", cpp)
        self.assertNotIn("PhysicsServer", cpp)
        self.assertNotIn("SceneTree", cpp)
        self.assertNotIn("RenderingServer", cpp)
        self.assertEqual([m.get("name") for m in methods.findall("./methods/method")],
                         ["interpolate_yaw"])

    def test_remote_players_zombies_use_actual_histories_and_stock_fallback(self):
        smooth = (GAME / "network_snapshot_smoothing.gd").read_text()
        entity = (GAME / "entity_view.gd").read_text()
        game_test = (TEST / "test_snapshot_rotation_smoothing.gd").read_text()
        runner = (TEST / "run_snapshot_rotation_smoothing.gd").read_text()
        all_tests = (TEST / "run_all.gd").read_text()
        self.assertIn('EngineFeatures.make("SnapshotRotationSmoothing3D")', entity)
        self.assertIn("SnapshotSmoothing.sample_yaw(", entity)
        self.assertIn("SnapshotSmoothing.sample_position(", entity)
        self.assertIn("if GraphicsQuality.level() == 0:", entity)
        self.assertIn("lerp_angle(float(older[2]), float(newer[2]), k)", entity)
        self.assertIn("history.clear() # A teleport", entity)
        self.assertIn("NetworkJitterBuffer.advance_clock(", entity)
        self.assertIn("func _sample(key: String)", entity)
        self.assertIn("static func interpolate_yaw(", smooth)
        self.assertIn("static func sample_yaw(", smooth)
        self.assertIn('native_policy.call("interpolate_yaw"', smooth)
        self.assertIn("return from_yaw + turn", smooth)
        self.assertIn("if not have_neighbor:", smooth)
        self.assertIn("native/script yaw smoothing parity", game_test)
        self.assertIn("test_snapshot_rotation_smoothing.gd", runner)
        self.assertIn("test_snapshot_rotation_smoothing.gd", all_tests)


if __name__ == "__main__":
    unittest.main()
