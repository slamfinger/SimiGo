from __future__ import annotations

import hashlib
import unittest
from dataclasses import replace

from g3.gate.g3_runtime_isolation_gate import evaluate_runtime_isolation, require_runtime_isolation
from g3.gate.runtime_attestation_provider import (
    ATTESTATION_CONTRACT_ID,
    AttestationRequest,
    FixtureAttestationRejected,
    InvalidRuntimeAttestation,
    RuntimeAttestation,
    UnregisteredRuntimeAttestationProvider,
    validate_attestation_batch,
)


class DeclaredFixtureProvider:
    provider_id = "test.fixture.provider"
    provider_kind = "fixture"

    def collect(self, request: AttestationRequest):
        return []


class UnregisteredLiveClaimProvider:
    # A live-looking label is insufficient: exact provider class registration is
    # source-controlled and intentionally empty until a real emitter is reviewed.
    provider_id = "simigo.g3.python-live-worker.v1"
    provider_kind = "python-live-worker"

    def collect(self, request: AttestationRequest):
        return []


def _arm(arm_id: str, suffix: str, pid: int, root: str) -> dict:
    return {
        "arm_id": arm_id,
        "worker_pid": pid,
        "isolation_unit_id": f"sandbox-{suffix}",
        "model_instance_id": f"model-instance-{suffix}",
        "model_content_sha256": hashlib.sha256(b"same-model-weights").hexdigest(),
        "tokenizer_instance_id": f"tokenizer-instance-{suffix}",
        "tokenizer_content_sha256": hashlib.sha256(b"same-tokenizer").hexdigest(),
        "weights_buffer_instance_id": f"weights-buffer-{suffix}",
        "kv_cache_instance_id": f"kv-cache-{suffix}",
        "prefix_cache_instance_id": f"prefix-cache-{suffix}",
        "runtime_buffer_instance_id": f"runtime-buffer-{suffix}",
        "kv_cache_namespace": f"kv-ns-{suffix}",
        "prefix_cache_namespace": f"prefix-ns-{suffix}",
        "runtime_write_root": root,
        "generation_invocations_before_gate": 0,
        "initialized_before_first_generation": True,
        "mutable_resource_ids": [f"mutable-{suffix}-model", f"mutable-{suffix}-kv", f"mutable-{suffix}-tokenizer"],
        "shared_read_only_artifacts": [hashlib.sha256(b"same-model-weights").hexdigest(), hashlib.sha256(b"same-tokenizer").hexdigest()],
        "attestation_source": f"test-fixture-{suffix}",
        "observed_fields": [
            "worker_pid", "isolation_unit_id", "model_instance_id", "model_content_sha256",
            "tokenizer_instance_id", "tokenizer_content_sha256", "weights_buffer_instance_id",
            "kv_cache_instance_id", "prefix_cache_instance_id", "runtime_buffer_instance_id",
            "kv_cache_namespace", "prefix_cache_namespace", "runtime_write_root",
            "generation_invocations_before_gate", "initialized_before_first_generation",
            "mutable_resource_ids",
        ],
    }


def envelopes(request: AttestationRequest) -> list[RuntimeAttestation]:
    rows = [
        _arm("ES+IS", "a", 41001, "/tmp/simigo-g3/es-is"),
        _arm("IS-only", "b", 41002, "/tmp/simigo-g3/is-only"),
    ]
    build_sha = hashlib.sha256(b"provider-exporter-build").hexdigest()
    return [
        RuntimeAttestation(
            contract_id=ATTESTATION_CONTRACT_ID,
            contract_version=1,
            provider_id="simigo.g3.python-live-worker.v1",
            provider_kind="python-live-worker",
            run_id=request.run_id,
            challenge_nonce=request.challenge_nonce,
            arm_id=row["arm_id"],
            captured_at_utc="2026-10-20T10:00:00Z",
            source_revision="unit-test-revision",
            source_sha256=build_sha,
            observation=row,
        )
        for row in rows
    ]


