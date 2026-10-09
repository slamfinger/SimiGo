"""ES-driven Information Space loop backed by the existing D002 carrier.

This module reuses `database-carrier-replication/implementation/db_is.py`
without modification. All durable state is stored as canonical JSON objects in
the carrier's append-only object store; current items and settlements are
resolved through the carrier's index and dependency ledgers.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any, Callable, Optional

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "database-carrier-replication" / "implementation"))
from db_is import DatabaseBackedIS, MissingLogicalEntry  # noqa: E402


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


class CarrierInformationLoop:
    """Minimal ES/IS continuation loop over DatabaseBackedIS."""

    def __init__(self, carrier: DatabaseBackedIS):
        self.carrier = carrier

    @classmethod
    def create(cls, database_path: str) -> "CarrierInformationLoop":
        path = Path(database_path)
        if path.exists() or path.is_symlink():
            raise FileExistsError(path)
        carrier = DatabaseBackedIS.init_empty(database_path)
        return cls(carrier)

    @classmethod
    def open(cls, database_path: str) -> "CarrierInformationLoop":
        path = Path(database_path)
        if not path.is_file() or path.is_symlink():
            raise FileNotFoundError(path)
        carrier = DatabaseBackedIS(path)
        carrier.validate_schema()
        return cls(carrier)

    def commit(self) -> None:
        self.carrier.connection.commit()

    def close(self) -> None:
        self.carrier.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()

    def _current_index_object(self, identity: str) -> Optional[dict]:
        row = self.carrier.connection.execute(
            "SELECT append_order,srs_identity,record_object "
            "FROM is_index_entries WHERE srs_identity=? "
            "ORDER BY append_order DESC LIMIT 1",
            (identity,),
        ).fetchone()
        if row is None:
            return None
        return json.loads(self.carrier.get_object(row["record_object"]))

    def _current_dependency_object(self, dependency_id: str) -> Optional[dict]:
        try:
            record = self.carrier.resolve_current_dependency(dependency_id)
        except MissingLogicalEntry:
            return None
        value = json.loads(self.carrier.get_object(record.content_address))
        value["_object_id"] = record.content_address
        return value

    def _put_index_object(self, identity: str, value: dict) -> str:
        content = canonical(value)
        object_id = self.carrier.write_object(content)
        self.carrier.append_index_entry({
            "srs_identity": identity,
            "record_object": object_id,
        })
        return object_id

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
    ) -> dict:
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
        }
        content = canonical(value)
        dependency_id = f"dependency:{item_id}"
        history = self.carrier.get_dependency_history(dependency_id)
        revision = len(history) + 1
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
    ) -> dict:
        old = self._current_index_object(f"item:{item_id}")
        if old is None:
            raise MissingLogicalEntry(f"item:{item_id}")
        value = {
            "schema_id": "EINFO-INFORMATION-ITEM-V1",
            "demand_id": old["demand_id"],
            "item_id": item_id,
            "source_kind": old["source_kind"],
            "source_version": source_version,
            "source_payload": source_payload,
            "dependencies": old["dependencies"],
        }
        content = canonical(value)
        dependency_id = f"dependency:{item_id}"
        revision = len(self.carrier.get_dependency_history(dependency_id)) + 1
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

    def settle(
        self,
        advancement_id: str,
        item_id: str,
        result: dict,
        basis: dict,
    ) -> dict:
        value = {
            "schema_id": "EINFO-SETTLEMENT-V1",
            "state": "SETTLED",
            "advancement_id": advancement_id,
            "item_id": item_id,
            "result": result,
            "basis": basis,
        }
        content = canonical(value)
        dependency_id = f"settlement:{item_id}"
        revision = len(self.carrier.get_dependency_history(dependency_id)) + 1
        object_id, dependency_order = self.carrier.atomic_dependency_materialization(
            content,
            {
                "dependency_id": dependency_id,
                "content_address": "",
                "revision": revision,
                "reason": "settled result",
            },
        )
        self.carrier.append_index_entry({
            "srs_identity": f"settlement:{item_id}",
            "record_object": object_id,
        })
        return {
            "item_id": item_id,
            "object_id": object_id,
            "dependency_order": dependency_order,
        }

    def invalidate_settlement(
        self,
        target_item_id: str,
        reason: str,
        include_dependents: bool = True,
    ) -> dict:
        """Append explicit invalidation records for an item and its dependents."""
        items = {}
        for row in self.carrier.connection.execute(
            "SELECT append_order,srs_identity,record_object "
            "FROM is_index_entries WHERE srs_identity LIKE 'item:%' "
            "ORDER BY append_order ASC"
        ):
            item_id = row["srs_identity"][len("item:"):]
            value = json.loads(self.carrier.get_object(row["record_object"]))
            items[item_id] = value["dependencies"]
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

    def current_settlement(self, item_id: str) -> Optional[dict]:
        return self._current_dependency_object(f"settlement:{item_id}")

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
    ) -> dict:
        if status not in {"RESTORED", "ADVANCED", "BLOCKED"}:
            raise ValueError("invalid execution state")
        identity = f"execution_state:{continuation_point}:{state_id}"
        if self._current_index_object(identity) is not None:
            raise FileExistsError(identity)
        value = {
            "schema_id": "EINFO-EXECUTION-STATE-V1",
            "state_id": state_id,
            "continuation_point": continuation_point,
            "prior_state_id": prior_state_id,
            "demand_id": demand_id,
            "status": status,
            "pending_obligations": pending_obligations,
            "next_continuation_point": next_continuation_point,
            "result_digest": result_digest,
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

    def execute_demand(
        self,
        demand_id: str,
        advancement_id: str,
        calculator: Callable[[str, dict, dict], dict],
    ) -> dict:
        demand = self.current_demand(demand_id)
        if demand is None:
            raise ValueError(f"unknown demand: {demand_id}")
        required = demand["required_item_ids"]
        actions: list[dict] = []
        missing: list[str] = []
        computed: list[str] = []
        reused: list[str] = []
        resolved: dict[str, dict] = {}

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

            settlement = self.current_settlement(item_id)
            reusable = False
            if settlement is not None and settlement.get("state") != "SETTLED":
                reusable = False
            elif settlement is not None:
                basis = settlement["basis"]
                try:
                    reusable = (
                        settlement["result"]["payload_digest"] == digest(item["source_payload"])
                        and settlement["result"]["source_version"] == item["source_version"]
                        and settlement["result"]["dependency_object_ids"] == dependency_object_ids
                        and basis["source_payload_sha256"] == digest(item["source_payload"])
                        and basis["source_version"] == item["source_version"]
                        and basis["dependency_object_ids"] == dependency_object_ids
                    )
                except KeyError:
                    reusable = False
            basis = settlement.get("basis") if settlement is not None else None
            payload_digest = digest(item["source_payload"])
            if reusable:
                result = settlement["result"]["value"]
                action = "REUSE"
                reused.append(item_id)
                settlement_record = {
                    "object_id": settlement["_object_id"],
                }
            else:
                result = calculator(item_id, item["source_payload"], dependency_values)
                action = "COMPUTE"
                computed.append(item_id)
                settlement_record = self.settle(
                    advancement_id,
                    item_id,
                    {
                        "value": result,
                        "payload_digest": payload_digest,
                        "source_version": item["source_version"],
                        "dependency_object_ids": {
                            key: dependency_object_ids[key] for key in dependency_values
                        },
                    },
                    {
                        "source_payload_sha256": payload_digest,
                        "source_version": item["source_version"],
                        "dependency_object_ids": {
                            key: dependency_object_ids[key] for key in dependency_values
                        },
                    },
                )
            resolved[item_id] = {"value": result, "object_id": settlement_record["object_id"]}
            actions.append({
                "item_id": item_id,
                "action": action,
                "result_digest": digest(result),
                "settlement_object_id": settlement_record["object_id"],
                "source_payload_digest": payload_digest,
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
        return {
            "demand_id": demand_id,
            "state": "ADVANCED",
            "actions": actions,
            "computed_item_ids": computed,
            "reused_item_ids": reused,
            "result": result_payload,
            "advanced": True,
        }
