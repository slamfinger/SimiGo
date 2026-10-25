from __future__ import annotations

import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
HARNESS = HERE / "g3_harness.py"
REPO_ROOT = HERE.parents[5]

# Import the harness by its file-anchored directory. This mirrors what the
# reviewer checks: the module (and its gate import) must resolve from a fixed
# repo layout, not from whatever the current working directory happens to be.
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
import g3_harness  # noqa: E402


def _run_cli(cwd, extra):
    return subprocess.run(
        [sys.executable, str(HARNESS), *extra],
        cwd=str(cwd), capture_output=True, text=True)


# A refusal shaped exactly like the native Swift entry emits today (empty trust
# registry -> refuse at provider_trust, generation never reached).
def _refusal_record(run_id="t", nonce="n"):
    return {
        "gate": "G3_RUNTIME_ISOLATION_PRECHECK_V1",
        "stage": "provider_trust", "passed": False,
        "eligibleForRuntimeEvidence": False,
        "evidenceClass": "gate_refused_before_generation",
        "generationCallCount": 0, "modelGenerationStartedByGate": False,
        "isExecutionEvidence": False,
        "reason": "no reviewed live provider is registered for "
                  "simigo.g3.swift-runtime-resource-provider.v1",
        "failedChecks": [], "runID": run_id, "challengeNonce": nonce,
        "providerID": "simigo.g3.swift-runtime-resource-provider.v1",
        "providerKind": "swift-mlx-live-worker", "trustedLiveProviderCount": 0,
    }


def _cleared_record(run_id="t", nonce="n"):
    rec = dict(_refusal_record(run_id, nonce))
    rec.update(stage="cleared", passed=True, eligibleForRuntimeEvidence=True,
               evidenceClass="registered_live_runtime_attestation",
               generationCallCount=1, reason="isolation gate cleared; generation entered")
    return rec


class SwiftBoundaryAnchorsTests(unittest.TestCase):
    def test_swift_sources_are_anchored_to_repo_root(self):
        # The native gate the harness defers to must live at file-anchored paths,
        # independent of cwd.
        self.assertTrue(g3_harness.SWIFT_PKG_DIR.is_dir())
        for src in g3_harness.SWIFT_ENTRY_SOURCES:
            self.assertTrue(src.is_file(), "missing native gate source %s" % src)


class ContrastPythonGateTests(unittest.TestCase):
    # The Python gate is now a research/contrast tool, not the execution
    # boundary; these prove its own fail-closed reject behavior is intact.
    def test_gate_import_resolves_regardless_of_launch_directory(self):
        require_runtime_isolation, registry = g3_harness._load_runtime_isolation()
        self.assertTrue(callable(require_runtime_isolation))
        self.assertEqual(len(registry), 0)  # fail-closed: nothing trusted yet

    def test_perfect_fixture_is_refused_not_fallen_back_on(self):
        raw = [{"arm_id": "ES+IS", "worker_pid": 1}, {"arm_id": "IS-only", "worker_pid": 2}]
        iso = g3_harness.preflight_runtime_isolation(
            raw, run_id="t", challenge_nonce="n")
        self.assertFalse(iso["passed"])
        self.assertTrue(iso["refused"])
        self.assertTrue(iso["reason"])
        self.assertFalse(iso["eligible_for_runtime_evidence"])

    def test_no_trusted_provider_refuses_in_contrast_gate(self):
        iso = g3_harness.preflight_runtime_isolation(
            None, run_id="t", challenge_nonce="n")
        self.assertFalse(iso["passed"])
        self.assertTrue(iso["refused"])
        self.assertEqual(iso["trusted_provider_count"], 0)
        self.assertFalse(iso["provider_present"])


class RealRunnerSwiftBoundaryTests(unittest.TestCase):
    def test_unregistered_provider_refuses_before_generation(self):
        rec = g3_harness.run_real_runner(
            run_id="t", challenge_nonce="n",
            swift_invoker=lambda rid, nc, binary=None: (_refusal_record(), 3, None))
        self.assertEqual(rec["result"], "REFUSED_BY_NATIVE_GATE_BEFORE_GENERATION")
        self.assertFalse(rec["native_gate_passed"])
        self.assertEqual(rec["native_generation_call_count"], 0)
        self.assertFalse(rec["generation_reached_in_python"])
        self.assertEqual(rec["actual_model_starts"], 0)
        self.assertFalse(rec["model_generation_started"])
        self.assertFalse(rec["is_execution_evidence"])

    def test_swift_record_is_collected_verbatim(self):
        sent = _refusal_record()
        rec = g3_harness.run_real_runner(
            run_id="t", challenge_nonce="n",
            swift_invoker=lambda rid, nc, binary=None: (sent, 3, None))
        # The harness must not rewrite the native gate's verdict.
        self.assertEqual(rec["swift_gate_record"], sent)
        self.assertEqual(rec["swift_entry_returncode"], 3)

    def test_missing_or_failed_swift_entry_fails_closed_no_fallback(self):
        rec = g3_harness.run_real_runner(
            run_id="t", challenge_nonce="n",
            swift_invoker=lambda rid, nc, binary=None: (None, None, "swift_entry_missing: x"))
        self.assertEqual(rec["result"], "SWIFT_ENTRY_UNAVAILABLE_FAIL_CLOSED")
        self.assertIsNone(rec["swift_gate_record"])
        self.assertTrue(rec["swift_entry_failure"])
        # No fallback to a fixture or an old runner: nothing was started.
        self.assertEqual(rec["actual_model_starts"], 0)
        self.assertFalse(rec["is_execution_evidence"])
        self.assertNotIn("runtime_isolation", rec)  # no Python-side attestation

    def test_generation_only_after_native_gate_clears(self):
        # Even if the native gate cleared, Python never claims execution
        # evidence nor starts a model itself; generation ran inside Swift only.
        rec = g3_harness.run_real_runner(
            run_id="t", challenge_nonce="n",
            swift_invoker=lambda rid, nc, binary=None: (_cleared_record(), 0, None))
        self.assertEqual(rec["result"], "NATIVE_GATE_CLEARED")
        self.assertTrue(rec["native_gate_passed"])
        self.assertEqual(rec["native_generation_call_count"], 1)
        self.assertFalse(rec["generation_reached_in_python"])
        self.assertFalse(rec["model_generation_started"])
        self.assertEqual(rec["actual_model_starts"], 0)
        self.assertFalse(rec["is_execution_evidence"])
        self.assertNotEqual(rec["result"], "PASS")

    def test_record_is_json_serializable(self):
        rec = g3_harness.run_real_runner(
            run_id="t", challenge_nonce="n",
            swift_invoker=lambda rid, nc, binary=None: (_refusal_record(), 3, None))
        text = json.dumps(rec, ensure_ascii=False, sort_keys=True)
        self.assertIn("REFUSED_BY_NATIVE_GATE_BEFORE_GENERATION", text)

    def test_provenance_hashes_the_current_harness(self):
        rec = g3_harness.run_real_runner(
            run_id="t", challenge_nonce="n",
            swift_invoker=lambda rid, nc, binary=None: (_refusal_record(), 3, None))
        expected = hashlib.sha256(HARNESS.read_bytes()).hexdigest()
        self.assertEqual(rec["provenance"]["harness_sha256"], expected)
        # The native gate sources the run depends on are bound in provenance.
        self.assertTrue(rec["provenance"]["swift_entry_source_sha256"])


