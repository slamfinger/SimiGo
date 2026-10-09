"""Read-only real PALACE source adapter feeding the D002-backed IS loop.

Allowed source tables are limited to structural metadata. Vector, full-text,
queue, and model systems are never read.
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
from pathlib import Path
from typing import Optional

from carrier_loop import CarrierInformationLoop

ALLOWED_TABLES = {
    "collections",
    "collection_metadata",
    "segments",
    "segment_metadata",
    "embedding_metadata",
    "embedding_metadata_array",
}


class RealPalaceSource:
    def __init__(self, snapshot_path: str, expected_sha256: str):
        self.path = Path(snapshot_path)
        self.expected_sha256 = expected_sha256.lower()
        self._verify_bytes()
        self.connection = sqlite3.connect(
            f"file:{self.path}?mode=ro&immutable=1", uri=True
        )
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA query_only=ON")
        self._validate()

    def _verify_bytes(self) -> None:
        digest = hashlib.sha256(self.path.read_bytes()).hexdigest()
        if digest != self.expected_sha256:
            raise ValueError("PALACE snapshot digest mismatch")

    def _validate(self) -> None:
        integrity = self.connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise ValueError("PALACE snapshot integrity failure")
        tables = {row[0] for row in self.connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        )}
        missing = ALLOWED_TABLES - tables
        if missing:
            raise ValueError(f"missing allowed tables: {sorted(missing)}")

    def close(self) -> None:
        self.connection.close()

    def first_metadata_records(self, count: int = 7) -> list[dict]:
        ids = [
            row[0] for row in self.connection.execute(
                "SELECT DISTINCT id FROM embedding_metadata ORDER BY id LIMIT ?",
                (count,),
            )
        ]
        records = []
        for internal_id in ids:
            rows = self.connection.execute(
                "SELECT key,string_value,int_value,float_value,bool_value "
                "FROM embedding_metadata WHERE id=? ORDER BY key",
                (internal_id,),
            ).fetchall()
            metadata = {}
            for row in rows:
                metadata[row["key"]] = {
                    "string": row["string_value"],
                    "int": row["int_value"],
                    "float": row["float_value"],
                    "bool": row["bool_value"],
                }
            records.append({
                "source": "REAL_PALACE_SNAPSHOT",
                "source_internal_id": internal_id,
                "metadata": metadata,
                "metadata_digest": hashlib.sha256(
                    json.dumps(metadata, ensure_ascii=False, sort_keys=True,
                               separators=(",", ":")).encode("utf-8")
                ).hexdigest(),
            })
        return records


class RealPalaceConsumptionLoop:
    def __init__(self, carrier: CarrierInformationLoop, source: RealPalaceSource):
        self.carrier = carrier
        self.source = source

    def materialize_sources(self, demand_id: str, count: int = 7) -> list[dict]:
        records = self.source.first_metadata_records(count)
        previous: Optional[str] = None
        for index, record in enumerate(records):
            item_id = f"REAL-{index + 1}"
            dependencies = [] if index == 0 else [f"REAL-{index}"]
            self.carrier.put_source(
                demand_id=demand_id,
                item_id=item_id,
                source_kind="REAL_PALACE_METADATA",
                source_version=record["metadata"]["last_modified"]["string"] or "unknown",
                source_payload=record,
                dependencies=dependencies,
            )
            previous = item_id
        return records

    def invalidate_settlement(self, item_id: str, reason: str) -> dict:
        return self.carrier.invalidate_settlement(item_id, reason)

    def execute_real_demand(
        self,
        demand_id: str,
        advancement_id: str,
        count: int = 7,
    ) -> dict:
        def deterministic_consumer(item_id, source_payload, dependencies):
            metadata = source_payload["metadata"]
            content = metadata.get("chroma:document", {})
            content_digest = content.get("sha256")
            if content_digest is None:
                content_digest = hashlib.sha256(b"").hexdigest()
            return {
                "item_id": item_id,
                "source_internal_id": source_payload["source_internal_id"],
                "content_sha256": content_digest,
                "metadata_digest": source_payload["metadata_digest"],
                "dependency_content_sha256es": {
                    key: value.get("content_sha256")
                    for key, value in dependencies.items()
                },
                "structural_record": {
                    "room": metadata.get("room", {}).get("string"),
                    "wing": metadata.get("wing", {}).get("string"),
                    "type": metadata.get("type", {}).get("string"),
                    "chunk_index": metadata.get("chunk_index", {}).get("int"),
                },
            }
        return self.carrier.execute_demand(
            demand_id, advancement_id, deterministic_consumer
        )
