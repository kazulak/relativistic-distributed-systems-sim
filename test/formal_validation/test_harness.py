from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
SPEC = importlib.util.spec_from_file_location(
    "formal_validation", REPO_ROOT / "scripts" / "formal_validation.py"
)
assert SPEC is not None and SPEC.loader is not None
HARNESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HARNESS)


def fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


class TlcClassifierTests(unittest.TestCase):
    def test_explicit_completion_and_empty_queue_pass(self) -> None:
        result = HARNESS.classify_tlc(fixture("tlc_pass.log"), "", 0, False)
        self.assertEqual(result["status"], "PASS")
        self.assertTrue(result["completion_marker_seen"])
        self.assertEqual(result["statistics"]["states_generated"], 13)
        self.assertEqual(result["statistics"]["states_queued"], 0)
        self.assertEqual(result["statistics"]["search_depth"], 7)

    def test_success_exit_without_completion_is_incomplete(self) -> None:
        result = HARNESS.classify_tlc("TLC2 Version 2.19\n", "", 0, False)
        self.assertEqual(result["status"], "INCOMPLETE")

    def test_rmi_exception_with_exit_zero_is_blocked(self) -> None:
        result = HARNESS.classify_tlc(
            fixture("tlc_rmi_exit_zero.log"), "", 0, False
        )
        self.assertEqual(result["status"], "BLOCKED")

    def test_timeout_is_incomplete_and_retains_progress_stats(self) -> None:
        result = HARNESS.classify_tlc(fixture("tlc_timeout.log"), "", 124, True)
        self.assertEqual(result["status"], "INCOMPLETE")
        self.assertEqual(result["statistics"]["states_generated"], 432393)
        self.assertEqual(result["statistics"]["states_queued"], 27072)

    def test_counterexample_is_fail(self) -> None:
        result = HARNESS.classify_tlc(fixture("tlc_violation.log"), "", 1, False)
        self.assertEqual(result["status"], "FAIL")

    def test_nonzero_queue_cannot_pass(self) -> None:
        output = fixture("tlc_pass.log").replace(
            "0 states left on queue", "2 states left on queue"
        )
        result = HARNESS.classify_tlc(output, "", 0, False)
        self.assertEqual(result["status"], "INCOMPLETE")


class ManifestTests(unittest.TestCase):
    def test_manifest_declares_every_checked_in_config(self) -> None:
        manifest = HARNESS.load_manifest()
        declared = {run["config"] for run in manifest["tlc_runs"]}
        checked_in = {
            str(path.relative_to(HARNESS.FORMAL_DIR))
            for path in (HARNESS.FORMAL_DIR / "models").glob("*.cfg")
        }
        self.assertEqual(declared, checked_in)

    def test_manifest_is_json_and_has_explicit_caps(self) -> None:
        manifest = json.loads(HARNESS.MANIFEST_PATH.read_text(encoding="utf-8"))
        for run in [*manifest["sany_runs"], *manifest["tlc_runs"]]:
            self.assertGreater(run["timeout_seconds"], 0)
            self.assertGreater(run["max_heap_mb"], 0)


if __name__ == "__main__":
    unittest.main()