@unittest.skipUnless(g3_harness.SWIFT_ENTRY_BINARY.exists(),
                     "native Swift entry not built; run `swift build --target G3SwiftIsolationEntry`")
class NativeSwiftEntryIntegrationTests(unittest.TestCase):
    def test_real_binary_refuses_with_zero_generation(self):
        rec, rc, failure = g3_harness.invoke_swift_gate("r1", "n1")
        self.assertIsNone(failure)
        self.assertEqual(rc, 3)
        self.assertEqual(rec["generationCallCount"], 0)
        self.assertFalse(rec["passed"])
        self.assertFalse(rec["eligibleForRuntimeEvidence"])
        self.assertEqual(rec["trustedLiveProviderCount"], 0)

    def test_run_real_runner_end_to_end_refuses(self):
        rec = g3_harness.run_real_runner(run_id="r1", challenge_nonce="n1")
        self.assertEqual(rec["result"], "REFUSED_BY_NATIVE_GATE_BEFORE_GENERATION")
        self.assertEqual(rec["native_generation_call_count"], 0)
        self.assertFalse(rec["is_execution_evidence"])
        self.assertEqual(rec["actual_model_starts"], 0)


class RealRunnerCliSubprocessTests(unittest.TestCase):
    def _pinned(self, cwd):
        proc = _run_cli(cwd, ["--real-runner", "--run-id", "FIXED",
                              "--challenge-nonce", "NFIXED"])
        return proc, json.loads(proc.stdout)

    def test_real_runner_fails_closed_identically_from_repo_root_and_tmp(self):
        proc_root, rec_root = self._pinned(REPO_ROOT)
        proc_tmp, rec_tmp = self._pinned(tempfile.gettempdir())
        for rec in (rec_root, rec_tmp):
            # Fail-closed regardless of whether the native binary is built here:
            # either the gate refused, or the entry was unavailable -- never a
            # green run and never a fallback.
            self.assertIn(rec["result"], {
                "REFUSED_BY_NATIVE_GATE_BEFORE_GENERATION",
                "SWIFT_ENTRY_UNAVAILABLE_FAIL_CLOSED"})
            self.assertFalse(rec["native_gate_passed"])
            self.assertNotEqual(rec["result"], "NATIVE_GATE_CLEARED")
            self.assertEqual(rec["actual_model_starts"], 0)
            self.assertFalse(rec["model_generation_started"])
            self.assertFalse(rec["is_execution_evidence"])
        # File-anchored, no subprocess pid: the record is byte-equal across cwd.
        self.assertEqual(rec_root, rec_tmp)

    def test_real_runner_cli_exit_code_nonzero(self):
        proc, _ = self._pinned(REPO_ROOT)
        self.assertEqual(proc.returncode, 1)

    def test_dry_run_unchanged_from_repo_root_and_tmp(self):
        proc_root = _run_cli(REPO_ROOT, [])
        proc_tmp = _run_cli(tempfile.gettempdir(), [])
        for proc in (proc_root, proc_tmp):
            self.assertEqual(proc.returncode, 0, proc.stderr)
            rec = json.loads(proc.stdout)
            self.assertTrue(rec["dry_run"])
            self.assertEqual(rec["result"], "PASS")
            self.assertFalse(rec["is_execution_evidence"])
            self.assertEqual(rec["budget"]["actual_model_starts"], 0)
            self.assertEqual(rec["budget"]["measured_calculator_invocations"], 20)
            self.assertTrue(all(f["decision"] == "PASS"
                                for f in rec["fixtures"].values()))

    def test_dry_run_hashes_the_current_harness_file(self):
        rec = json.loads(_run_cli(REPO_ROOT, []).stdout)
        expected = hashlib.sha256(HARNESS.read_bytes()).hexdigest()
        self.assertEqual(rec["provenance"]["harness_sha256"], expected)


if __name__ == "__main__":
    unittest.main(verbosity=2)