class RuntimeAttestationProviderContractTests(unittest.TestCase):
    def test_raw_perfect_fixture_cannot_enter_production_gate(self) -> None:
        rows = [
            _arm("ES+IS", "a", 41001, "/tmp/simigo-g3/es-is"),
            _arm("IS-only", "b", 41002, "/tmp/simigo-g3/is-only"),
        ]
        self.assertTrue(evaluate_runtime_isolation(rows)["passed"])
        with self.assertRaisesRegex(FixtureAttestationRejected, "raw observations"):
            require_runtime_isolation(rows, run_id="g3-test", challenge_nonce="nonce-1")

    def test_declared_fixture_provider_is_hard_rejected(self) -> None:
        with self.assertRaisesRegex(FixtureAttestationRejected, "fixture provider kind"):
            require_runtime_isolation(
                DeclaredFixtureProvider(), run_id="g3-test", challenge_nonce="nonce-1"
            )

    def test_provider_cannot_self_promote_by_claiming_live_kind(self) -> None:
        with self.assertRaisesRegex(UnregisteredRuntimeAttestationProvider, "no reviewed live provider"):
            require_runtime_isolation(
                UnregisteredLiveClaimProvider(), run_id="g3-test", challenge_nonce="nonce-1"
            )

    def test_attestation_envelopes_bind_run_nonce_and_provider(self) -> None:
        request = AttestationRequest(run_id="g3-test", challenge_nonce="nonce-1")
        good = envelopes(request)
        normalized = validate_attestation_batch(
            good,
            request,
            expected_provider_id="simigo.g3.python-live-worker.v1",
            expected_provider_kind="python-live-worker",
        )
        self.assertEqual([row["arm_id"] for row in normalized], ["ES+IS", "IS-only"])
        bad = [replace(good[0], challenge_nonce="stale-nonce"), good[1]]
        with self.assertRaisesRegex(InvalidRuntimeAttestation, "run_id/challenge_nonce"):
            validate_attestation_batch(
                bad,
                request,
                expected_provider_id="simigo.g3.python-live-worker.v1",
                expected_provider_kind="python-live-worker",
            )

    def test_envelope_rejects_fixture_kind_even_with_live_provider_id(self) -> None:
        request = AttestationRequest(run_id="g3-test", challenge_nonce="nonce-1")
        bad = [replace(row, provider_kind="fixture") for row in envelopes(request)]
        with self.assertRaisesRegex(InvalidRuntimeAttestation, "provider identity/kind mismatch"):
            validate_attestation_batch(
                bad,
                request,
                expected_provider_id="simigo.g3.python-live-worker.v1",
                expected_provider_kind="python-live-worker",
            )

    def test_envelope_requires_source_build_digest(self) -> None:
        request = AttestationRequest(run_id="g3-test", challenge_nonce="nonce-1")
        bad = [replace(envelopes(request)[0], source_sha256="not-a-sha"), envelopes(request)[1]]
        with self.assertRaisesRegex(InvalidRuntimeAttestation, "source_sha256"):
            validate_attestation_batch(
                bad,
                request,
                expected_provider_id="simigo.g3.python-live-worker.v1",
                expected_provider_kind="python-live-worker",
            )

    def test_envelope_requires_exact_arm_set_and_order(self) -> None:
        request = AttestationRequest(run_id="g3-test", challenge_nonce="nonce-1")
        good = envelopes(request)
        bad = [good[1], good[0]]
        with self.assertRaisesRegex(InvalidRuntimeAttestation, "arms/order mismatch"):
            validate_attestation_batch(
                bad,
                request,
                expected_provider_id="simigo.g3.python-live-worker.v1",
                expected_provider_kind="python-live-worker",
            )

    def test_contract_has_swift_adapter_slot_but_no_live_provider_registered(self) -> None:
        from g3.gate.runtime_attestation_provider import LIVE_PROVIDER_KINDS, TRUSTED_LIVE_PROVIDER_TYPES
        self.assertIn("swift-mlx-live-worker", LIVE_PROVIDER_KINDS)
        self.assertEqual(dict(TRUSTED_LIVE_PROVIDER_TYPES), {})


if __name__ == "__main__":
    unittest.main(verbosity=2)
