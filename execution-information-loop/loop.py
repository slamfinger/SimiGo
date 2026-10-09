"""Minimal ES-driven Information Space incremental continuation loop.

Isolated reference implementation. SQLite is the physical Information Space;
Execution State derives a demand; valid settlements are reused; missing, stale,
invalid, or dependency-changed items are selectively recomputed; all transitions
are appended to a digest-chained audit log.
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional, Tuple


SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE es_demands (
    demand_id TEXT PRIMARY KEY,
    continuation_point TEXT NOT NULL,
    pending_obligations_json TEXT NOT NULL,
    continuation_conditions_json TEXT NOT NULL,
    required_item_ids_json TEXT NOT NULL,
    state TEXT NOT NULL CHECK(state IN ('ACTIVE','ADVANCED','BLOCKED')),
    created_order INTEGER NOT NULL UNIQUE
);

CREATE TABLE information_items (
    item_id TEXT PRIMARY KEY,
    demand_id TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    source_version TEXT NOT NULL,
    source_payload_json TEXT NOT NULL,
    source_payload_sha256 TEXT NOT NULL CHECK(length(source_payload_sha256) = 64),
    dependencies_json TEXT NOT NULL,
    state TEXT NOT NULL CHECK(state IN ('AVAILABLE','STALE','INVALID')),
    declared_order INTEGER NOT NULL UNIQUE,
    FOREIGN KEY (demand_id) REFERENCES es_demands(demand_id)
);

CREATE TABLE settlements (
    settlement_id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES information_items(item_id),
    result_json TEXT NOT NULL,
    result_sha256 TEXT NOT NULL CHECK(length(result_sha256) = 64),
    basis_json TEXT NOT NULL,
    state TEXT NOT NULL CHECK(state IN ('SETTLED','INVALID')),
    settlement_order INTEGER NOT NULL UNIQUE,
    superseded_by TEXT
);

CREATE TABLE es_advancements (
    advancement_id TEXT PRIMARY KEY,
    demand_id TEXT NOT NULL REFERENCES es_demands(demand_id),
    required_item_ids_json TEXT NOT NULL,
    actions_json TEXT NOT NULL,
    result_json TEXT NOT NULL,
    advanced_order INTEGER NOT NULL UNIQUE
);

CREATE TABLE audit_events (
    event_order INTEGER PRIMARY KEY,
    event_type TEXT NOT NULL,
    aggregate_id TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    previous_event_digest TEXT NOT NULL,
    event_digest TEXT NOT NULL UNIQUE
);
"""


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


