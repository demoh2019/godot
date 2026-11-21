"""Native/game cosmetic physics LOD wiring; not a native compile substitute."""
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/debris_simulation_lod"
GAME = ROOT / "game/scripts/client"
TESTS = ROOT / "game/tests"


class DebrisSimulationLODContract(unittest.TestCase):
    def test_engine_registration_and_pure_hysteresis(self):
        h = (MODULE / "debris_simulation_lod_3d.h").read_text()
        cpp = (MODULE / "debris_simulation_lod_3d.cpp").read_text()
        reg = (MODULE / "register_types.cpp").read_text()
        doc = ET.parse(MODULE / "doc_classes/DebrisSimulationLOD3D.xml")
        self.assertIn("GDREGISTER_CLASS(DebrisSimulationLOD3D);", reg)
        self.assertIn("int classify(", h)
        self.assertIn("p_distance_m >= p_retire_radius_m", cpp)
        self.assertIn("p_in_water", cpp)
        self.assertIn("p_simulate_radius_m - p_hysteresis_m", cpp)
        self.assertIn("p_simulate_radius_m + p_hysteresis_m", cpp)
        self.assertIn("return TIER_INVALID", cpp)
        self.assertNotIn("PhysicsServer", cpp)
        self.assertNotIn("RenderingServer", cpp)
        self.assertNotIn("SceneTree", cpp)
        self.assertEqual([m.get("name") for m in doc.findall("./methods/method")],
                         ["classify"])

    def test_actual_game_physics_body_and_viewer_integration(self):
        debris = (GAME / "physics_debris.gd").read_text()
        fx = (GAME / "physics_world_fx.gd").read_text()
        online = (GAME / "online_main.gd").read_text()
        fallback = (GAME / "debris_simulation_lod.gd").read_text()
        game_tests = (TESTS / "test_debris_simulation_lod.gd").read_text()
        runner = (TESTS / "run_debris_simulation_lod.gd").read_text()
        full = (TESTS / "run_all.gd").read_text()
        self.assertIn('EngineFeatures.make("DebrisSimulationLOD3D")', debris)
        self.assertIn("DebrisLOD.classify(", debris)
        self.assertIn("func set_viewer_position(at: Vector3)", debris)
        self.assertIn("range(_bodies.size() - 1, -1, -1)", debris)
        self.assertNotIn("for body in _bodies.duplicate():\n\t\tvar kind:", debris)
        self.assertIn("body.freeze = true", debris)
        self.assertIn("body.freeze = false", debris)
        self.assertIn("_retire(body)", debris)
        self.assertIn("BLAST_WAKE_GRACE := 0.40", debris)
        self.assertIn('body.set_meta("blast_wake_until", _clock + BLAST_WAKE_GRACE)', debris)
        self.assertIn('body.set_meta("sim_lod", 0)', debris)
        self.assertIn("not _within_relevance(at)", debris)
        self.assertIn("not _within_relevance(center, radius)", debris)
        self.assertIn('debris.call("set_viewer_position", player)', fx)
        self.assertIn("physics_fx.update(delta, position)", online)
        self.assertIn("static func classify(", fallback)
        self.assertIn("native/script parity across movement", game_tests)
        self.assertIn("test_debris_simulation_lod.gd", runner)
        self.assertIn("test_debris_simulation_lod.gd", full)


if __name__ == "__main__":
    unittest.main()
