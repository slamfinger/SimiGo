"""ES-driven Information Space loop backed by the existing D002 carrier.

This module reuses `database-carrier-replication/implementation/db_is.py`
without modification. All durable state is stored as canonical JSON objects in
the carrier's append-only object store; current items and settlements are
resolved through the carrier's index and dependency ledgers.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Optional

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "database-carrier-replication" / "implementation"))
from db_is import DatabaseBackedIS, MissingLogicalEntry  # noqa: E402

import settlement_provenance as settlement_provenance  # noqa: E402


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def parse_utc(value: str) -> datetime:
    if not isinstance(value, str):
        raise ValueError("UTC timestamp must use the YYYY-MM-DDTHH:MM:SSZ form")
    try:
        parsed = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as error:
        raise ValueError("UTC timestamp must use the YYYY-MM-DDTHH:MM:SSZ form") from error
    return parsed.replace(tzinfo=timezone.utc)


class _DemandNotAdvanced(Exception):
    def __init__(self, result: dict):
        self.result = result


class ConcurrentStateTransition(Exception):
    """The latest lawful state changed while a failed attempt was rolling back."""


RUNTIME_APPLICATION_STATUSES = {"PENDING_SWIFT", "APPLIED_SWIFT"}

# One settlement contract for every writer. External information and internal
# computed results must arrive in the same envelope, otherwise the reuse
# predicate can only ever match the dialect that wrote the record.
SETTLEMENT_CONTRACT = "EINFO-SETTLEMENT-CONTRACT-V1"
CARRIER_LOOP_CONTRACT_VERSION = "2"

# Two digest domains that never mix: `source_payload_sha256` binds the input a
# settlement was computed from, `result_value_sha256` binds the value it
# produced. Neither domain may be compared against the other.
SETTLEMENT_DIGEST_FIELDS = ("source_payload_sha256", "result_value_sha256")
SETTLEMENT_RESULT_FIELDS = (
    "value",
    "source_payload_sha256",
    "result_value_sha256",
    "source_version",
    "dependency_object_ids",
    "evaluated_at_utc",
    "valid_until_utc",
    "validity_policy",
)
SETTLEMENT_BASIS_FIELDS = (
    "source_payload_sha256",
    "result_value_sha256",
    "source_version",
    "dependency_object_ids",
    "evaluated_at_utc",
    "valid_until_utc",
    "validity_policy",
)


def _is_sha256_hex(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def _is_object_id_map(value: Any) -> bool:
    return isinstance(value, dict) and all(
        isinstance(key, str) and _is_sha256_hex(item) for key, item in value.items()
    )


class SettlementContractViolation(ValueError):
    """A settlement payload does not satisfy the single settlement contract."""

    def __init__(self, missing: list[str], mismatched: list[str], detail: str = ""):
        self.missing = list(missing)
        self.mismatched = list(mismatched)
        message = "settlement contract violation"
        if self.missing:
            message += "; missing=%s" % ",".join(sorted(set(self.missing)))
        if self.mismatched:
            message += "; mismatched=%s" % ",".join(sorted(set(self.mismatched)))
        if detail:
            message += "; " + detail
        super().__init__(message)


def validate_settlement_payload(result: Any, basis: Any) -> None:
    """Reject a settlement that no reader could reuse under the contract."""
    if not isinstance(result, dict):
        raise SettlementContractViolation(
            ["result"], [], "result must be a JSON object"
        )
    if not isinstance(basis, dict):
        raise SettlementContractViolation(["basis"], [], "basis must be a JSON object")
    missing = ["result.%s" % field for field in SETTLEMENT_RESULT_FIELDS
               if field not in result]
    missing += ["basis.%s" % field for field in SETTLEMENT_BASIS_FIELDS
                if field not in basis]
    if missing:
        raise SettlementContractViolation(missing, [])

    mismatched: list[str] = []
    for scope, payload in (("result", result), ("basis", basis)):
        for field in SETTLEMENT_DIGEST_FIELDS:
            if not _is_sha256_hex(payload[field]):
                mismatched.append("%s.%s" % (scope, field))
        if not isinstance(payload["source_version"], str) or not payload["source_version"]:
            mismatched.append("%s.source_version" % scope)
        if not _is_object_id_map(payload["dependency_object_ids"]):
            mismatched.append("%s.dependency_object_ids" % scope)
        try:
            parse_utc(payload["evaluated_at_utc"])
        except ValueError:
            mismatched.append("%s.evaluated_at_utc" % scope)
        if payload["valid_until_utc"] is not None:
            try:
                parse_utc(payload["valid_until_utc"])
            except ValueError:
                mismatched.append("%s.valid_until_utc" % scope)
        try:
            validity_policy_identity(payload["validity_policy"])
        except ValueError:
            mismatched.append("%s.validity_policy" % scope)

    # Each digest domain is validated against its own subject: the recorded
    # result digest must be the digest of the recorded value, and both scopes
    # must agree on each domain independently.
    try:
        recorded_value_sha256 = digest(result["value"])
    except (TypeError, ValueError):
        recorded_value_sha256 = None
        mismatched.append("result.value_not_canonical_json")
    if recorded_value_sha256 is not None:
        for scope, payload in (("result", result), ("basis", basis)):
            if payload["result_value_sha256"] != recorded_value_sha256:
                mismatched.append("%s.result_value_sha256!=digest(result.value)" % scope)
    for field in SETTLEMENT_DIGEST_FIELDS:
        if result[field] != basis[field]:
            mismatched.append("result.%s!=basis.%s" % (field, field))
    if result["source_version"] != basis["source_version"]:
        mismatched.append("result.source_version!=basis.source_version")
    if result["dependency_object_ids"] != basis["dependency_object_ids"]:
        mismatched.append("result.dependency_object_ids!=basis.dependency_object_ids")
    if result["evaluated_at_utc"] != basis["evaluated_at_utc"]:
        mismatched.append("result.evaluated_at_utc!=basis.evaluated_at_utc")
    if result["valid_until_utc"] != basis["valid_until_utc"]:
        mismatched.append("result.valid_until_utc!=basis.valid_until_utc")
    if result["validity_policy"] != basis["validity_policy"]:
        mismatched.append("result.validity_policy!=basis.validity_policy")

    try:
        if (result["valid_until_utc"] is not None
                and parse_utc(result["evaluated_at_utc"])
                > parse_utc(result["valid_until_utc"])):
            mismatched.append("valid_until_utc<=evaluated_at_utc")
    except ValueError:
        pass

    try:
        canonical(result)
        canonical(basis)
    except (TypeError, ValueError):
        mismatched.append("payload_not_canonical_json")

    if mismatched:
        raise SettlementContractViolation([], mismatched)


def validity_policy_identity(policy: Any) -> dict:
    """Validate and return a canonical validity-policy identity."""
    if not isinstance(policy, dict):
        raise ValueError("validity policy identity is missing")
    if not isinstance(policy.get("policy_version"), str) or not policy["policy_version"]:
        raise ValueError("validity policy_version is missing")
    if not isinstance(policy.get("policy_source"), str) or not policy["policy_source"]:
        raise ValueError("validity policy_source is missing")
    body = {key: value for key, value in policy.items() if key != "policy_sha256"}
    expected = digest(body)
    if policy.get("policy_sha256") != expected:
        raise ValueError("validity policy_sha256 mismatch")
    return policy


class CarrierInformationLoop:
    """Minimal ES/IS continuation loop over DatabaseBackedIS.

    ``provenance_policy='required'`` is the production producer setting: every
    new settlement is signed, and every reuse must verify a detached Ed25519
    signature against a trust anchor outside the database.  ``verify`` is the
    consumer setting: it verifies signatures but never loads a private key.
    ``off`` exists only for isolated library tests and is never selected
    implicitly by the bridge.
    """

    def __init__(
        self,
        carrier: DatabaseBackedIS,
        *,
        provenance_policy: str = "off",
        signer: Optional[settlement_provenance.SigningKey] = None,
        trust_anchor: Optional[settlement_provenance.TrustAnchor] = None,
        run_id: Optional[str] = None,
        execution_id: Optional[str] = None,
        build_sha256: Optional[str] = None,
    ):
        self.carrier = carrier
        self.provenance_policy = provenance_policy
        self.signer = signer
        self.trust_anchor = trust_anchor
        self.run_id = run_id or os.environ.get(settlement_provenance.RUN_ID_ENV) or "local"
        self.execution_id = (
            execution_id
            or os.environ.get(settlement_provenance.EXECUTION_ID_ENV)
            or "local"
        )
        self.build_sha256 = (
            build_sha256
            or os.environ.get(settlement_provenance.BUILD_SHA256_ENV)
            or hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        )
        if provenance_policy == "required" and (signer is None or trust_anchor is None):
            raise settlement_provenance.ProvenanceError(
                "PROVENANCE_CONFIGURATION_MISSING",
                "required policy needs a signing key and trust anchor",
            )
        if provenance_policy == "verify" and trust_anchor is None:
            raise settlement_provenance.ProvenanceError(
                "PROVENANCE_CONFIGURATION_MISSING",
                "verify policy needs a trust anchor",
            )

    @classmethod
    def _configured(cls, carrier: DatabaseBackedIS, provenance_policy: Optional[str]):
        policy, signer, anchor = settlement_provenance.load_policy(provenance_policy)
        return cls(
            carrier,
            provenance_policy=policy,
            signer=signer,
            trust_anchor=anchor,
        )

    @classmethod
    def create(
        cls, database_path: str, *, provenance_policy: Optional[str] = None
    ) -> "CarrierInformationLoop":
        path = Path(database_path)
        if path.exists() or path.is_symlink():
            raise FileExistsError(path)
        carrier = DatabaseBackedIS.init_empty(database_path)
        return cls._configured(carrier, provenance_policy)

    @classmethod
    def open(
        cls, database_path: str, *, provenance_policy: Optional[str] = None
    ) -> "CarrierInformationLoop":
        path = Path(database_path)
        if not path.is_file() or path.is_symlink():
            raise FileNotFoundError(path)
        carrier = DatabaseBackedIS(path)
        carrier.validate_schema()
        return cls._configured(carrier, provenance_policy)

    def commit(self) -> None:
        self.carrier.connection.commit()

    def close(self) -> None:
        self.carrier.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()

    def _current_index_record(self, identity: str) -> Optional[dict]:
        row = self.carrier.connection.execute(
            "SELECT append_order,srs_identity,record_object "
            "FROM is_index_entries WHERE srs_identity=? "
            "ORDER BY append_order DESC LIMIT 1",
            (identity,),
        ).fetchone()
        if row is None:
            return None
        value = json.loads(self.carrier.get_object(row["record_object"]))
        return {"value": value, "object_id": row["record_object"]}

    def _current_index_object(self, identity: str) -> Optional[dict]:
        record = self._current_index_record(identity)
        return None if record is None else record["value"]

    def _current_dependency_object(self, dependency_id: str) -> Optional[dict]:
        try:
            record = self.carrier.resolve_current_dependency(dependency_id)
        except MissingLogicalEntry:
            return None
        value = json.loads(self.carrier.get_object(record.content_address))
        value["_object_id"] = record.content_address
        return value

    def _put_index_object(self, identity: str, value: dict) -> str:
        with self.carrier.atomic_write_group():
            content = canonical(value)
            object_id = self.carrier.write_object(content)
            self.carrier.append_index_entry({
                "srs_identity": identity,
                "record_object": object_id,
            })
            return object_id

    def current_demand_digest(self, demand_id: str) -> str:
        demand = self.current_demand(demand_id)
        if demand is None:
            raise MissingLogicalEntry(f"demand:{demand_id}")
        demand.pop("_identity", None)
        demand.pop("_object_id", None)
        return digest(demand)

    def define_demand(
        self,
        demand_id: str,
        continuation_point: str,
        pending_obligations: list[str],
        continuation_conditions: list[str],
        required_item_ids: list[str],
    ) -> dict:
        if len(set(required_item_ids)) != len(required_item_ids):
            raise ValueError("required item ids must be unique")
        value = {
            "schema_id": "EINFO-ES-DEMAND-V1",
            "demand_id": demand_id,
            "continuation_point": continuation_point,
            "pending_obligations": pending_obligations,
            "continuation_conditions": continuation_conditions,
            "required_item_ids": required_item_ids,
        }
        object_id = self._put_index_object(f"demand:{demand_id}", value)
        return {"demand_id": demand_id, "object_id": object_id, **value}

    def put_source(
        self,
        demand_id: str,
        item_id: str,
        source_kind: str,
        source_version: str,
        source_payload: dict,
        dependencies: Optional[list[str]] = None,
        valid_until_utc: Optional[str] = None,
        validity_policy: Optional[dict] = None,
    ) -> dict:
        if valid_until_utc is not None:
            parse_utc(valid_until_utc)
        dependencies = list(dependencies or [])
        if len(set(dependencies)) != len(dependencies):
            raise ValueError("dependency ids must be unique")
        if item_id in dependencies:
            raise ValueError("item cannot depend on itself")
        # Dependencies must already have current source objects. This keeps the
        # reference test topologically ordered without adding implicit discovery.
        current_dependencies: dict[str, dict] = {}
        for dependency_id in dependencies:
            current = self._current_index_object(f"item:{dependency_id}")
            if current is None:
                raise MissingLogicalEntry(f"item:{dependency_id}")
            current_dependencies[dependency_id] = current
        value = {
            "schema_id": "EINFO-INFORMATION-ITEM-V1",
            "demand_id": demand_id,
            "item_id": item_id,
            "source_kind": source_kind,
            "source_version": source_version,
            "source_payload": source_payload,
            "dependencies": dependencies,
            "valid_until_utc": valid_until_utc,
            "validity_policy": validity_policy,
        }
        content = canonical(value)
        dependency_id = f"dependency:{item_id}"
        history = self.carrier.get_dependency_history(dependency_id)
        revision = len(history) + 1
        with self.carrier.atomic_write_group():
            object_id, dependency_order = self.carrier.atomic_dependency_materialization(
                content,
                {
                    "dependency_id": dependency_id,
                    "content_address": "",  # filled by atomic helper
                    "revision": revision,
                    "reason": "source version",
                },
            )
            self.carrier.append_index_entry({
                "srs_identity": f"item:{item_id}",
                "record_object": object_id,
            })
        return {
            "item_id": item_id,
            "object_id": object_id,
            "revision": revision,
            "dependency_order": dependency_order,
            "current_dependencies": current_dependencies,
        }

    def update_source(
        self,
        item_id: str,
        source_version: str,
        source_payload: dict,
        reason: str,
        valid_until_utc: Optional[str] = None,
        validity_policy: Optional[dict] = None,
    ) -> dict:
        old = self._current_index_object(f"item:{item_id}")
        if old is None:
            raise MissingLogicalEntry(f"item:{item_id}")
        if valid_until_utc is not None:
            parse_utc(valid_until_utc)
        value = {
            "schema_id": "EINFO-INFORMATION-ITEM-V1",
            "demand_id": old["demand_id"],
            "item_id": item_id,
            "source_kind": old["source_kind"],
            "source_version": source_version,
            "source_payload": source_payload,
            "dependencies": old["dependencies"],
            "valid_until_utc": (
                old.get("valid_until_utc") if valid_until_utc is None else valid_until_utc
            ),
            "validity_policy": (
                old.get("validity_policy") if validity_policy is None else validity_policy
            ),
        }
        content = canonical(value)
        dependency_id = f"dependency:{item_id}"
        revision = len(self.carrier.get_dependency_history(dependency_id)) + 1
        with self.carrier.atomic_write_group():
            object_id, dependency_order = self.carrier.atomic_dependency_materialization(
                content,
                {
                    "dependency_id": dependency_id,
                    "content_address": "",
                    "revision": revision,
                    "reason": reason,
                },
            )
            self.carrier.append_index_entry({
                "srs_identity": f"item:{item_id}",
                "record_object": object_id,
            })
        return {
            "item_id": item_id,
            "object_id": object_id,
            "revision": revision,
            "dependency_order": dependency_order,
        }

    def settlement_provenance_for(
        self,
        item_id: str,
        result: dict,
        dependency_object_ids: dict,
        dependency_values: dict,
        override: Optional[dict] = None,
    ) -> dict:
        """Build the provenance a trusted settlement path is about to sign.

        Public wrapper for settlement paths that settle outside
        ``execute_demand`` (for example task registration). It never signs: the
        caller must pass the result to ``settle``, which signs inside the same
        atomic group that writes the settlement object.
        """
        item = self.current_item(item_id)
        item_record = self.current_item_record(item_id)
        if item is None or item_record is None:
            raise settlement_provenance.ProvenanceError(
                "TASK_ITEM_RECORD_MISSING", item_id
            )
        return self._provenance_for_settlement(
            item, item_record, item_id, result, dependency_object_ids,
            dependency_values, override,
        )

    def _provenance_for_settlement(
        self,
        item: dict,
        item_record: dict,
        item_id: str,
        result: dict,
        dependency_object_ids: dict,
        dependency_values: dict,
        override: Optional[dict] = None,
    ) -> dict:
        producer = {
            "kind": "carrier_calculator",
            "run_id": self.run_id,
            "execution_id": self.execution_id,
            "process_id": str(os.getpid()),
            "build_sha256": self.build_sha256,
        }
        model = None
        output = None
        if override is not None:
            unexpected = set(override) - {"producer", "model", "output"}
            if unexpected:
                raise settlement_provenance.ProvenanceError(
                    "PROVENANCE_OVERRIDE_INVALID", sorted(unexpected)
                )
            if isinstance(override.get("producer"), dict):
                producer.update(override["producer"])
            model = override.get("model")
            output = override.get("output")
            if producer.get("kind") == "model_task" and (model is None or output is None):
                raise settlement_provenance.ProvenanceError(
                    "PROVENANCE_MODEL_INCOMPLETE", item_id
                )
        dependencies = {}
        for dependency_id in item.get("dependencies") or []:
            object_id = dependency_object_ids.get(dependency_id)
            value = dependency_values.get(dependency_id)
            if not object_id or value is None:
                raise settlement_provenance.ProvenanceError(
                    "PROVENANCE_DEPENDENCY_MISSING", dependency_id
                )
            dependencies[dependency_id] = {
                "object_id": object_id,
                "result_value_sha256": digest(value),
            }
        policy = item.get("validity_policy")
        if "value" not in result or "evaluated_at_utc" not in result:
            raise settlement_provenance.ProvenanceError(
                "PROVENANCE_RESULT_INCOMPLETE", item_id
            )
        return {
            "schema_id": settlement_provenance.PROVENANCE_SCHEMA_ID,
            "producer": producer,
            "task": {
                "item_id": item_id,
                "item_object_id": item_record["object_id"],
                "payload_sha256": digest(item),
            },
            "source": {
                "object_id": item_record["object_id"],
                "payload_sha256": digest(item["source_payload"]),
                "version": item["source_version"],
            },
            "dependencies": dependencies,
            "result_value_sha256": digest(result["value"]),
            "validity": {
                "evaluated_at_utc": result["evaluated_at_utc"],
                "valid_until_utc": result["valid_until_utc"],
                "validity_policy_sha256": digest(policy) if policy is not None else None,
            },
            "model": model,
            "output": output,
        }

    def settle(
        self,
        advancement_id: str,
        item_id: str,
        result: dict,
        basis: dict,
        provenance: Optional[dict] = None,
    ) -> dict:
        # Reject a contract violation before the carrier is touched: a
        # malformed settlement must never reach the append-only ledger.
        validate_settlement_payload(result, basis)
        dependency_id = f"settlement:{item_id}"
        history = self.carrier.get_dependency_history(dependency_id)
        revision = len(history) + 1
        if provenance is None or self.provenance_policy == "off":
            if self.provenance_policy != "off":
                raise settlement_provenance.ProvenanceError(
                    "PROVENANCE_REQUIRED", "settlement %s has no provenance" % item_id
                )
            value = {
                "schema_id": "EINFO-SETTLEMENT-V1",
                "state": "SETTLED",
                "settlement_contract": SETTLEMENT_CONTRACT,
                "advancement_id": advancement_id,
                "item_id": item_id,
                "result": result,
                "basis": basis,
            }
            signature_envelope = None
        else:
            provenance = settlement_provenance.attach_event(
                provenance,
                item_id=item_id,
                history=history,
                result_value_sha256=result["result_value_sha256"],
                evaluated_at_utc=result["evaluated_at_utc"],
            )
            value = settlement_provenance.build_declaration(
                advancement_id, item_id, result, basis, provenance
            )
            signature_envelope = None
            if self.provenance_policy == "required":
                signature_envelope, declared_id, _ = settlement_provenance.sign_declaration(
                    value, self.signer
                )
                content = canonical(value)
                actual_id = hashlib.sha256(content).hexdigest()
                if actual_id != declared_id:
                    raise settlement_provenance.ProvenanceError(
                        "DECLARATION_ID_MISMATCH", "%s != %s" % (actual_id, declared_id)
                    )
        content = canonical(value)
        object_id = hashlib.sha256(content).hexdigest()
        signature_object_id = None
        with self.carrier.atomic_write_group():
            written_id, dependency_order = self.carrier.atomic_dependency_materialization(
                content,
                {
                    "dependency_id": dependency_id,
                    "content_address": "",
                    "revision": revision,
                    "reason": "settled result",
                },
            )
            if written_id != object_id:
                raise settlement_provenance.ProvenanceError(
                    "SETTLEMENT_OBJECT_ID_MISMATCH",
                    "%s != %s" % (written_id, object_id),
                )
            self.carrier.append_index_entry({
                "srs_identity": f"settlement:{item_id}",
                "record_object": object_id,
            })
            if signature_envelope is not None:
                signature_content = canonical(signature_envelope)
                signature_object_id = self.carrier.write_object(signature_content)
                self.carrier.append_index_entry({
                    "srs_identity": f"settlement-signature:{item_id}",
                    "record_object": signature_object_id,
                })
        return {
            "item_id": item_id,
            "object_id": object_id,
            "signature_object_id": signature_object_id,
            "dependency_order": dependency_order,
        }

    def invalidate_settlement(
        self,
        target_item_id: str,
        reason: str,
        include_dependents: bool = True,
        strict: bool = True,
    ) -> dict:
        """Invalidate `target_item_id` and everything that truly depends on it.

        `strict` governs exactly one thing: whether an unknown target is an
        error. With `strict=False` the pre-W4 computation and return shape are
        reproduced as-is (an unknown target is echoed back as invalidated with
        zero records written), which is what historical callers were written
        against. New callers should keep the default, which reports the same
        situation as the carrier's own `MissingLogicalEntry` instead of a
        successful-looking no-op.
        """
        with self.carrier.atomic_write_group():
            return self._invalidate_settlement_in_group(
                target_item_id, reason, include_dependents, strict
            )

    def _dependency_edges(self) -> dict[str, set[str]]:
        """Dependency graph per item, as the union of two declared sources.

        An item declares its dependencies in `dependencies`; the settlement it
        produced declares the same relation in `basis.dependency_object_ids`.
        A settlement written by an external writer can carry only the second,
        which would leave a real dependency invisible to a graph built from
        item objects alone. Union keeps the closure complete without inventing
        edges: both keys are item ids the carrier itself recorded.
        """
        edges: dict[str, set[str]] = {}
        for row in self.carrier.connection.execute(
            "SELECT append_order,srs_identity,record_object "
            "FROM is_index_entries WHERE srs_identity LIKE 'item:%' "
            "ORDER BY append_order ASC"
        ):
            item_id = row["srs_identity"][len("item:"):]
            value = json.loads(self.carrier.get_object(row["record_object"]))
            edges[item_id] = set(value.get("dependencies") or ())
        for item_id in edges:
            settlement = self.current_settlement(item_id)
            basis = settlement.get("basis") if isinstance(settlement, dict) else None
            declared = basis.get("dependency_object_ids") if isinstance(basis, dict) else None
            if isinstance(declared, dict):
                edges[item_id].update(declared)
        return edges

    def _invalidate_settlement_in_group(
        self,
        target_item_id: str,
        reason: str,
        include_dependents: bool = True,
        strict: bool = True,
    ) -> dict:
        """Append explicit invalidation records for an item and its dependents."""
        items = self._dependency_edges()
        if strict and target_item_id not in items:
            raise MissingLogicalEntry(
                "item:%s (unknown invalidation target)" % target_item_id
            )
        dependents: dict[str, list[str]] = {
            item_id: [] for item_id in items
        }
        for dependent_id, dependencies in items.items():
            for dependency_id in dependencies:
                dependents.setdefault(dependency_id, []).append(dependent_id)

        affected: list[str] = [target_item_id] if include_dependents else []
        stack = list(dependents.get(target_item_id, []))
        while stack:
            dependent_id = stack.pop()
            if dependent_id not in affected:
                affected.append(dependent_id)
                stack.extend(dependents.get(dependent_id, []))

        invalidated = []
        for affected_id in sorted(affected):
            settlement = self.current_settlement(affected_id)
            if settlement is None or settlement.get("state") == "INVALID":
                continue
            value = {
                "schema_id": "EINFO-SETTLEMENT-INVALID-V1",
                "item_id": affected_id,
                "state": "INVALID",
                "reason": reason,
                "invalidated_by": target_item_id if affected_id != target_item_id else None,
                "prior_result": settlement.get("result"),
            }
            content = canonical(value)
            dependency_id = f"settlement:{affected_id}"
            history = self.carrier.get_dependency_history(dependency_id)
            revision = len(history) + 1
            object_id, dependency_order = self.carrier.atomic_dependency_materialization(
                content,
                {
                    "dependency_id": dependency_id,
                    "content_address": "",
                    "revision": revision,
                    "reason": "explicit invalidation",
                },
            )
            self.carrier.append_index_entry({
                "srs_identity": f"settlement:{affected_id}",
                "record_object": object_id,
            })
            invalidated.append({
                "item_id": affected_id,
                "object_id": object_id,
                "dependency_order": dependency_order,
            })
        return {
            "invalidated_item_ids": sorted(affected),
            "invalidated_records": invalidated,
            "reason": reason,
        }

    def current_demand(self, demand_id: str) -> Optional[dict]:
        return self._current_index_object(f"demand:{demand_id}")

    def current_item(self, item_id: str) -> Optional[dict]:
        return self._current_index_object(f"item:{item_id}")

    def current_item_record(self, item_id: str) -> Optional[dict]:
        return self._current_index_record(f"item:{item_id}")

    def current_settlement(self, item_id: str) -> Optional[dict]:
        return self._current_dependency_object(f"settlement:{item_id}")

    def current_settlement_signature(self, item_id: str) -> Optional[dict]:
        record = self._current_index_record(f"settlement-signature:{item_id}")
        if record is None:
            return None
        value = record["value"]
        value["_object_id"] = record["object_id"]
        return value

    def _latest_index_object_with_identity(self, prefix: str) -> Optional[dict]:
        row = self.carrier.connection.execute(
            "SELECT append_order,srs_identity,record_object "
            "FROM is_index_entries WHERE srs_identity LIKE ? || '%'"
            " ORDER BY append_order DESC LIMIT 1",
            (prefix,),
        ).fetchone()
        if row is None:
            return None
        value = json.loads(self.carrier.get_object(row["record_object"]))
        value["_identity"] = row["srs_identity"]
        value["_object_id"] = row["record_object"]
        return value

    def record_execution_state(
        self,
        state_id: str,
        continuation_point: str,
        prior_state_id: Optional[str],
        demand_id: str,
        status: str,
        pending_obligations: list[str],
        next_continuation_point: str,
        result_digest: str,
        runtime_application_status: Optional[str] = None,
    ) -> dict:
        if runtime_application_status not in {None, *RUNTIME_APPLICATION_STATUSES}:
            raise ValueError("invalid runtime application status")
        with self.carrier.atomic_write_group():
            return self._record_execution_state_in_group(
                state_id,
                continuation_point,
                prior_state_id,
                demand_id,
                status,
                pending_obligations,
                next_continuation_point,
                result_digest,
                runtime_application_status,
            )

    def _record_execution_state_in_group(
        self,
        state_id: str,
        continuation_point: str,
        prior_state_id: Optional[str],
        demand_id: str,
        status: str,
        pending_obligations: list[str],
        next_continuation_point: str,
        result_digest: str,
        runtime_application_status: Optional[str] = None,
    ) -> dict:
        if status not in {"RESTORED", "ADVANCED", "BLOCKED"}:
            raise ValueError("invalid execution state")
        identity = f"execution_state:{continuation_point}:{state_id}"
        if self._current_index_object(identity) is not None:
            raise FileExistsError(identity)
        demand_digest = self.current_demand_digest(demand_id)
        value = {
            "schema_id": "EINFO-EXECUTION-STATE-V1",
            "state_id": state_id,
            "continuation_point": continuation_point,
            "prior_state_id": prior_state_id,
            "demand_id": demand_id,
            "demand_digest": demand_digest,
            "status": status,
            "pending_obligations": pending_obligations,
            "next_continuation_point": next_continuation_point,
            "result_digest": result_digest,
            "runtime_application_status": runtime_application_status,
        }
        object_id = self._put_index_object(identity, value)
        dependency_id = f"execution_state:{state_id}"
        revision = len(self.carrier.get_dependency_history(dependency_id)) + 1
        _, dependency_order = self.carrier.atomic_dependency_materialization(
            canonical(value),
            {
                "dependency_id": dependency_id,
                "content_address": "",
                "revision": revision,
                "reason": "execution state transition",
            },
        )
        return {
            "state_id": state_id,
            "object_id": object_id,
            "dependency_order": dependency_order,
        }

    def latest_execution_state(self, continuation_point: str) -> Optional[dict]:
        value = self._latest_index_object_with_identity(f"execution_state:{continuation_point}:")
        if value is not None:
            value.pop("_identity", None)
            value.pop("_object_id", None)
        return value

    def restore_continuation(self, continuation_point: str) -> dict:
        """Restore the latest lawful state and its ES-derived information demand."""
        state = self.latest_execution_state(continuation_point)
        if state is None:
            raise MissingLogicalEntry(f"execution state:{continuation_point}")
        if state["status"] == "BLOCKED":
            raise ValueError("blocked execution state cannot continue without repair")
        runtime_status = state.get("runtime_application_status")
        if runtime_status == "PENDING_SWIFT":
            raise ValueError(
                "pending runtime application requires confirmation: "
                f"{state['state_id']}"
            )
        if runtime_status != "APPLIED_SWIFT":
            raise ValueError(
                "execution state has no verifiable runtime-application completion"
            )
        demand = self.current_demand(state["demand_id"])
        if demand is None:
            raise MissingLogicalEntry(f"demand:{state['demand_id']}")
        if demand["continuation_point"] != continuation_point:
            raise ValueError("execution state and demand continuation points disagree")
        if state.get("demand_digest") != self.current_demand_digest(state["demand_id"]):
            raise ValueError("execution state demand contract digest mismatch")
        return {
            "state": state,
            "demand": demand,
            "required_item_ids": list(demand["required_item_ids"]),
        }

    def confirm_runtime_application(self, state_id: str) -> dict:
        """Append the completion evidence for the exact pending Swift intent."""
        with self.carrier.transaction():
            state = self._find_state_by_id(state_id)
            if state is None:
                raise ValueError(f"pending execution state not found: {state_id}")
            if state.get("status") != "ADVANCED" or state.get(
                "runtime_application_status"
            ) != "PENDING_SWIFT":
                raise ValueError(
                    f"execution state is not pending Swift application: {state_id}"
                )
            latest = self.latest_execution_state(state["continuation_point"])
            if latest is None or latest["state_id"] != state_id:
                raise ValueError(
                    "runtime confirmation is not the latest execution state"
                )
            confirmation = self.record_execution_state(
                f"{state_id}:runtime-applied",
                continuation_point=state["continuation_point"],
                prior_state_id=state_id,
                demand_id=state["demand_id"],
                status="ADVANCED",
                pending_obligations=[],
                next_continuation_point="runtime-application-complete",
                result_digest=state["result_digest"],
                runtime_application_status="APPLIED_SWIFT",
            )
        return {"confirmation": confirmation, "confirmed_state_id": state_id}

    def _find_state_by_id(self, state_id: str) -> Optional[dict]:
        row = self.carrier.connection.execute(
            "SELECT srs_identity,record_object FROM is_index_entries "
            "WHERE srs_identity LIKE '%:' || ? "
            "ORDER BY append_order DESC LIMIT 1",
            (state_id,),
        ).fetchone()
        if row is None:
            return None
        value = json.loads(self.carrier.get_object(row["record_object"]))
        value["_identity"] = row["srs_identity"]
        value["_object_id"] = row["record_object"]
        return value

    def _verify_signed_settlement(
        self,
        settlement: dict,
        item: dict,
        dependency_object_ids: dict,
        dependency_values: Optional[dict],
    ) -> tuple[bool, Optional[str]]:
        """Verify the detached signature and its semantic binding.

        The signature covers a canonical payload whose settlement id is the
        content address of the declaration.  Verification therefore checks both
        the cryptographic signature and the declaration's current semantic
        binding (task object, source, dependency closure, validity and event
        chain).  A signature over a stale declaration is not reusable.
        """
        provenance = settlement.get("provenance")
        if self.provenance_policy == "off":
            return (True, None) if provenance is None else (False, "SETTLEMENT_SIGNATURE_UNVERIFIABLE")
        if not isinstance(provenance, dict):
            return False, "SETTLEMENT_SIGNATURE_MISSING"
        signature = self.current_settlement_signature(item["item_id"])
        if signature is None:
            return False, "SETTLEMENT_SIGNATURE_MISSING"
        object_id = settlement.get("_object_id")
        if not object_id:
            return False, "SETTLEMENT_OBJECT_ID_MISSING"
        try:
            payload = settlement_provenance.verify_signature(
                signature,
                self.trust_anchor,
                expected_settlement_object_id=object_id,
                expected_item_id=item["item_id"],
            )
            if payload.get("provenance") != provenance:
                return False, "SETTLEMENT_PROVENANCE_MISMATCH"
            if payload.get("advancement_id") != settlement.get("advancement_id"):
                return False, "SETTLEMENT_PROVENANCE_MISMATCH"
            if payload.get("settlement_contract") != settlement.get("settlement_contract"):
                return False, "SETTLEMENT_PROVENANCE_MISMATCH"
            if payload.get("settlement_schema_id") != settlement.get("schema_id"):
                return False, "SETTLEMENT_PROVENANCE_MISMATCH"
            provenance = settlement_provenance.validate_provenance_shape(provenance)
        except settlement_provenance.ProvenanceError as error:
            if error.code.startswith("SIGNATURE"):
                return False, "SETTLEMENT_SIGNATURE_INVALID"
            if error.code.startswith("TRUST_ANCHOR") or error.code.startswith("KEY_ID"):
                return False, "SETTLEMENT_TRUST_ANCHOR_INVALID"
            return False, "SETTLEMENT_PROVENANCE_MISMATCH"
        except Exception:  # noqa: BLE001 - any defect is a refusal
            return False, "SETTLEMENT_SIGNATURE_INVALID"

        item_record = self.current_item_record(item["item_id"])
        if item_record is None:
            return False, "SETTLEMENT_PROVENANCE_MISMATCH"
        task = provenance["task"]
        source = provenance["source"]
        if (
            task.get("item_id") != item["item_id"]
            or task.get("item_object_id") != item_record["object_id"]
            or task.get("payload_sha256") != digest(item)
        ):
            return False, "SETTLEMENT_PROVENANCE_MISMATCH"
        if (
            source.get("object_id") != item_record["object_id"]
            or source.get("payload_sha256") != digest(item["source_payload"])
            or source.get("version") != item["source_version"]
        ):
            return False, "SETTLEMENT_PROVENANCE_MISMATCH"
        signed_dependencies = provenance["dependencies"]
        if set(signed_dependencies) != set(dependency_object_ids):
            return False, "SETTLEMENT_PROVENANCE_MISMATCH"
        for dependency_id, signed in signed_dependencies.items():
            if signed.get("object_id") != dependency_object_ids[dependency_id]:
                return False, "SETTLEMENT_PROVENANCE_MISMATCH"
            if dependency_values is not None:
                if dependency_id not in dependency_values:
                    return False, "SETTLEMENT_PROVENANCE_MISMATCH"
                if signed.get("result_value_sha256") != digest(
                    dependency_values[dependency_id]
                ):
                    return False, "SETTLEMENT_PROVENANCE_MISMATCH"
        result = settlement["result"]
        if provenance["result_value_sha256"] != digest(result["value"]):
            return False, "SETTLEMENT_PROVENANCE_MISMATCH"
        validity = provenance["validity"]
        policy = item.get("validity_policy")
        if (
            validity.get("evaluated_at_utc") != result["evaluated_at_utc"]
            or validity.get("valid_until_utc") != result["valid_until_utc"]
            or validity.get("validity_policy_sha256")
            != (digest(policy) if policy is not None else None)
        ):
            return False, "SETTLEMENT_PROVENANCE_MISMATCH"
        producer = provenance["producer"]
        if producer.get("kind") == "model_task":
            if provenance.get("model") is None or provenance.get("output") is None:
                return False, "SETTLEMENT_PROVENANCE_MISMATCH"
        history = self.carrier.get_dependency_history(f"settlement:{item['item_id']}")
        event = provenance["event"]
        expected_previous = history[-2].content_address if len(history) >= 2 else None
        if event.get("sequence") != len(history):
            return False, "SETTLEMENT_EVENT_CHAIN_INVALID"
        if event.get("previous_settlement_object_id") != expected_previous:
            return False, "SETTLEMENT_EVENT_CHAIN_INVALID"
        expected_event_id = settlement_provenance.digest({
            "item_id": item["item_id"],
            "sequence": event.get("sequence"),
            "previous_settlement_object_id": expected_previous,
            "result_value_sha256": result["result_value_sha256"],
            "evaluated_at_utc": result["evaluated_at_utc"],
        })
        if event.get("settlement_event_id") != expected_event_id:
            return False, "SETTLEMENT_EVENT_CHAIN_INVALID"
        return True, None

    def _settlement_reuse_decision(
        self,
        settlement: Optional[dict],
        item: dict,
        dependency_object_ids: dict,
        evaluated_at: datetime,
        dependency_values: Optional[dict] = None,
    ) -> tuple[bool, Optional[str]]:
        """Decide whether a settlement may be reused for the current source.

        Returns (reusable, refusal_reason). An unreadable, opaque or expired
        settlement is a refusal, never an exception: fail closed, but keep the
        reason so the caller can record why the work was redone.
        """
        if settlement is None:
            return False, "MISSING_OR_SUPERSEDED_SETTLEMENT"
        if settlement.get("state") == "INVALID":
            return False, "SETTLEMENT_INVALID"
        if settlement.get("state") != "SETTLED":
            return False, "SETTLEMENT_NOT_SETTLED"
        if settlement.get("settlement_contract") != SETTLEMENT_CONTRACT:
            return False, "SETTLEMENT_CONTRACT_OPAQUE"
        result = settlement.get("result")
        basis = settlement.get("basis")
        if not isinstance(result, dict) or not isinstance(basis, dict):
            return False, "SETTLEMENT_CONTRACT_MALFORMED"
        if any(field not in result for field in SETTLEMENT_RESULT_FIELDS):
            return False, "SETTLEMENT_CONTRACT_MALFORMED"
        if any(field not in basis for field in SETTLEMENT_BASIS_FIELDS):
            return False, "SETTLEMENT_CONTRACT_MALFORMED"
        try:
            settlement_value_sha256 = digest(result["value"])
            settlement_valid_until = basis["valid_until_utc"]
            if settlement_valid_until is not None and evaluated_at > parse_utc(
                settlement_valid_until
            ):
                return False, "SETTLEMENT_EXPIRED"
            source_payload_sha256 = digest(item["source_payload"])
            reusable = (
                result["source_payload_sha256"] == source_payload_sha256
                and basis["source_payload_sha256"] == source_payload_sha256
                and result["result_value_sha256"] == settlement_value_sha256
                and basis["result_value_sha256"] == settlement_value_sha256
                and result["source_version"] == item["source_version"]
                and basis["source_version"] == item["source_version"]
                and result["dependency_object_ids"] == dependency_object_ids
                and basis["dependency_object_ids"] == dependency_object_ids
                and result["valid_until_utc"] == settlement_valid_until
                and item.get("valid_until_utc") == settlement_valid_until
                and result["validity_policy"] == item.get("validity_policy")
                and basis["validity_policy"] == item.get("validity_policy")
                and parse_utc(result["evaluated_at_utc"]) <= evaluated_at
            )
        except (KeyError, TypeError, ValueError):
            return False, "SETTLEMENT_CONTRACT_MALFORMED"
        if not reusable:
            return False, "SETTLEMENT_BASIS_MISMATCH"
        return self._verify_signed_settlement(
            settlement, item, dependency_object_ids, dependency_values
        )

    def execute_demand(
        self,
        demand_id: str,
        advancement_id: str,
        calculator: Callable[[str, dict, dict], dict],
        *,
        evaluated_at_utc: str,
        expected_validity_policy_sha256: Optional[str] = None,
        require_deployment_policy: bool = False,
        provenance_overrides: Optional[dict] = None,
    ) -> dict:
        result: Optional[dict] = None
        expected_prior_state: Optional[dict] = None
        try:
            with self.carrier.transaction():
                demand = self.current_demand(demand_id)
                if demand is None:
                    raise ValueError(f"unknown demand: {demand_id}")
                prior_state = self.latest_execution_state(demand["continuation_point"])
                if prior_state is not None:
                    if prior_state["status"] == "BLOCKED":
                        raise ValueError(
                            "blocked execution state cannot continue without repair: "
                            f"{prior_state['state_id']}"
                        )
                    runtime_status = prior_state.get("runtime_application_status")
                    if runtime_status == "PENDING_SWIFT":
                        raise ValueError(
                            "pending runtime application requires confirmation: "
                            f"{prior_state['state_id']}"
                        )
                    if runtime_status != "APPLIED_SWIFT":
                        raise ValueError(
                            "execution state has no verifiable runtime-application completion"
                        )
                expected_prior_state = prior_state
                result = self._execute_demand_in_transaction(
                    demand_id, advancement_id, calculator,
                    evaluated_at_utc=evaluated_at_utc,
                    expected_validity_policy_sha256=expected_validity_policy_sha256,
                    require_deployment_policy=require_deployment_policy,
                    provenance_overrides=provenance_overrides,
                )
                if not result["advanced"]:
                    raise _DemandNotAdvanced(result)
        except _DemandNotAdvanced as error:
            if error.result.get("state", "").startswith("BLOCKED_"):
                # Begin the append transaction before reading the lineage link;
                # otherwise another writer can advance between the read and append.
                with self.carrier.atomic_write_group():
                    current_state = self.latest_execution_state(
                        self.current_demand(demand_id)["continuation_point"]
                    )
                    expected_id = (
                        expected_prior_state["state_id"]
                        if expected_prior_state
                        else None
                    )
                    current_id = current_state["state_id"] if current_state else None
                    if current_id != expected_id:
                        raise ConcurrentStateTransition(
                            "latest execution state changed during blocked attempt: "
                            f"{expected_id} -> {current_id}"
                        )
                    self.record_execution_state(
                        advancement_id,
                        continuation_point=self.current_demand(demand_id)["continuation_point"],
                        prior_state_id=current_id,
                        demand_id=demand_id,
                        status="BLOCKED",
                        pending_obligations=[error.result.get("failure_reason", "information demand blocked")],
                        next_continuation_point="await-operator-or-refreshed-information",
                        result_digest=digest(error.result),
                    )
            return error.result
        assert result is not None
        return result

    def _execute_demand_in_transaction(
        self,
        demand_id: str,
        advancement_id: str,
        calculator: Callable[[str, dict, dict], dict],
        *,
        evaluated_at_utc: str,
        expected_validity_policy_sha256: Optional[str] = None,
        require_deployment_policy: bool = False,
        provenance_overrides: Optional[dict] = None,
    ) -> dict:
        demand = self.current_demand(demand_id)
        if demand is None:
            raise ValueError(f"unknown demand: {demand_id}")
        try:
            evaluated_at = parse_utc(evaluated_at_utc)
        except ValueError as error:
            return {
                "demand_id": demand_id,
                "state": "BLOCKED_VALIDITY_FAILURE",
                "validity_failure_item_ids": list(demand["required_item_ids"]),
                "actions": [],
                "advanced": False,
                "failure_reason": str(error),
            }
        required = demand["required_item_ids"]
        actions: list[dict] = []
        missing: list[str] = []
        missing_validity: list[str] = []
        policy_mismatch: list[str] = []
        invalid_validity: list[str] = []
        stale_item_ids: list[str] = []
        computed: list[str] = []
        reused: list[str] = []
        resolved: dict[str, dict] = {}

        # Preflight the complete dependency closure before any calculator or
        # settlement can run. This prevents a stale transitive dependency from
        # being settled merely because it was omitted from required_item_ids.
        closure: dict[str, dict] = {}
        pending_items = list(required)
        while pending_items:
            item_id = pending_items.pop(0)
            if item_id in closure:
                continue
            item = self.current_item(item_id)
            if item is None:
                missing.append(item_id)
                continue
            closure[item_id] = item
            pending_items.extend(item["dependencies"])
            valid_until = item.get("valid_until_utc")
            if valid_until is None:
                missing_validity.append(item_id)
                continue
            try:
                validity_policy_identity(item.get("validity_policy"))
            except ValueError:
                missing_validity.append(item_id)
                continue
            stored_policy = item.get("validity_policy")
            if require_deployment_policy and expected_validity_policy_sha256 is None:
                missing_validity.append(item_id)
            elif expected_validity_policy_sha256 is not None and stored_policy.get(
                "policy_sha256"
            ) != expected_validity_policy_sha256:
                policy_mismatch.append(item_id)
            try:
                if evaluated_at > parse_utc(valid_until):
                    stale_item_ids.append(item_id)
            except ValueError:
                invalid_validity.append(item_id)

        if missing:
            return {
                "demand_id": demand_id,
                "state": "BLOCKED_MISSING_INFORMATION",
                "missing_item_ids": missing,
                "actions": [
                    {"item_id": item_id, "action": "BLOCKED_MISSING"}
                    for item_id in missing
                ],
                "advanced": False,
            }
        if missing_validity:
            return {
                "demand_id": demand_id,
                "state": "BLOCKED_MISSING_VALIDITY",
                "validity_failure_item_ids": missing_validity,
                "actions": [
                    {"item_id": item_id, "action": "BLOCKED_MISSING_VALIDITY"}
                    for item_id in missing_validity
                ],
                "advanced": False,
                "failure_reason": "validity policy is undefined; fail closed",
            }
        if invalid_validity:
            return {
                "demand_id": demand_id,
                "state": "BLOCKED_INVALID_VALIDITY",
                "validity_failure_item_ids": invalid_validity,
                "actions": [
                    {"item_id": item_id, "action": "BLOCKED_INVALID_VALIDITY"}
                    for item_id in invalid_validity
                ],
                "advanced": False,
                "failure_reason": "source validity is malformed; fail closed",
            }
        if policy_mismatch:
            return {
                "demand_id": demand_id,
                "state": "BLOCKED_POLICY_MISMATCH",
                "validity_failure_item_ids": policy_mismatch,
                "actions": [
                    {
                        "item_id": item_id,
                        "action": "BLOCKED_POLICY_MISMATCH",
                    }
                    for item_id in policy_mismatch
                ],
                "advanced": False,
                "failure_reason": (
                    "source validity policy does not match the deployment policy; fail closed"
                ),
            }
        if stale_item_ids:
            return {
                "demand_id": demand_id,
                "state": "BLOCKED_STALE_VALIDITY",
                "validity_failure_item_ids": stale_item_ids,
                "actions": [
                    {"item_id": item_id, "action": "BLOCKED_STALE_VALIDITY"}
                    for item_id in stale_item_ids
                ],
                "advanced": False,
                "failure_reason": "source validity expired without refreshed authorization",
            }

        def resolve(item_id: str, visiting: set[str]) -> Optional[dict]:
            if item_id in resolved:
                return resolved[item_id]
            if item_id in visiting:
                raise ValueError(f"dependency cycle at {item_id}")
            visiting.add(item_id)
            item = self.current_item(item_id)
            if item is None:
                missing.append(item_id)
                actions.append({"item_id": item_id, "action": "BLOCKED_MISSING"})
                return None
            source_valid_until = item.get("valid_until_utc")
            if source_valid_until is not None:
                try:
                    source_expired = evaluated_at > parse_utc(source_valid_until)
                except ValueError:
                    invalid_validity.append(item_id)
                    actions.append({
                        "item_id": item_id,
                        "action": "BLOCKED_INVALID_VALIDITY",
                        "valid_until_utc": source_valid_until,
                    })
                    return None
                if source_expired:
                    stale_item_ids.append(item_id)
            dependencies = item["dependencies"]
            dependency_values: dict[str, dict] = {}
            dependency_object_ids: dict[str, str] = {}
            dependency_blocked = False
            for dependency_id in dependencies:
                dependency = resolve(dependency_id, visiting)
                if dependency is None:
                    dependency_blocked = True
                else:
                    dependency_values[dependency_id] = dependency["value"]
                    dependency_object_ids[dependency_id] = dependency["object_id"]
            if dependency_blocked:
                missing.append(item_id)
                actions.append({"item_id": item_id, "action": "BLOCKED_DEPENDENCY_MISSING"})
                return None

            valid_until_utc = item.get("valid_until_utc")
            settlement = self.current_settlement(item_id)
            reusable, reuse_refusal_reason = self._settlement_reuse_decision(
                settlement, item, dependency_object_ids, evaluated_at, dependency_values
            )
            source_payload_sha256 = digest(item["source_payload"])
            if reusable:
                result = settlement["result"]["value"]
                action = "REUSE"
                reused.append(item_id)
                # Report the signature object that admitted this reuse, so the
                # action record distinguishes "verified reuse" from reuse that
                # merely found an object with the right digest.
                signature = self.current_settlement_signature(item_id)
                settlement_record = {
                    "object_id": settlement["_object_id"],
                    "signature_object_id": (signature or {}).get("_object_id"),
                }
            else:
                action_reason = (
                    "VALIDITY_EXPIRED" if item_id in stale_item_ids
                    else (reuse_refusal_reason or "MISSING_OR_SUPERSEDED_SETTLEMENT")
                )
                result = calculator(item_id, item["source_payload"], dependency_values)
                action = "COMPUTE"
                computed.append(item_id)
                settlement_basis = {
                    "source_payload_sha256": source_payload_sha256,
                    "result_value_sha256": digest(result),
                    "source_version": item["source_version"],
                    "dependency_object_ids": {
                        key: dependency_object_ids[key] for key in dependency_values
                    },
                    "evaluated_at_utc": evaluated_at_utc,
                    "valid_until_utc": valid_until_utc,
                    "validity_policy": item.get("validity_policy"),
                }
                item_record = self.current_item_record(item_id)
                if item_record is None:
                    raise settlement_provenance.ProvenanceError(
                        "TASK_ITEM_RECORD_MISSING", item_id
                    )
                settlement_result = {"value": result, **settlement_basis}
                provenance = self._provenance_for_settlement(
                    item,
                    item_record,
                    item_id,
                    settlement_result,
                    dependency_object_ids,
                    dependency_values,
                    (provenance_overrides or {}).get(item_id),
                )
                settlement_record = self.settle(
                    advancement_id,
                    item_id,
                    settlement_result,
                    settlement_basis,
                    provenance,
                )
            resolved[item_id] = {"value": result, "object_id": settlement_record["object_id"]}
            actions.append({
                "item_id": item_id,
                "action": action,
                "reason": None if action == "REUSE" else action_reason,
                "result_digest": digest(result),
                "settlement_object_id": settlement_record["object_id"],
                "settlement_signature_object_id": settlement_record.get(
                    "signature_object_id"
                ),
                "source_payload_sha256": source_payload_sha256,
            })
            return {"value": result, "object_id": settlement_record["object_id"]}

        for item_id in required:
            resolved_value = resolve(item_id, set())
            if resolved_value is None:
                result = {
                    "demand_id": demand_id,
                    "state": "BLOCKED_MISSING_INFORMATION",
                    "missing_item_ids": missing,
                    "actions": actions,
                    "advanced": False,
                }
                return result

        result_payload = {
            "demand_id": demand_id,
            "continuation_point": demand["continuation_point"],
            "resolved_items": {key: value["value"] for key, value in resolved.items()},
        }
        if required:
            prior_state = self.latest_execution_state(
                demand["continuation_point"]
            )
            self.record_execution_state(
                advancement_id,
                continuation_point=demand["continuation_point"],
                prior_state_id=prior_state["state_id"] if prior_state else None,
                demand_id=demand_id,
                status="ADVANCED",
                pending_obligations=[
                    "apply runtime continuation and representation binding"
                ],
                next_continuation_point="await-runtime-application-completion",
                result_digest=digest(result_payload),
                runtime_application_status="PENDING_SWIFT",
            )
            execution_state = self.latest_execution_state(
                demand["continuation_point"]
            )
        else:
            execution_state = None
        return {
            "demand_id": demand_id,
            "state": "ADVANCED",
            "actions": actions,
            "computed_item_ids": computed,
            "reused_item_ids": reused,
            "result": result_payload,
            "advanced": True,
            "execution_state": execution_state,
        }


def audit_settlement_contracts(database_path: str) -> dict:
    """Classify the current settlement of each item without writing to the carrier.

    Historical carriers may contain settlements written before the contract
    existed. They stay readable, but they are reported as opaque so no caller
    mistakes them for reusable work.
    """
    import sqlite3

    uri = Path(database_path).resolve().as_uri() + "?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    connection.row_factory = sqlite3.Row
    try:
        rows = connection.execute(
            "SELECT append_order,srs_identity,record_object "
            "FROM is_index_entries WHERE srs_identity LIKE 'settlement:%' "
            "ORDER BY append_order ASC"
        ).fetchall()
        latest: dict[str, dict] = {}
        for row in rows:
            item_id = row["srs_identity"][len("settlement:"):]
            body = connection.execute(
                "SELECT object_id,byte_size,content FROM is_objects WHERE object_id=?",
                (row["record_object"],),
            ).fetchone()
            if body is None:
                latest[item_id] = {
                    "item_id": item_id,
                    "object_id": row["record_object"],
                    "classification": "MISSING_OBJECT",
                }
                continue
            content = bytes(body["content"])
            bytes_match = hashlib.sha256(content).hexdigest() == body["object_id"]
            try:
                value = json.loads(content)
            except ValueError:
                latest[item_id] = {
                    "item_id": item_id,
                    "object_id": body["object_id"],
                    "classification": "UNREADABLE",
                    "bytes_match_address": bytes_match,
                }
                continue
            state = value.get("state")
            contract = value.get("settlement_contract")
            if state == "INVALID":
                classification = "INVALIDATION_RECORD"
            elif state != "SETTLED":
                classification = "NOT_SETTLED"
            elif contract != SETTLEMENT_CONTRACT:
                classification = "OPAQUE"
            else:
                try:
                    validate_settlement_payload(value.get("result"), value.get("basis"))
                    classification = "CONFORMING"
                except SettlementContractViolation:
                    classification = "MALFORMED"
            latest[item_id] = {
                "item_id": item_id,
                "object_id": body["object_id"],
                "state": state,
                "settlement_contract": contract,
                "bytes_match_address": bytes_match,
                "classification": classification,
            }
    finally:
        connection.close()

    settlements = [latest[item_id] for item_id in sorted(latest)]
    counts: dict[str, int] = {}
    for settlement in settlements:
        key = settlement["classification"]
        counts[key] = counts.get(key, 0) + 1
    return {
        "schema_id": "EINFO-SETTLEMENT-CONTRACT-AUDIT-V1",
        "contract": SETTLEMENT_CONTRACT,
        "carrier_contract_version": CARRIER_LOOP_CONTRACT_VERSION,
        "database_path": str(Path(database_path).resolve()),
        "settlements": settlements,
        "counts": counts,
        "all_conforming": bool(settlements)
        and all(item["classification"] == "CONFORMING" for item in settlements),
    }
