"""Provider contract for trustworthy G3 runtime resource observations.

The harness is Python, while the real MLX executor may be Swift.  The contract
is deliberately transport-neutral so a Python worker provider or a Swift-to-
Python exporter can implement the same envelope.  No live provider is registered
in this package yet: production gating therefore fails closed until a concrete,
reviewed emitter is added to the source-controlled trust registry.

Unit-test fixtures may exercise the pure isolation evaluator, but they are not
runtime attestations and cannot be accepted by ``require_runtime_isolation``.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from types import MappingProxyType
from typing import Any, Mapping, Protocol, Sequence
import re

ATTESTATION_CONTRACT_ID = "SIMIGO-G3-RUNTIME-ATTESTATION-V1"
ATTESTATION_CONTRACT_VERSION = 1
_SHA256 = re.compile(r"^[0-9a-f]{64}$")

PYTHON_WORKER_PROVIDER_ID = "simigo.g3.python-live-worker.v1"
SWIFT_MLX_PROVIDER_ID = "simigo.simi2.swift-mlx-live-worker.v1"
LIVE_PROVIDER_KINDS = frozenset({"python-live-worker", "swift-mlx-live-worker"})
FIXTURE_PROVIDER_KINDS = frozenset({"fixture", "test-double", "synthetic", "replay"})


class RuntimeAttestationError(RuntimeError):
    """Base error for missing, malformed, or untrusted runtime attestations."""


class FixtureAttestationRejected(RuntimeAttestationError):
    """Raised when test/synthetic evidence is submitted to a production gate."""


class UnregisteredRuntimeAttestationProvider(RuntimeAttestationError):
    """Raised until a concrete live provider is source-registered and reviewed."""


class InvalidRuntimeAttestation(RuntimeAttestationError):
    """Raised when an attestation does not match the current challenge/run."""


@dataclass(frozen=True)
class AttestationRequest:
    """Fresh, per-run challenge passed to a live runtime adapter."""

    run_id: str
    challenge_nonce: str
    expected_arms: tuple[str, ...] = ("ES+IS", "IS-only")
    contract_id: str = ATTESTATION_CONTRACT_ID
    contract_version: int = ATTESTATION_CONTRACT_VERSION

    def __post_init__(self) -> None:
        if not self.run_id.strip():
            raise ValueError("run_id must be non-empty")
        if not self.challenge_nonce.strip():
            raise ValueError("challenge_nonce must be non-empty")
        if len(self.expected_arms) != 2 or len(set(self.expected_arms)) != 2:
            raise ValueError("expected_arms must name exactly two distinct arms")


@dataclass(frozen=True)
class RuntimeAttestation:
    """One arm's observation, exported by a live worker before generation.

    ``source_sha256`` binds the concrete exporter/build, not model weights.
    Model and tokenizer content hashes live in ``observation``.  IDs for model
    instances and mutable buffers must be sampled from actual runtime objects;
    they may not be derived from arm labels or a static config file.
    """

    contract_id: str
    contract_version: int
    provider_id: str
    provider_kind: str
    run_id: str
    challenge_nonce: str
    arm_id: str
    captured_at_utc: str
    source_revision: str
    source_sha256: str
    observation: Mapping[str, Any]


class RuntimeAttestationProvider(Protocol):
    """Transport-neutral contract; implemented by the real Python/Swift worker.

    A provider must collect after backend/model initialization and immediately
    before the first generation call.  It must report a real runtime call count
    of zero at collection time.  Implementing this Protocol alone does not grant
    trust: the concrete implementation must also be registered below in code.
    """

    # Concrete providers must define these as class-level constants. This is
    # intentional: the trust registry pins the exact concrete class path.
    provider_id: str
    provider_kind: str

    def collect(self, request: AttestationRequest) -> Sequence[RuntimeAttestation]: ...


# Exact provider implementation bindings.  Intentionally empty in this change:
# no real emitter has been implemented or authorized.  To enable production
# runs, add a concrete, reviewed class path for the selected worker path here.
# Raw mappings, duck-typed objects, and test doubles cannot self-register at
# runtime. MappingProxyType prevents harness code from changing the trust policy.
TRUSTED_LIVE_PROVIDER_TYPES: Mapping[str, str] = MappingProxyType({})


def _class_path(value: object) -> str:
    cls = type(value)
    return f"{cls.__module__}.{cls.__qualname__}"


def require_trusted_provider(provider: object) -> RuntimeAttestationProvider:
    """Return an exact registered provider instance or fail closed.

    This rejects raw fixture dictionaries, fixture providers and unregistered
    implementations before calling ``collect``.  A string claiming to be a live
    provider is not proof of a live source.
    """
    if isinstance(provider, (Mapping, list, tuple, str, bytes)) or provider is None:
        raise FixtureAttestationRejected(
            "raw observations are test inputs, not runtime attestations; provide a registered live provider"
        )

    provider_kind = getattr(type(provider), "provider_kind", None)
    provider_id = getattr(type(provider), "provider_id", None)
    if provider_kind in FIXTURE_PROVIDER_KINDS:
        raise FixtureAttestationRejected(f"fixture provider kind refused: {provider_kind}")
    if provider_kind not in LIVE_PROVIDER_KINDS:
        raise FixtureAttestationRejected(
            f"provider_kind must be one of {sorted(LIVE_PROVIDER_KINDS)!r}; got {provider_kind!r}"
        )
    if not isinstance(provider_id, str) or not provider_id:
        raise UnregisteredRuntimeAttestationProvider("provider class has no source-controlled provider_id")
    expected_type = TRUSTED_LIVE_PROVIDER_TYPES.get(provider_id)
    if expected_type is None:
        raise UnregisteredRuntimeAttestationProvider(
            f"no reviewed live provider is registered for {provider_id!r}; refusing to treat a fixture as live"
        )
    if _class_path(provider) != expected_type:
        raise UnregisteredRuntimeAttestationProvider(
            f"provider class mismatch for {provider_id!r}: expected {expected_type!r}, got {_class_path(provider)!r}"
        )
    return provider  # type: ignore[return-value]


def validate_attestation_batch(
    attestations: Sequence[RuntimeAttestation],
    request: AttestationRequest,
    *,
    expected_provider_id: str,
    expected_provider_kind: str,
) -> list[dict[str, Any]]:
    """Validate envelope provenance and return observations for the pure gate."""
    if not isinstance(attestations, (list, tuple)):
        raise InvalidRuntimeAttestation("provider.collect must return a list/tuple of RuntimeAttestation")
    if len(attestations) != len(request.expected_arms):
        raise InvalidRuntimeAttestation(
            f"expected {len(request.expected_arms)} arm attestations, got {len(attestations)}"
        )

    normalized: list[dict[str, Any]] = []
    observed_arms: list[str] = []
    for attestation in attestations:
        if type(attestation) is not RuntimeAttestation:
            raise FixtureAttestationRejected(
                "attestation item is not the exact RuntimeAttestation envelope type"
            )
        if attestation.contract_id != request.contract_id or attestation.contract_version != request.contract_version:
            raise InvalidRuntimeAttestation("attestation contract identity/version mismatch")
        if attestation.provider_id != expected_provider_id or attestation.provider_kind != expected_provider_kind:
            raise InvalidRuntimeAttestation("attestation provider identity/kind mismatch")
        if attestation.provider_kind in FIXTURE_PROVIDER_KINDS or attestation.provider_kind not in LIVE_PROVIDER_KINDS:
            raise FixtureAttestationRejected(f"non-live provider kind refused: {attestation.provider_kind!r}")
        if attestation.run_id != request.run_id or attestation.challenge_nonce != request.challenge_nonce:
            raise InvalidRuntimeAttestation("attestation run_id/challenge_nonce mismatch")
        if not isinstance(attestation.source_revision, str) or not attestation.source_revision.strip():
            raise InvalidRuntimeAttestation("source revision is required")
        if not isinstance(attestation.source_sha256, str) or not _SHA256.fullmatch(attestation.source_sha256):
            raise InvalidRuntimeAttestation("source_sha256 must be 64 lowercase hexadecimal characters")
        try:
            captured = datetime.fromisoformat(attestation.captured_at_utc.replace("Z", "+00:00"))
        except (AttributeError, TypeError, ValueError) as error:
            raise InvalidRuntimeAttestation("captured_at_utc is malformed") from error
        if captured.tzinfo is None or captured.utcoffset() != timezone.utc.utcoffset(captured):
            raise InvalidRuntimeAttestation("captured_at_utc must be timezone-aware UTC")
        if not isinstance(attestation.observation, Mapping):
            raise InvalidRuntimeAttestation("observation must be a mapping")

        row = dict(attestation.observation)
        if row.get("arm_id") != attestation.arm_id:
            raise InvalidRuntimeAttestation("envelope arm_id differs from observation arm_id")
        # These provenance values come from the validated envelope, not from an
        # arbitrary dictionary provided by the caller.
        row["attestation_source"] = f"{attestation.provider_id}@{attestation.source_revision}"
        row["observed_fields"] = sorted(
            key for key in row.keys()
            if key not in {"attestation_source", "observed_fields", "shared_read_only_artifacts"}
        )
        observed_arms.append(attestation.arm_id)
        normalized.append(row)

    if tuple(observed_arms) != request.expected_arms:
        raise InvalidRuntimeAttestation(
            f"attestation arms/order mismatch: expected {request.expected_arms!r}, got {tuple(observed_arms)!r}"
        )
    return normalized
