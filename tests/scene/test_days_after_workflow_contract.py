"""Guard against accidental duplicate workflow fragments and invalid smoke assertions.

GitHub also parses the YAML; these source checks keep known regressions out.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"


class TestDaysAfterWorkflows(unittest.TestCase):
    def test_gameplay_smoke_and_unique_steps(self):
        content = (WORKFLOWS / "days-after-gameplay.yml").read_text()
        self.assertEqual(content.count("      - name: Upload smoke test logs"), 1)
        self.assertEqual(content.count("      - name: Run survivor persistence smoke"), 1)
        self.assertEqual(content.count("      - name: Run gameplay smoke with real physics steps"), 1)
        self.assertIn("grep -Eq '^PASS: Days After .*physics frames\\.' days-after-smoke.log", content)
        self.assertNotIn("\n days-after-smoke.log\n", content)

    def test_integration_smoke_and_unique_steps(self):
        content = (WORKFLOWS / "days-after-integration.yml").read_text()
        self.assertEqual(content.count("      - name: Import and exercise survival game"), 1)
        self.assertIn("grep -Eq '^PASS: Days After .*physics frames\\.' smoke.log", content)
        self.assertNotIn("\n smoke.log\n", content)


if __name__ == "__main__":
    unittest.main()
