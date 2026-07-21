import json
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[2]
FIXTURE = REPOSITORY / "Tests/SkillFixtures/PinPatch"
SCAN = REPOSITORY / "skills/pinpatch-apply/scripts/scan_pending.py"
RECORD = REPOSITORY / "skills/pinpatch-apply/scripts/record_result.py"
PREPARE = REPOSITORY / "skills/pinpatch-apply/scripts/prepare_input.py"
PREPARE_BATCH = REPOSITORY / "skills/pinpatch-apply/scripts/prepare_batch.py"
SCAN_BATCH = REPOSITORY / "skills/pinpatch-apply/scripts/scan_batch.py"
PACKAGE_BATCH = REPOSITORY / "skills/pinpatch-apply/scripts/package_batch.py"
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

    def test_scan_surfaces_blocked_result_instead_of_dropping_it(self):
        self.run_json(
            RECORD,
            "--root", self.root,
            "--pin-id", PIN_ID,
            "--revision-id", REVISION_ID,
            "--status", "blocked",
            "--summary", "Needs a design decision.",
        )
        scanned = self.run_json(SCAN, "--root", self.root)
        self.assertEqual(scanned["pendingCount"], 0)
        self.assertEqual(scanned["blockedCount"], 1)
        self.assertEqual(scanned["blocked"][0]["pinID"], PIN_ID)
        self.assertEqual(scanned["blocked"][0]["revisionID"], REVISION_ID)
        self.assertEqual(scanned["blocked"][0]["summary"], "Needs a design decision.")

    def test_batch_marks_duplicate_of_failed_input_as_error(self):
        broken = Path(self.temporary.name) / "Broken"
        broken.mkdir()
        prepared = subprocess.run(
            [
                sys.executable,
                str(PREPARE_BATCH),
                "--input", str(broken),
                "--input", str(broken),
                "--work-dir", str(Path(self.temporary.name) / "work"),
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(prepared.returncode, 2)
        payload = json.loads(prepared.stdout)
        self.assertEqual(payload["errorCount"], 2)
        self.assertEqual(payload["duplicateCount"], 0)
        self.assertEqual([item["status"] for item in payload["items"]], ["error", "error"])
        self.assertIn("which failed to prepare", payload["items"][1]["error"])

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

    def test_scan_uses_shared_screen_snapshot(self):
        legacy = self.root / "pins" / PIN_ID / "assets" / "screen.png"
        shared = self.root / "screens" / "11111111-1111-4111-8111-111111111111" / "screen.png"
        shared.parent.mkdir()
        legacy.replace(shared)

        pending = self.run_json(SCAN, "--root", self.root)["pending"][0]
        self.assertEqual(Path(pending["screenImagePath"]), shared.resolve())

    def test_batch_prepares_directories_and_zips_deduplicates_and_packages(self):
        archive_base = Path(self.temporary.name) / "Export"
        archive = Path(shutil.make_archive(
            str(archive_base),
            "zip",
            root_dir=self.root.parent,
            base_dir=self.root.name,
        ))
        work = Path(self.temporary.name) / "work"
        prepared = self.run_json(
            PREPARE_BATCH,
            "--input", self.root,
            "--input", archive,
            "--input", self.root,
            "--work-dir", work,
        )
        self.assertEqual(prepared["readyCount"], 2)
        self.assertEqual(prepared["duplicateCount"], 1)
        roots = [Path(item["root"]) for item in prepared["items"] if item["status"] == "ready"]

        scanned = self.run_json(
            SCAN_BATCH,
            "--root", roots[0],
            "--root", roots[1],
        )
        self.assertEqual(scanned["uniquePendingCount"], 1)
        self.assertEqual(len(scanned["duplicates"]), 1)
        self.assertEqual(scanned["duplicates"][0]["pinID"], PIN_ID)

        packaged = self.run_json(
            PACKAGE_BATCH,
            "--root", roots[0],
            "--root", roots[1],
            "--output-dir", Path(self.temporary.name) / "processed",
        )
        self.assertEqual(packaged["readyCount"], 2)
        for item in packaged["items"]:
            self.assertTrue(Path(item["output"]).is_file())

    def test_prepare_rejects_zip_path_traversal(self):
        archive = Path(self.temporary.name) / "Unsafe.zip"
        with zipfile.ZipFile(archive, "w") as handle:
            handle.writestr("../escape.txt", "unsafe")
        completed = subprocess.run(
            [
                sys.executable,
                str(PREPARE),
                "--input", str(archive),
                "--work-dir", str(Path(self.temporary.name) / "work"),
            ],
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("unsafe archive member path", completed.stderr)
        self.assertEqual(list(Path(self.temporary.name).rglob("escape.txt")), [])


if __name__ == "__main__":
    unittest.main()
