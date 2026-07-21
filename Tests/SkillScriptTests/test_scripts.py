import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[2]
FIXTURE = REPOSITORY / "Tests/SkillFixtures/PinPatch"
SCAN = REPOSITORY / "skills/pinpatch-apply/scripts/scan_pending.py"
RECORD = REPOSITORY / "skills/pinpatch-apply/scripts/record_result.py"
PIN_ID = "22222222-2222-4222-8222-222222222222"
REVISION_ID = "33333333-3333-4333-8333-333333333333"


class SkillScriptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="PinPatchSkillTests-")
        self.root = Path(self.temporary.name) / "PinPatch"
        shutil.copytree(FIXTURE, self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def run_json(self, *arguments):
        completed = subprocess.run(
            [sys.executable, *map(str, arguments)],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout)

    def test_scan_ignores_index_and_result_removes_current_revision_from_queue(self):
        first = self.run_json(SCAN, "--root", self.root)
        self.assertEqual(first["pendingCount"], 1)
        self.assertEqual(first["pending"][0]["pinID"], PIN_ID)
        self.assertTrue(first["pending"][0]["cropImagePath"].endswith("assets/crop.png"))

        result = self.run_json(
            RECORD,
            "--root", self.root,
            "--pin-id", PIN_ID,
            "--revision-id", REVISION_ID,
            "--status", "resolved",
            "--summary", "Updated color.\nVerified focused tests.",
        )
        self.assertEqual(result["summary"], "Updated color. Verified focused tests.")
        self.assertTrue((self.root / "results" / f"{PIN_ID}.json").is_file())
        self.assertEqual(self.run_json(SCAN, "--root", self.root)["pendingCount"], 0)

    def test_record_rejects_stale_revision(self):
        current = self.root / "pins" / PIN_ID / "current.json"
        current.write_text(json.dumps({"revisionID": "44444444-4444-4444-8444-444444444444"}), encoding="utf-8")
        completed = subprocess.run(
            [
                sys.executable,
                str(RECORD),
                "--root", str(self.root),
                "--pin-id", PIN_ID,
                "--revision-id", REVISION_ID,
                "--status", "resolved",
                "--summary", "Should not be written",
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("stale revision", completed.stderr)
        self.assertFalse((self.root / "results" / f"{PIN_ID}.json").exists())


if __name__ == "__main__":
    unittest.main()
