from __future__ import annotations

import copy
import hashlib
import unittest

from g3.gate.g3_runtime_isolation_gate import evaluate_runtime_isolation, require_runtime_isolation
from g3.gate.runtime_attestation_provider import FixtureAttestationRejected

FIELDS = [
    "worker_pid", "isolation_unit_id", "model_instance_id", "model_content_sha256",
    "tokenizer_instance_id", "tokenizer_content_sha256", "weights_buffer_instance_id",
    "kv_cache_instance_id", "prefix_cache_instance_id", "runtime_buffer_instance_id",
    "kv_cache_namespace", "prefix_cache_namespace", "runtime_write_root",
    "generation_invocations_before_gate", "initialized_before_first_generation",
    "mutable_resource_ids",
]
MODEL_SHA = hashlib.sha256(b"same-model-weights").hexdigest()
TOKENIZER_SHA = hashlib.sha256(b"same-tokenizer").hexdigest()


def arm(arm_id: str, suffix: str, pid: int, root: str) -> dict:
    row = {
        "arm_id": arm_id,
        "worker_pid": pid,
        "isolation_unit_id": f"sandbox-{suffix}",
        "model_instance_id": f"model-instance-{suffix}",
        "model_content_sha256": MODEL_SHA,
        "tokenizer_instance_id": f"tokenizer-instance-{suffix}",
        "tokenizer_content_sha256": TOKENIZER_SHA,
        "weights_buffer_instance_id": f"weights-buffer-{suffix}",
        "kv_cache_instance_id": f"kv-cache-{suffix}",
        "prefix_cache_instance_id": f"prefix-cache-{suffix}",
        "runtime_buffer_instance_id": f"runtime-buffer-{suffix}",
        "kv_cache_namespace": f"kv-ns-{suffix}",
        "prefix_cache_namespace": f"prefix-ns-{suffix}",
        "runtime_write_root": root,
        "generation_invocations_before_gate": 0,
        "initialized_before_first_generation": True,
        "mutable_resource_ids": [
            f"mutable-model-{suffix}", f"mutable-tokenizer-{suffix}",
            f"mutable-weights-{suffix}", f"mutable-kv-{suffix}",
            f"mutable-prefix-{suffix}", f"mutable-runtime-{suffix}",
        ],
        "attestation_source": f"live-runtime-probe-{suffix}",
        "observed_fields": list(FIELDS),
        # Same immutable on-disk artifacts are deliberately permitted.
        "shared_read_only_artifacts": [MODEL_SHA, TOKENIZER_SHA],
    }
    return row


class RuntimeIsolationGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.observations = [
            arm("ES+IS", "a", 41001, "/tmp/simigo-g3/es-is"),
            arm("IS-only", "b", 41002, "/tmp/simigo-g3/is-only"),
        ]

    def test_happy_path_all_checks_pass(self) -> None:
        report = evaluate_runtime_isolation(self.observations)
        self.assertTrue(report["passed"], report["details"])
        self.assertEqual(report["failed_count"], 0)
        self.assertTrue(report["read_only_model_artifact_sharing_allowed"])
        self.assertEqual(report["evidence_class"], "untrusted_observation_evaluation")
        self.assertFalse(report["eligible_for_runtime_evidence"])

    def test_gate_returns_auditable_check_inventory(self) -> None:
        report = evaluate_runtime_isolation(self.observations)
        self.assertGreaterEqual(report["check_count"], 15)
        self.assertEqual(report["check_count"], report["passed_count"] + report["failed_count"])

    def test_shared_kv_instance_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["kv_cache_instance_id"] = bad[0]["kv_cache_instance_id"]
        report = evaluate_runtime_isolation(bad)
        self.assertFalse(report["checks"]["distinct_kv_cache_instances"])
        with self.assertRaisesRegex(FixtureAttestationRejected, "raw observations"):
            require_runtime_isolation(bad, run_id="unit-test", challenge_nonce="unit-test-nonce")

    def test_shared_prefix_cache_namespace_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["prefix_cache_namespace"] = bad[0]["prefix_cache_namespace"]
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["distinct_prefix_cache_namespaces"])

    def test_shared_tokenizer_instance_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["tokenizer_instance_id"] = bad[0]["tokenizer_instance_id"]
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["distinct_tokenizer_instances"])

    def test_shared_mutable_resource_id_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["mutable_resource_ids"].append(bad[0]["mutable_resource_ids"][0])
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["no_shared_mutable_resources"])

    def test_same_model_content_is_allowed_but_different_model_content_fails(self) -> None:
        good = evaluate_runtime_isolation(self.observations)
        self.assertTrue(good["checks"]["same_valid_model_content"])
        bad = copy.deepcopy(self.observations)
        bad[1]["model_content_sha256"] = hashlib.sha256(b"different model").hexdigest()
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["same_valid_model_content"])

    def test_same_tokenizer_content_is_allowed_but_different_tokenizer_content_fails(self) -> None:
        self.assertTrue(evaluate_runtime_isolation(self.observations)["checks"]["same_valid_tokenizer_content"])
        bad = copy.deepcopy(self.observations)
        bad[1]["tokenizer_content_sha256"] = "not-a-sha256"
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["same_valid_tokenizer_content"])

    def test_nested_writable_roots_fail(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["runtime_write_root"] = "/tmp/simigo-g3/es-is/child"
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["disjoint_runtime_write_roots"])

    def test_same_worker_pid_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["worker_pid"] = bad[0]["worker_pid"]
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["distinct_live_worker_pids"])

    def test_generation_before_gate_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["generation_invocations_before_gate"] = 1
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["zero_generation_invocations_before_gate"])

    def test_runtime_not_initialized_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[0]["initialized_before_first_generation"] = False
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["runtime_initialized_before_generation"])

    def test_missing_live_provenance_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["attestation_source"] = ""
        bad[1]["observed_fields"].remove("kv_cache_instance_id")
        report = evaluate_runtime_isolation(bad)
        self.assertFalse(report["checks"]["live_attestation_provenance_complete"])

    def test_missing_or_malformed_mutable_inventory_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[0]["mutable_resource_ids"] = []
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["no_shared_mutable_resources"])

    def test_wrong_arm_set_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["arm_id"] = "OTHER"
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["exact_two_expected_arms"])

    def test_duplicate_arm_ids_fail(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["arm_id"] = bad[0]["arm_id"]
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["distinct_arm_ids"])

    def test_missing_namespace_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["kv_cache_namespace"] = None
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["distinct_kv_cache_namespaces"])

    def test_missing_runtime_root_fails(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[1]["runtime_write_root"] = None
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["disjoint_runtime_write_roots"])

    def test_read_only_file_sharing_does_not_affect_mutable_inventory(self) -> None:
        self.observations[1]["shared_read_only_artifacts"] = self.observations[0]["shared_read_only_artifacts"]
        report = evaluate_runtime_isolation(self.observations)
        self.assertTrue(report["passed"], report["details"])

    def test_provenance_must_cover_mutable_resource_inventory(self) -> None:
        bad = copy.deepcopy(self.observations)
        bad[0]["observed_fields"].remove("mutable_resource_ids")
        self.assertFalse(evaluate_runtime_isolation(bad)["checks"]["live_attestation_provenance_complete"])

    def test_empty_observation_fails_closed(self) -> None:
        report = evaluate_runtime_isolation([])
        self.assertFalse(report["passed"])
        self.assertEqual(report["failed_count"], report["check_count"])
        self.assertFalse(report["eligible_for_runtime_evidence"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