class InformationLoop:
    """SQLite-backed reference implementation of the ES/IS continuation loop."""

    def __init__(self, database_path: str):
        self.database_path = database_path
        self.connection = sqlite3.connect(database_path)
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA foreign_keys = ON")

    @classmethod
    def create(cls, database_path: str) -> "InformationLoop":
        path = Path(database_path)
        if path.exists() or path.is_symlink():
            raise FileExistsError(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        loop = cls(database_path)
        loop.connection.executescript(SCHEMA)
        loop.connection.commit()
        loop._append("SYSTEM_INIT", "database", {"schema": "execution-information-loop-v1"})
        return loop

    @classmethod
    def open(cls, database_path: str) -> "InformationLoop":
        path = Path(database_path)
        if not path.is_file() or path.is_symlink():
            raise FileNotFoundError(path)
        loop = cls(database_path)
        tables = {row[0] for row in loop.connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        )}
        required = {"es_demands", "information_items", "settlements", "es_advancements", "audit_events"}
        if not required.issubset(tables):
            raise ValueError("not an execution-information-loop database")
        return loop

    def close(self) -> None:
        self.connection.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()

    def _next_order(self, table: str, column: str) -> int:
        row = self.connection.execute(
            f"SELECT COALESCE(MAX({column}),0)+1 AS next_order FROM {table}"
        ).fetchone()
        return int(row["next_order"])

    def _append(self, event_type: str, aggregate_id: str, payload: dict) -> str:
        previous = self.connection.execute(
            "SELECT event_digest FROM audit_events ORDER BY event_order DESC LIMIT 1"
        ).fetchone()
        previous_digest = previous["event_digest"] if previous else "GENESIS"
        event_order = self._next_order("audit_events", "event_order")
        payload_json = canonical(payload).decode("utf-8")
        chain_input = previous_digest.encode("utf-8") + b"\x00" + payload_json.encode("utf-8")
        event_digest = hashlib.sha256(chain_input).hexdigest()
        self.connection.execute(
            "INSERT INTO audit_events "
            "(event_type,aggregate_id,payload_json,previous_event_digest,event_digest,event_order) "
            "VALUES (?,?,?,?,?,?)",
            (event_type, aggregate_id, payload_json, previous_digest, event_digest, event_order),
        )
        return event_digest

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
        payload = {
            "continuation_point": continuation_point,
            "pending_obligations": pending_obligations,
            "continuation_conditions": continuation_conditions,
            "required_item_ids": required_item_ids,
        }
        order = self._next_order("es_demands", "created_order")
        self.connection.execute(
            "INSERT INTO es_demands "
            "(demand_id,continuation_point,pending_obligations_json,continuation_conditions_json,"
            "required_item_ids_json,state,created_order) VALUES (?,?,?,?,?,'ACTIVE',?)",
            (
                demand_id,
                continuation_point,
                canonical(pending_obligations).decode(),
                canonical(continuation_conditions).decode(),
                canonical(required_item_ids).decode(),
                order,
            ),
        )
        event = self._append("ES_DEMAND_DEFINED", demand_id, payload)
        self.connection.commit()
        return {"demand_id": demand_id, "event_digest": event, **payload}

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
        payload_digest = digest(source_payload)
        order = self._next_order("information_items", "declared_order")
        self.connection.execute(
            "INSERT INTO information_items "
            "(item_id,demand_id,source_kind,source_version,source_payload_json,"
            "source_payload_sha256,dependencies_json,state,declared_order) "
            "VALUES (?,?,?,?,?,?,?,'AVAILABLE',?)",
            (
                item_id,
                demand_id,
                source_kind,
                source_version,
                canonical(source_payload).decode(),
                payload_digest,
                canonical(dependencies).decode(),
                order,
            ),
        )
        event = self._append(
            "SOURCE_PUT", item_id,
            {"demand_id": demand_id, "source_version": source_version, "source_payload_sha256": payload_digest},
        )
        self.connection.commit()
        return {"item_id": item_id, "source_payload_sha256": payload_digest, "event_digest": event}

    def invalidate_source(self, item_id: str, reason: str) -> dict:
        affected = self._dependents(item_id, include_self=True)
        now_marker = f"INVALIDATED_BY_{item_id}"
        for affected_id in affected:
            self.connection.execute(
                "UPDATE information_items SET state='STALE', source_version=source_version || ':stale' "
                "WHERE item_id=? AND state='AVAILABLE'",
                (affected_id,),
            )
            self.connection.execute(
                "UPDATE settlements SET state='INVALID', superseded_by=? "
                "WHERE item_id=? AND state='SETTLED'",
                (now_marker, affected_id),
            )
        payload = {"item_id": item_id, "reason": reason, "affected_item_ids": affected}
        event = self._append("SOURCE_INVALIDATED", item_id, payload)
        self.connection.commit()
        return {"affected_item_ids": affected, "event_digest": event, **payload}

    def _dependents(self, item_id: str, include_self: bool = False) -> list[str]:
        rows = self.connection.execute(
            "SELECT item_id,dependencies_json FROM information_items"
        ).fetchall()
        dependency_graph = {
            row["item_id"]: json.loads(row["dependencies_json"]) for row in rows
        }
        dependent_graph: dict[str, list[str]] = {
            row["item_id"]: [] for row in rows
        }
        for dependent_id, dependencies in dependency_graph.items():
            for dependency_id in dependencies:
                dependent_graph.setdefault(dependency_id, []).append(dependent_id)
        found: set[str] = set()
        stack = [item_id] if include_self else list(dependent_graph.get(item_id, []))
        while stack:
            current = stack.pop()
            if current in found:
                continue
            found.add(current)
            stack.extend(dependent_graph.get(current, []))
        return sorted(found)

    def _settlement(self, item_id: str) -> Optional[sqlite3.Row]:
        return self.connection.execute(
            "SELECT * FROM settlements WHERE item_id=? AND state='SETTLED' "
            "ORDER BY settlement_order DESC LIMIT 1",
            (item_id,),
        ).fetchone()

    def _item(self, item_id: str) -> Optional[sqlite3.Row]:
        return self.connection.execute(
            "SELECT * FROM information_items WHERE item_id=?", (item_id,)
        ).fetchone()

    def _valid_settlement(self, item_id: str, visited: Optional[set[str]] = None) -> bool:
        visited = set() if visited is None else visited
        if item_id in visited:
            raise ValueError(f"dependency cycle at {item_id}")
        visited.add(item_id)
        item = self._item(item_id)
        settlement = self._settlement(item_id)
        if item is None or settlement is None:
            return False
        if item["state"] != "AVAILABLE" or settlement["state"] != "SETTLED":
            return False
        payload = json.loads(item["source_payload_json"])
        if digest(payload) != item["source_payload_sha256"]:
            return False
        result = json.loads(settlement["result_json"])
        if digest(result) != settlement["result_sha256"]:
            return False
        basis = json.loads(settlement["basis_json"])
        if basis.get("source_payload_sha256") != item["source_payload_sha256"]:
            return False
        if basis.get("source_version") != item["source_version"]:
            return False
        dependencies = json.loads(item["dependencies_json"])
        for dependency_id in dependencies:
            dependency_item = self._item(dependency_id)
            if dependency_item is None:
                return False
            if not self._valid_settlement(dependency_id, visited):
                return False
            dependency_settlement = self._settlement(dependency_id)
            if dependency_settlement is None:
                return False
            dependency_basis = json.loads(dependency_settlement["basis_json"])
            dependency_result = json.loads(dependency_settlement["result_json"])
            expected = digest(dependency_result)
            actual = basis.get("dependency_digests", {}).get(dependency_id)
            if actual != expected:
                return False
        return True

    def execute_demand(
        self,
        demand_id: str,
        advancement_id: str,
        calculator: Callable[[str, dict, dict], dict],
    ) -> dict:
        demand = self.connection.execute(
            "SELECT * FROM es_demands WHERE demand_id=?", (demand_id,)
        ).fetchone()
        if demand is None:
            raise ValueError(f"unknown demand: {demand_id}")
        required = json.loads(demand["required_item_ids_json"])
        actions: list[dict] = []
        missing: list[str] = []
        computed: list[str] = []
        reused: list[str] = []
        validity_failures: list[str] = []

        # Resolve in declared order; callers must provide an acyclic demand graph.
        resolved_dependencies: dict[str, dict] = {}

        def resolve(item_id: str, visiting: set[str]) -> dict:
            if item_id in resolved_dependencies:
                return resolved_dependencies[item_id]
            if item_id in visiting:
                raise ValueError(f"dependency cycle at {item_id}")
            visiting.add(item_id)
            item = self._item(item_id)
            if item is None:
                raise KeyError(item_id)
            source_payload = json.loads(item["source_payload_json"])
            if digest(source_payload) != item["source_payload_sha256"]:
                raise ValueError("source payload digest mismatch")
            dependencies = json.loads(item["dependencies_json"])
            dependency_values = {dep: resolve(dep, visiting) for dep in dependencies}
            settlement = self._settlement(item_id)
            source_payload = json.loads(item["source_payload_json"])
            eligible = (
                item["state"] == "AVAILABLE"
                and settlement is not None
                and settlement["state"] == "SETTLED"
                and self._valid_settlement(item_id)
            )
            if eligible:
                result = json.loads(settlement["result_json"])
                action = "REUSE"
                reused.append(item_id)
            else:
                result = calculator(item_id, source_payload, dependency_values)
                action = "COMPUTE"
                computed.append(item_id)
                settlement_id = f"{advancement_id}:{item_id}"
                basis = {
                    "source_version": item["source_version"],
                    "source_payload_sha256": item["source_payload_sha256"],
                    "dependency_digests": {
                        dep: digest(dependency_values[dep])
                        for dep in dependencies
                    },
                }
                settlement_order = self._next_order("settlements", "settlement_order")
                self.connection.execute(
                    "INSERT INTO settlements "
                    "(settlement_id,item_id,result_json,result_sha256,basis_json,state,settlement_order) "
                    "VALUES (?,?,?,?,?,'SETTLED',?)",
                    (
                        settlement_id,
                        item_id,
                        canonical(result).decode(),
                        digest(result),
                        canonical(basis).decode(),
                        settlement_order,
                    ),
                )
            resolved_dependencies[item_id] = result
            actions.append({
                "item_id": item_id,
                "action": action,
                "result_digest": digest(result),
                "source_payload_sha256": item["source_payload_sha256"],
            })
            return result

        try:
            for item_id in required:
                try:
                    resolve(item_id, set())
                except KeyError:
                    missing.append(item_id)
                    actions.append({"item_id": item_id, "action": "BLOCKED_MISSING"})
                except ValueError:
                    validity_failures.append(item_id)
                    actions.append({"item_id": item_id, "action": "BLOCKED_PAYLOAD_DIGEST_MISMATCH"})
            if missing or validity_failures:
                self.connection.execute(
                    "UPDATE es_demands SET state='BLOCKED' WHERE demand_id=?", (demand_id,)
                )
                result = {
                    "demand_id": demand_id,
                    "state": "BLOCKED_MISSING_INFORMATION" if missing else "BLOCKED_VALIDITY_FAILURE",
                    "missing_item_ids": missing,
                    "validity_failure_item_ids": validity_failures,
                    "actions": actions,
                    "advanced": False,
                }
                self._append("ES_DEMAND_BLOCKED", demand_id, result)
                self.connection.commit()
                return result

            result_payload = {
                "demand_id": demand_id,
                "continuation_point": demand["continuation_point"],
                "resolved_items": resolved_dependencies,
            }
            advancement_order = self._next_order("es_advancements", "advanced_order")
            self.connection.execute(
                "INSERT INTO es_advancements "
                "(advancement_id,demand_id,required_item_ids_json,actions_json,result_json,advanced_order) "
                "VALUES (?,?,?,?,?,?)",
                (
                    advancement_id,
                    demand_id,
                    canonical(required).decode(),
                    canonical(actions).decode(),
                    canonical(result_payload).decode(),
                    advancement_order,
                ),
            )
            self.connection.execute(
                "UPDATE es_demands SET state='ADVANCED' WHERE demand_id=?", (demand_id,)
            )
            result = {
                "demand_id": demand_id,
                "state": "ADVANCED",
                "actions": actions,
                "computed_item_ids": computed,
                "reused_item_ids": reused,
                "result": result_payload,
                "advanced": True,
            }
            self._append("ES_DEMAND_ADVANCED", demand_id, result)
            self.connection.commit()
            return result
        except Exception:
            self.connection.rollback()
            raise

    def audit_verify(self) -> dict:
        previous = "GENESIS"
        count = 0
        for row in self.connection.execute(
            "SELECT * FROM audit_events ORDER BY event_order"
        ):
            payload = row["payload_json"].encode("utf-8")
            chain_input = previous.encode("utf-8") + b"\x00" + payload
            expected = hashlib.sha256(chain_input).hexdigest()
            if expected != row["event_digest"]:
                return {"result": "FAIL", "broken_event_order": row["event_order"]}
            previous = row["event_digest"]
            count += 1
        return {"result": "PASS", "event_count": count, "terminal_event_digest": previous}
