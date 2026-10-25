"""Fail-closed runtime isolation gate for a two-arm G3 execution.

This module validates attestations emitted by the *live runtime* after each arm's
backend is initialized but before the first generation invocation. It does not
itself prove that an attestor is truthful; integration must populate observations
from actual process/runtime handles, not hard-coded fixture values.

Read-only model/tokenizer files may be shared. Runtime instances, KV/prefix
caches, mutable buffers, cache namespaces, and writable roots may not be shared.
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any, Mapping, Sequence

from .runtime_attestation_provider import (
    AttestationRequest,
    RuntimeAttestationProvider,
    require_trusted_provider,
    validate_attestation_batch,
)

_REQUIRED_PROVENANCE_FIELDS = (
    "worker_pid",
    "isolation_unit_id",
    "model_instance_id",
    "model_content_sha256",
    "tokenizer_instance_id",
    "tokenizer_content_sha256",
    "weights_buffer_instance_id",
    "kv_cache_instance_id",
    "prefix_cache_instance_id",
    "runtime_buffer_instance_id",
    "kv_cache_namespace",
    "prefix_cache_namespace",
    "runtime_write_root",
    "generation_invocations_before_gate",
    "initialized_before_first_generation",
    "mutable_resource_ids",
)
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


def _nonempty(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _valid_sha256(value: Any) -> bool:
    return isinstance(value, str) and _SHA256.fullmatch(value) is not None


def _unique_nonempty(values: Sequence[Any]) -> bool:
    return all(_nonempty(v) for v in values) and len(set(values)) == len(values)


def _normalized_path(value: Any) -> str | None:
    if not _nonempty(value):
        return None
    try:
        return os.path.normcase(os.path.abspath(os.path.expanduser(value)))
    except (TypeError, ValueError, OSError):
        return None


def _paths_disjoint(paths: Sequence[Any]) -> bool:
    normalized = [_normalized_path(path) for path in paths]
    if any(path is None for path in normalized) or len(set(normalized)) != len(normalized):
        return False
    # Roots may not be ancestors/descendants. This prevents arm-specific files
    # from accidentally being written into a shared parent runtime directory.
    for i, left in enumerate(normalized):
        assert left is not None
        left_path = Path(left)
        for right in normalized[i + 1 :]:
            assert right is not None
            right_path = Path(right)
            try:
                left_path.relative_to(right_path)
                return False
            except ValueError:
                pass
            try:
                right_path.relative_to(left_path)
                return False
            except ValueError:
                pass
    return True


def _mapping(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def evaluate_runtime_isolation(
    observations: Sequence[Mapping[str, Any]],
    *,
    expected_arms: Sequence[str] = ("ES+IS", "IS-only"),
) -> dict[str, Any]:
    """Return a deterministic gate report; malformed/missing evidence fails closed.

    Each observation is expected to contain the fields in
    ``_REQUIRED_PROVENANCE_FIELDS`` plus:

      arm_id: unique arm label
      attestation_source: live adapter/component that observed the values
      observed_fields: field names actually sampled from the runtime
      model_content_sha256/tokenizer_content_sha256: identity of shared read-only
        artifacts (these may be equal across arms)

    ``mutable_resource_ids`` must enumerate actual mutable runtime handles/IDs,
    including runtime buffers and cache objects. Do not populate it from a static
    configuration file.
    """
    rows = [dict(_mapping(row)) for row in observations]
    expected = tuple(expected_arms)
    arms = [row.get("arm_id") for row in rows]

    checks: dict[str, bool] = {}
    details: dict[str, str] = {}

    def add(name: str, passed: bool, detail: str) -> None:
        checks[name] = bool(passed)
        details[name] = detail

    add(
        "exact_two_expected_arms",
        len(rows) == 2 and tuple(arms) == expected,
        f"expected ordered arms {expected!r}; observed {tuple(arms)!r}",
    )
    add("distinct_arm_ids", len(arms) == 2 and _unique_nonempty(arms), f"arm_ids={arms!r}")

    def values(field: str) -> list[Any]:
        return [row.get(field) for row in rows]

    pids = values("worker_pid")
    add(
        "distinct_live_worker_pids",
        len(pids) == 2 and all(type(pid) is int and pid > 0 for pid in pids) and len(set(pids)) == 2,
        f"worker_pids={pids!r}",
    )
    for field, check_name in (
        ("isolation_unit_id", "distinct_isolation_units"),
        ("model_instance_id", "distinct_model_instances"),
        ("tokenizer_instance_id", "distinct_tokenizer_instances"),
        ("weights_buffer_instance_id", "distinct_weights_buffer_instances"),
        ("kv_cache_instance_id", "distinct_kv_cache_instances"),
        ("prefix_cache_instance_id", "distinct_prefix_cache_instances"),
        ("runtime_buffer_instance_id", "distinct_runtime_buffer_instances"),
        ("kv_cache_namespace", "distinct_kv_cache_namespaces"),
        ("prefix_cache_namespace", "distinct_prefix_cache_namespaces"),
    ):
        actual = values(field)
        add(check_name, len(actual) == 2 and _unique_nonempty(actual), f"{field}={actual!r}")

    model_hashes = values("model_content_sha256")
    tokenizer_hashes = values("tokenizer_content_sha256")
    add(
        "same_valid_model_content",
        len(model_hashes) == 2 and all(_valid_sha256(v) for v in model_hashes) and model_hashes[0] == model_hashes[1],
        f"model_content_sha256={model_hashes!r}",
    )
    add(
        "same_valid_tokenizer_content",
        len(tokenizer_hashes) == 2 and all(_valid_sha256(v) for v in tokenizer_hashes) and tokenizer_hashes[0] == tokenizer_hashes[1],
        f"tokenizer_content_sha256={tokenizer_hashes!r}",
    )

    roots = values("runtime_write_root")
    add("disjoint_runtime_write_roots", len(roots) == 2 and _paths_disjoint(roots), f"runtime_write_roots={roots!r}")

    mutable_sets: list[set[str]] = []
    mutable_well_formed = True
    for row in rows:
        raw = row.get("mutable_resource_ids")
        if not isinstance(raw, (list, tuple, set, frozenset)) or not raw or not all(_nonempty(x) for x in raw):
            mutable_well_formed = False
            mutable_sets.append(set())
        else:
            mutable_sets.append(set(raw))
    shared_mutable = sorted(mutable_sets[0] & mutable_sets[1]) if len(mutable_sets) == 2 else []
    add(
        "no_shared_mutable_resources",
        len(mutable_sets) == 2 and mutable_well_formed and not shared_mutable,
        f"shared_mutable_resource_ids={shared_mutable!r}; well_formed={mutable_well_formed}",
    )

    before_generation = [row.get("initialized_before_first_generation") for row in rows]
    add(
        "runtime_initialized_before_generation",
        len(before_generation) == 2 and all(value is True for value in before_generation),
        f"initialized_before_first_generation={before_generation!r}",
    )
    invocation_counts = values("generation_invocations_before_gate")
    add(
        "zero_generation_invocations_before_gate",
        len(invocation_counts) == 2 and all(type(value) is int and value == 0 for value in invocation_counts),
        f"generation_invocations_before_gate={invocation_counts!r}",
    )

    provenance_ok = len(rows) == 2
    provenance_detail: list[dict[str, Any]] = []
    for row in rows:
        observed = row.get("observed_fields")
        observed_set = set(observed) if isinstance(observed, (list, tuple, set, frozenset)) else set()
        missing = sorted(set(_REQUIRED_PROVENANCE_FIELDS) - observed_set)
        source_ok = _nonempty(row.get("attestation_source"))
        row_ok = not missing and source_ok
        provenance_ok = provenance_ok and row_ok
        provenance_detail.append({"arm_id": row.get("arm_id"), "missing_fields": missing, "source_present": source_ok})
    add("live_attestation_provenance_complete", provenance_ok, repr(provenance_detail))

    failed = [name for name, passed in checks.items() if not passed]
    return {
        "gate": "G3_RUNTIME_ISOLATION_PRECHECK_V1",
        # This function deliberately accepts mappings for pure logic tests. Its
        # result is never live execution evidence, even if all checks are true.
        "evidence_class": "untrusted_observation_evaluation",
        "eligible_for_runtime_evidence": False,
        "passed": not failed,
        "check_count": len(checks),
        "passed_count": sum(checks.values()),
        "failed_count": len(failed),
        "failed_checks": failed,
        "checks": checks,
        "details": details,
        "model_generation_started_by_gate": False,
        "read_only_model_artifact_sharing_allowed": True,
    }


def require_runtime_isolation(
    provider: RuntimeAttestationProvider | object,
    *,
    run_id: str,
    challenge_nonce: str,
    expected_arms: Sequence[str] = ("ES+IS", "IS-only"),
) -> dict[str, Any]:
    """Require a source-registered live provider and fail closed before generation.

    Raw mappings/lists remain supported only by ``evaluate_runtime_isolation``
    for unit tests. They are explicitly refused here so a synthetic fixture
    cannot accidentally produce a green production preflight. This repository
    currently registers no live provider; calls therefore fail closed until a
    reviewed Python or Swift/MLX emitter is implemented and source-registered.
    """
    trusted_provider = require_trusted_provider(provider)
    request = AttestationRequest(
        run_id=run_id,
        challenge_nonce=challenge_nonce,
        expected_arms=tuple(expected_arms),
    )
    attestations = trusted_provider.collect(request)
    observations = validate_attestation_batch(
        attestations,
        request,
        expected_provider_id=type(trusted_provider).provider_id,
        expected_provider_kind=type(trusted_provider).provider_kind,
    )
    report = evaluate_runtime_isolation(observations, expected_arms=expected_arms)
    if not report["passed"]:
        failed = ", ".join(report["failed_checks"])
        raise RuntimeError(f"G3 runtime isolation precheck refused execution: {failed}")
    report["evidence_class"] = "registered_live_runtime_attestation"
    report["eligible_for_runtime_evidence"] = True
    report["provider_id"] = type(trusted_provider).provider_id
    report["provider_kind"] = type(trusted_provider).provider_kind
    report["run_id"] = run_id
    report["challenge_nonce"] = challenge_nonce
    report["attestation_count"] = len(attestations)
    return report
