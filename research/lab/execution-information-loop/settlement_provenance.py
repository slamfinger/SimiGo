"""Signed settlement provenance for the production IS loop.

The signature is detached from the settlement object so it can bind the exact
content address of that object without a circular hash.  A settlement is only
reusable when the current settlement object and its signature object agree on
that address, the Ed25519 signature verifies against a trust anchor that lives
outside the database, and the signed provenance still matches the current task
item, source, dependency closure and validity basis.

The module deliberately exposes no generic `sign(bytes)` API.  Signing happens
only while constructing a settlement declaration inside
``CarrierInformationLoop.settle`` after the ordinary settlement contract has
been validated.  The private key is a deployment input, never a database row.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
from typing import Any, Mapping, Optional

PROVENANCE_SCHEMA_ID = "EINFO-SETTLEMENT-PROVENANCE-V1"
SIGNATURE_SCHEMA_ID = "EINFO-SETTLEMENT-SIGNATURE-V1"
SIGNING_KEY_SCHEMA_ID = "EINFO-SETTLEMENT-SIGNING-KEY-V1"
TRUST_ANCHOR_SCHEMA_ID = "EINFO-SETTLEMENT-TRUST-ANCHOR-V1"
SIGNATURE_ALGORITHM = "Ed25519"
POLICY_ENV = "SIMIGO_SETTLEMENT_PROVENANCE"
SIGNING_KEY_ENV = "SIMIGO_SETTLEMENT_SIGNING_KEY"
TRUST_ANCHOR_ENV = "SIMIGO_SETTLEMENT_TRUST_ANCHOR"
RUN_ID_ENV = "SIMIGO_SETTLEMENT_RUN_ID"
EXECUTION_ID_ENV = "SIMIGO_SETTLEMENT_EXECUTION_ID"
BUILD_SHA256_ENV = "SIMIGO_SETTLEMENT_BUILD_SHA256"

REQUIRED_PROVENANCE_FIELDS = (
    "schema_id",
    "producer",
    "task",
    "source",
    "dependencies",
    "result_value_sha256",
    "validity",
    "event",
)


class ProvenanceError(ValueError):
    """A fail-closed provenance error with a stable machine-readable code."""

    def __init__(self, code: str, detail: str = ""):
        self.code = code
        self.detail = detail
        super().__init__(code if not detail else "%s: %s" % (code, detail))


def canonical(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def _b64encode(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def _b64decode(value: Any, field: str) -> bytes:
    if not isinstance(value, str) or not value:
        raise ProvenanceError("SIGNATURE_MALFORMED", "%s is empty" % field)
    try:
        return base64.b64decode(value.encode("ascii"), validate=True)
    except Exception as error:  # noqa: BLE001 - malformed input is a refusal
        raise ProvenanceError("SIGNATURE_MALFORMED", "%s is not base64" % field) from error


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise ProvenanceError("PROVENANCE_MALFORMED", "%s is not a nonempty string" % field)
    return value


def _require_dict(value: Any, field: str) -> dict:
    if not isinstance(value, dict):
        raise ProvenanceError("PROVENANCE_MALFORMED", "%s is not an object" % field)
    return value


class SigningKey:
    def __init__(self, key_id: str, private_key: Any):
        self.key_id = _require_string(key_id, "key_id")
        self._private_key = private_key

    @classmethod
    def load(cls, path: str | os.PathLike[str]) -> "SigningKey":
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
        if raw.get("schema_id") != SIGNING_KEY_SCHEMA_ID:
            raise ProvenanceError("SIGNING_KEY_SCHEMA_INVALID")
        if raw.get("algorithm") != SIGNATURE_ALGORITHM:
            raise ProvenanceError("SIGNING_KEY_ALGORITHM_UNSUPPORTED")
        key_bytes = _b64decode(raw.get("private_key_base64"), "private_key_base64")
        if len(key_bytes) != 32:
            raise ProvenanceError("SIGNING_KEY_LENGTH_INVALID")
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        except ImportError as error:  # pragma: no cover - environment guard
            raise ProvenanceError("SIGNING_DEPENDENCY_MISSING", "cryptography") from error
        return cls(raw["key_id"], Ed25519PrivateKey.from_private_bytes(key_bytes))

    def sign(self, payload: bytes) -> bytes:
        return self._private_key.sign(payload)

    @property
    def public_key_base64(self) -> str:
        from cryptography.hazmat.primitives import serialization

        raw = self._private_key.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
        return _b64encode(raw)


class TrustAnchor:
    def __init__(self, key_id: str, public_key: Any):
        self.key_id = _require_string(key_id, "key_id")
        self._public_key = public_key

    @classmethod
    def load(cls, path: str | os.PathLike[str]) -> "TrustAnchor":
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
        if raw.get("schema_id") != TRUST_ANCHOR_SCHEMA_ID:
            raise ProvenanceError("TRUST_ANCHOR_SCHEMA_INVALID")
        if raw.get("algorithm") != SIGNATURE_ALGORITHM:
            raise ProvenanceError("TRUST_ANCHOR_ALGORITHM_UNSUPPORTED")
        key_bytes = _b64decode(raw.get("public_key_base64"), "public_key_base64")
        if len(key_bytes) != 32:
            raise ProvenanceError("TRUST_ANCHOR_LENGTH_INVALID")
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        except ImportError as error:  # pragma: no cover - environment guard
            raise ProvenanceError("SIGNING_DEPENDENCY_MISSING", "cryptography") from error
        return cls(raw["key_id"], Ed25519PublicKey.from_public_bytes(key_bytes))

    def verify(self, payload: bytes, signature: bytes) -> bool:
        try:
            self._public_key.verify(signature, payload)
            return True
        except Exception:  # noqa: BLE001 - any verification failure is a refusal
            return False


def load_policy(
    policy: Optional[str] = None,
    signing_key_path: Optional[str] = None,
    trust_anchor_path: Optional[str] = None,
) -> tuple[str, Optional[SigningKey], Optional[TrustAnchor]]:
    """Return (policy, signer, anchor).

    ``required`` is the producer setting: it refuses to start without both a
    signing key and a trust anchor.  ``verify`` is the consumer setting: it
    loads ONLY the anchor, so a process that admits settled results never holds
    the private key.  ``off`` is reserved for isolated library tests; the
    production bridge selects ``required`` or ``verify`` explicitly and never
    falls back on a missing key.
    """
    selected = (policy or os.environ.get(POLICY_ENV) or "off").strip().lower()
    if selected not in {"required", "verify", "off"}:
        raise ProvenanceError("PROVENANCE_POLICY_INVALID", selected)
    if selected == "off":
        return selected, None, None
    anchor_path = trust_anchor_path or os.environ.get(TRUST_ANCHOR_ENV)
    if not anchor_path:
        raise ProvenanceError("TRUST_ANCHOR_MISSING", TRUST_ANCHOR_ENV)
    anchor = TrustAnchor.load(anchor_path)
    if selected == "verify":
        return selected, None, anchor
    key_path = signing_key_path or os.environ.get(SIGNING_KEY_ENV)
    if not key_path:
        raise ProvenanceError("SIGNING_KEY_MISSING", SIGNING_KEY_ENV)
    signer = SigningKey.load(key_path)
    if signer.key_id != anchor.key_id:
        raise ProvenanceError(
            "KEY_ID_MISMATCH", "%s != %s" % (signer.key_id, anchor.key_id)
        )
    return selected, signer, anchor


def validate_provenance_shape(provenance: Any) -> dict:
    value = _require_dict(provenance, "provenance")
    if value.get("schema_id") != PROVENANCE_SCHEMA_ID:
        raise ProvenanceError("PROVENANCE_SCHEMA_INVALID")
    for field in REQUIRED_PROVENANCE_FIELDS:
        if field not in value:
            raise ProvenanceError("PROVENANCE_MISSING_FIELD", field)
    producer = _require_dict(value["producer"], "producer")
    _require_string(producer.get("kind"), "producer.kind")
    _require_string(producer.get("run_id"), "producer.run_id")
    _require_string(producer.get("execution_id"), "producer.execution_id")
    _require_string(producer.get("process_id"), "producer.process_id")
    _require_string(producer.get("build_sha256"), "producer.build_sha256")
    task = _require_dict(value["task"], "task")
    for field in ("item_id", "item_object_id", "payload_sha256"):
        _require_string(task.get(field), "task.%s" % field)
    source = _require_dict(value["source"], "source")
    for field in ("object_id", "payload_sha256", "version"):
        _require_string(source.get(field), "source.%s" % field)
    dependencies = _require_dict(value["dependencies"], "dependencies")
    for key, item in dependencies.items():
        _require_string(key, "dependencies.key")
        dependency = _require_dict(item, "dependencies.%s" % key)
        _require_string(dependency.get("object_id"), "dependencies.%s.object_id" % key)
        _require_string(
            dependency.get("result_value_sha256"),
            "dependencies.%s.result_value_sha256" % key,
        )
    _require_string(value["result_value_sha256"], "result_value_sha256")
    validity = _require_dict(value["validity"], "validity")
    _require_string(validity.get("evaluated_at_utc"), "validity.evaluated_at_utc")
    if validity.get("valid_until_utc") is not None:
        _require_string(validity.get("valid_until_utc"), "validity.valid_until_utc")
    if validity.get("validity_policy_sha256") is not None:
        _require_string(
            validity.get("validity_policy_sha256"), "validity.validity_policy_sha256"
        )
    event = _require_dict(value["event"], "event")
    _require_string(event.get("settlement_event_id"), "event.settlement_event_id")
    if not isinstance(event.get("sequence"), int) or event["sequence"] < 1:
        raise ProvenanceError("PROVENANCE_MALFORMED", "event.sequence is not a positive integer")
    previous = event.get("previous_settlement_object_id")
    if previous is not None:
        _require_string(previous, "event.previous_settlement_object_id")
    model = value.get("model")
    if model is not None:
        model = _require_dict(model, "model")
        _require_string(model.get("snapshot_revision"), "model.snapshot_revision")
        _require_string(
            model.get("weights_manifest_sha256"), "model.weights_manifest_sha256"
        )
    output = value.get("output")
    if output is not None:
        output = _require_dict(output, "output")
        _require_string(
            output.get("generated_token_ids_sha256"),
            "output.generated_token_ids_sha256",
        )
        if not isinstance(output.get("generated_token_count"), int):
            raise ProvenanceError(
                "PROVENANCE_MALFORMED", "output.generated_token_count is not an integer"
            )
    return value


def attach_event(
    provenance: Mapping[str, Any],
    *,
    item_id: str,
    history: list,
    result_value_sha256: str,
    evaluated_at_utc: str,
) -> dict:
    value = dict(provenance)
    sequence = len(history) + 1
    previous = history[-1].content_address if history else None
    event_id = digest({
        "item_id": item_id,
        "sequence": sequence,
        "previous_settlement_object_id": previous,
        "result_value_sha256": result_value_sha256,
        "evaluated_at_utc": evaluated_at_utc,
    })
    value["event"] = {
        "settlement_event_id": event_id,
        "sequence": sequence,
        "previous_settlement_object_id": previous,
    }
    return validate_provenance_shape(value)


def build_declaration(
    advancement_id: str,
    item_id: str,
    result: dict,
    basis: dict,
    provenance: Mapping[str, Any],
) -> dict:
    return {
        "schema_id": "EINFO-SETTLEMENT-V1",
        "state": "SETTLED",
        "settlement_contract": "EINFO-SETTLEMENT-CONTRACT-V1",
        "advancement_id": advancement_id,
        "item_id": item_id,
        "result": result,
        "basis": basis,
        "provenance": validate_provenance_shape(provenance),
    }


def sign_declaration(
    declaration: Mapping[str, Any],
    signer: SigningKey,
) -> tuple[dict, str, str]:
    """Sign one fully-built settlement declaration.

    Returns ``(signature_envelope, settlement_object_id, signature_object_id)``.
    The settlement object id is the content address of the canonical
    declaration, so the signature binds the exact object the consumer reads.
    """
    declaration_bytes = canonical(declaration)
    settlement_object_id = _sha256_text(declaration_bytes.decode("utf-8"))
    payload = {
        "schema_id": PROVENANCE_SCHEMA_ID,
        "settlement_object_id": settlement_object_id,
        "settlement_schema_id": declaration["schema_id"],
        "settlement_contract": declaration["settlement_contract"],
        "item_id": declaration["item_id"],
        "advancement_id": declaration["advancement_id"],
        "provenance": declaration["provenance"],
        "algorithm": SIGNATURE_ALGORITHM,
        "key_id": signer.key_id,
    }
    payload_bytes = canonical(payload)
    signature = signer.sign(payload_bytes)
    envelope = {
        "schema_id": SIGNATURE_SCHEMA_ID,
        "settlement_object_id": settlement_object_id,
        "item_id": declaration["item_id"],
        "algorithm": SIGNATURE_ALGORITHM,
        "key_id": signer.key_id,
        "payload": payload,
        "payload_canonical_base64": _b64encode(payload_bytes),
        "signature_base64": _b64encode(signature),
    }
    return envelope, settlement_object_id, _sha256_text(canonical(envelope).decode("utf-8"))


def verify_signature(
    envelope: Any,
    anchor: TrustAnchor,
    *,
    expected_settlement_object_id: str,
    expected_item_id: str,
) -> dict:
    """Verify the detached signature and return its signed payload."""
    value = _require_dict(envelope, "signature_envelope")
    if value.get("schema_id") != SIGNATURE_SCHEMA_ID:
        raise ProvenanceError("SIGNATURE_SCHEMA_INVALID")
    if value.get("algorithm") != SIGNATURE_ALGORITHM:
        raise ProvenanceError("SIGNATURE_ALGORITHM_UNSUPPORTED")
    if value.get("key_id") != anchor.key_id:
        raise ProvenanceError("SIGNATURE_KEY_NOT_TRUSTED")
    if value.get("settlement_object_id") != expected_settlement_object_id:
        raise ProvenanceError("SIGNATURE_OBJECT_ID_MISMATCH")
    if value.get("item_id") != expected_item_id:
        raise ProvenanceError("SIGNATURE_ITEM_MISMATCH")
    payload = _require_dict(value.get("payload"), "payload")
    payload_bytes = _b64decode(
        value.get("payload_canonical_base64"), "payload_canonical_base64"
    )
    if canonical(payload) != payload_bytes:
        raise ProvenanceError("SIGNATURE_PAYLOAD_NOT_CANONICAL")
    signature = _b64decode(value.get("signature_base64"), "signature_base64")
    if not anchor.verify(payload_bytes, signature):
        raise ProvenanceError("SIGNATURE_VERIFICATION_FAILED")
    if payload.get("schema_id") != PROVENANCE_SCHEMA_ID:
        raise ProvenanceError("SIGNATURE_PAYLOAD_SCHEMA_INVALID")
    if payload.get("settlement_object_id") != expected_settlement_object_id:
        raise ProvenanceError("SIGNATURE_PAYLOAD_OBJECT_ID_MISMATCH")
    if payload.get("item_id") != expected_item_id:
        raise ProvenanceError("SIGNATURE_PAYLOAD_ITEM_MISMATCH")
    return payload


def signature_descriptor(envelope: Mapping[str, Any]) -> dict:
    """Return the consumer-facing signature record (audit + Swift verify).

    Two identities are reported separately and must not be conflated:
    ``signature_object_id`` is the detached signature object itself, while
    ``settlement_object_id`` is the settlement the signature covers.  A
    caller that needs the settlement will find it in the payload as well;
    keeping both here lets consumers report which object was verified
    without having to guess from field order.
    """
    return {
        "schema_id": envelope.get("schema_id"),
        "signature_object_id": envelope.get("_object_id"),
        "settlement_object_id": envelope.get("settlement_object_id"),
        "item_id": envelope.get("item_id"),
        "algorithm": envelope.get("algorithm"),
        "key_id": envelope.get("key_id"),
        "payload": envelope.get("payload"),
        "payload_canonical_base64": envelope.get("payload_canonical_base64"),
        "signature_base64": envelope.get("signature_base64"),
    }
