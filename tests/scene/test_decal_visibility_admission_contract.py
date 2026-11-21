"""Static Cgame decal admission source contracts; native tests are separate."""
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "modules/decal_visibility_budget"
GAME = ROOT / "game/scripts/client"
TESTS = ROOT / "game/tests"


class DecalVisibilityAdmissionContract(unittest.TestCase):
    def test_registration_and_pure_engine_method(self):
        header = (MOD / "decal_visibility_admission_3d.h").read_text()
        cpp = (MOD / "decal_visibility_admission_3d.cpp").read_text()
        reg = (MOD / "register_types.cpp").read_text()
        self.assertIn("GDREGISTER_CLASS(DecalVisibilityAdmission3D);", reg)
        self.assertIn("bool should_spawn(", header)
        self.assertIn("p_max_distance_m + p_diameter_m * 0.5", cpp)
        self.assertIn("p_diameter_m * focal / MAX(distance, 0.1)", cpp)
        self.assertIn("p_min_diameter_px", cpp)
        self.assertNotIn("RenderingServer", cpp)
        self.assertNotIn("SceneTree", cpp)
        self.assertNotIn("intersect_ray", cpp)
        self.assertNotIn("memnew(", cpp)
        methods = ET.parse(MOD / "doc_classes/DecalVisibilityAdmission3D.xml").findall(
            "./methods/method")
        self.assertEqual([m.get("name") for m in methods], ["should_spawn"])

    def test_real_game_checks_before_gpu_pool_mutation(self):
        impact = (GAME / "impact_decals.gd").read_text()
        blood = (GAME / "blood_decals.gd").read_text()
        script = (GAME / "decal_visibility_policy.gd").read_text()
        game_test = (TESTS / "test_decal_visibility_admission.gd").read_text()
        runner = (TESTS / "run_decal_visibility_admission.gd").read_text()
        all_tests = (TESTS / "run_all.gd").read_text()
        self.assertIn('EngineFeatures.make("DecalVisibilityAdmission3D")', impact)
        self.assertIn('EngineFeatures.make("DecalVisibilityAdmission3D")', blood)
        self.assertIn('native_policy.call("should_spawn"', script)
        self.assertIn("Camera3D.KEEP_WIDTH", script)
        self.assertIn("static func should_spawn(", script)
        self.assertIn("static func can_project(", script)
        self.assertIn("viewport.get_camera_3d()", script)
        self.assertIn("draw_distance(current_quality) + 12.0", impact)
        self.assertLess(impact.find("if not DecalVisibility.can_project("),
                        impact.find("var key := randi() % 4"))
        self.assertEqual(blood.count("if not DecalVisibility.can_project("), 2)
        self.assertLess(blood.find("if not DecalVisibility.can_project("),
                        blood.find("var d := _pool[_next]"))
        self.assertIn("native/portable projection parity", game_test)
        self.assertIn("test_decal_visibility_admission.gd", runner)
        self.assertIn("test_decal_visibility_admission.gd", all_tests)


if __name__ == "__main__":
    unittest.main()
