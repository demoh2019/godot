"""Native/game Unreal-style spatial sound emission gate source checks."""
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "modules/gameplay_fx"
GAME = ROOT / "game/scripts/client"
TEST = ROOT / "game/tests"

class SpatialSoundEventPolicyContract(unittest.TestCase):
    def test_pure_registered_native_policy_and_docs(self):
        reg = (MOD / "register_types.cpp").read_text()
        config = (MOD / "config.py").read_text()
        h = (MOD / "spatial_sound_event_policy.h").read_text()
        cpp = (MOD / "spatial_sound_event_policy.cpp").read_text()
        xml = ET.parse(MOD / "doc_classes/SpatialSoundEventPolicy.xml")
        self.assertIn("GDREGISTER_CLASS(SpatialSoundEventPolicy);", reg)
        self.assertIn('#include "tests/test_spatial_sound_event_policy.h"', reg)
        self.assertIn('"SpatialSoundEventPolicy",', config)
        self.assertIn("bool should_emit(", h)
        self.assertIn("p_listener.distance_squared_to(p_source)", cpp)
        self.assertIn("p_previous_source.distance_squared_to(p_source)", cpp)
        self.assertIn("p_now_seconds - p_last_seconds < p_retrigger_seconds", cpp)
        self.assertNotIn("AudioServer", cpp)
        self.assertNotIn("PhysicsServer", cpp)
        self.assertNotIn("SceneTree", cpp)
        self.assertNotIn("Time::", cpp)
        self.assertEqual([m.get("name") for m in xml.findall("./methods/method")],
                         ["should_emit"])

    def test_actual_audio_gate_precedes_decoding_allocation_and_raycast(self):
        audio = (GAME / "audio.gd").read_text()
        portable = (GAME / "audio_spatial_emission.gd").read_text()
        online = (GAME / "online_main.gd").read_text()
        focused = (TEST / "test_spatial_sound_event_policy.gd").read_text()
        full = (TEST / "run_all.gd").read_text()
        play = audio.split("func play_at(", 1)[1].split("func _physics_process(", 1)[0]
        self.assertLess(play.index("_should_emit_spatial(sound_name, position, now)"),
                        play.index("Assets.sound(sound_name)"))
        self.assertLess(play.index("Assets.sound(sound_name)"),
                        play.index("AudioStreamPlayer3D.new()"))
        self.assertLess(play.index("AudioStreamPlayer3D.new()"),
                        play.index("player.play()"))
        self.assertLess(play.index("player.play()"),
                        play.index("_record_spatial_emission(sound_name, position, now)"))
        self.assertIn('EngineFeatures.make("SpatialSoundEventPolicy")', audio)
        self.assertIn("SPATIAL_RETRIGGER := ", audio)
        self.assertIn('"enemy_hurt": 0.075', audio)
        self.assertIn('"break": 0.095', audio)
        self.assertIn('"coin": 0.09', audio)
        self.assertNotIn('"blaster":', audio.split("const SPATIAL_RETRIGGER := ", 1)[1].split("\n",1)[0])
        self.assertIn("return AudioEmission.should_emit(", audio)
        self.assertIn("static func should_emit(", portable)
        self.assertIn("audio", online)
        self.assertIn("native and stock-Godot sound coalescing parity", focused)
        self.assertIn("test_spatial_sound_event_policy.gd", full)

if __name__ == "__main__":
    unittest.main()
