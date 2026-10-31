#!/usr/bin/env python3
"""Regression tests for the App XCTest isolation plist rewriter."""

import json
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "make_isolated_xctestrun.py"


class IsolatedXCTestRunTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.products = self.root / "Products"
        self.app = self.products / "Debug" / "SimiGo.app"
        binary = self.app / "Contents" / "MacOS" / "SimiGo"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"test-host-placeholder")
        self.iso = self.root / "evidence" / "isolation"
        self.iso.mkdir(parents=True)
        self.base = self.products / "SimiGo.xctestrun"
        self.out = self.products / "xctestrun_isolated.xctestrun"
        self.record = self.root / "record.json"
        self.write_base({
            "TestConfigurations": [{
                "TestTargets": [
                    {
                        "BlueprintName": "SimiGoTests",
                        "EnvironmentVariables": {"KEEP_ME": "yes"},
                    },
                    {
                        "BlueprintName": "OtherTests",
                        "EnvironmentVariables": {"OTHER_ONLY": "yes"},
                    },
                ]
            }]
        })

    def tearDown(self):
        self.tmp.cleanup()

    def write_base(self, doc):
        self.base.parent.mkdir(parents=True, exist_ok=True)
        with self.base.open("wb") as stream:
            plistlib.dump(doc, stream)

    def run_generator(self, *extra):
        return subprocess.run(
            [
                sys.executable, str(SCRIPT),
                "--app", str(self.app),
                "--isolation-root", str(self.iso),
                "--base-xctestrun", str(self.base),
                "--out", str(self.out),
                "--record", str(self.record),
                *extra,
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def read_output(self):
        with self.out.open("rb") as stream:
            return plistlib.load(stream)

    def test_injects_four_isolated_roots_into_each_test_target(self):
        result = self.run_generator()
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        doc = self.read_output()
        roots = {
            "SIMIGO_HOME": str(self.iso / "home"),
            "SIMIGO_CACHE_ROOT": str(self.iso / "cache"),
            "SIMIGO_STATE_GRAPH_STORE": str(
                self.iso / "state-graph" / "reference-graph-v1.json"
            ),
            "QODER_PROJECTS_DIR": str(self.iso / "qoder-projects"),
        }
        for target in doc["TestConfigurations"][0]["TestTargets"]:
            env = target["EnvironmentVariables"]
            for key, value in roots.items():
                self.assertEqual(env[key], value)
            self.assertEqual(env["KEEP_ME"] == "yes", target["BlueprintName"] == "SimiGoTests")
        rec = json.loads(self.record.read_text())
        self.assertEqual(rec["other_differences"], [])
        self.assertEqual(rec["target_env_applied"], [])

    def test_opt_ins_are_applied_only_to_the_named_target(self):
        result = self.run_generator(
            "--target-env", "SimiGoTests:SIMIGO_PREFIX_POOL=1",
            "--target-env", "SimiGoTests:SIMIGO_BRANCH_CHECKPOINTS=1",
            "--target-env", "SimiGoTests:SIMIGO_REQUEST_BUDGET_MS=0",
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        targets = self.read_output()["TestConfigurations"][0]["TestTargets"]
        by_name = {target["BlueprintName"]: target["EnvironmentVariables"] for target in targets}
        self.assertEqual(by_name["SimiGoTests"]["SIMIGO_PREFIX_POOL"], "1")
        self.assertEqual(by_name["SimiGoTests"]["SIMIGO_BRANCH_CHECKPOINTS"], "1")
        self.assertEqual(by_name["SimiGoTests"]["SIMIGO_REQUEST_BUDGET_MS"], "0")
        for key in (
            "SIMIGO_PREFIX_POOL",
            "SIMIGO_BRANCH_CHECKPOINTS",
            "SIMIGO_REQUEST_BUDGET_MS",
        ):
            self.assertNotIn(key, by_name["OtherTests"])
        rec = json.loads(self.record.read_text())
        self.assertEqual(len(rec["target_env_applied"]), 3)
        self.assertTrue(all(item["target"] == "SimiGoTests" for item in rec["target_env_applied"]))

    def test_unknown_target_fails_before_writing_output(self):
        result = self.run_generator("--target-env", "MissingTests:SIMIGO_PREFIX_POOL=1")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.out.exists())

    def test_non_allowlisted_value_fails_before_writing_output(self):
        result = self.run_generator("--target-env", "SimiGoTests:SIMIGO_PREFIX_POOL=0")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertFalse(self.out.exists())

    def test_conflicting_preexisting_isolation_root_is_not_overwritten(self):
        self.write_base({
            "TestConfigurations": [{
                "TestTargets": [{
                    "BlueprintName": "SimiGoTests",
                    "EnvironmentVariables": {"SIMIGO_HOME": "/real/user/home/.simigo"},
                }]
            }]
        })
        result = self.run_generator()
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertFalse(self.out.exists())


if __name__ == "__main__":
    unittest.main()
