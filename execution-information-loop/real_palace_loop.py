"""Read-only real PALACE structural source adapter for the D002-backed loop.

Only structural identity and metadata are read. Vector, full-text, queue and
model systems are never read.
"""
from __future__ import annotations

import hashlib
import json
import sqlite3
from pathlib import Path
from typing import Optional

from carrier_loop import CarrierInformationLoop, digest

ALLOWED_TABLES = {
    "collections",
    "collection_metadata",
    "segments",
    "segment_metadata",
    "embedding_metadata",
    "embedding_metadata_array",
    "embeddings",
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
        file_digest = hashlib.sha256(self.path.read_bytes()).hexdigest()
        if file_digest != self.expected_sha256:
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

    def _metadata_record(self, internal_id: int) -> dict:
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
        embedding = self.connection.execute(
            "SELECT segment_id,embedding_id FROM embeddings WHERE id=?",
            (internal_id,),
        ).fetchone()
        if embedding is None:
            raise ValueError(f"embedding row missing for metadata id {internal_id}")
        return {
            "source": "REAL_PALACE_SNAPSHOT",
            "record_kind": "EMBEDDING_METADATA",
            "source_internal_id": internal_id,
            "segment_id": embedding["segment_id"],
            "embedding_id": embedding["embedding_id"],
            "metadata": metadata,
            "metadata_digest": hashlib.sha256(
                json.dumps(metadata, ensure_ascii=False, sort_keys=True,
                           separators=(",", ":")).encode("utf-8")
            ).hexdigest(),
        }

    def structural_records(self, count: int = 7) -> dict:
        embedding_rows = self.connection.execute(
            "SELECT id,segment_id,embedding_id FROM embeddings "
            "WHERE id IN (SELECT DISTINCT id FROM embedding_metadata) "
            "ORDER BY id LIMIT ?",
            (count,),
        ).fetchall()
        if len(embedding_rows) != count:
            raise ValueError("requested real embedding count unavailable")
        segment_ids = {row["segment_id"] for row in embedding_rows}
        if len(segment_ids) != 1:
            raise ValueError(f"ambiguous real source segment: {sorted(segment_ids)}")
        segment_id = next(iter(segment_ids))
        segment = self.connection.execute(
            "SELECT s.id,s.type,s.scope,s.collection,"
            "c.id AS collection_id,c.name AS collection_name,c.dimension "
            "FROM segments s JOIN collections c ON c.id=s.collection "
            "WHERE s.id=?",
            (segment_id,),
        ).fetchone()
        if segment is None:
            raise ValueError(f"real source segment missing: {segment_id}")
        return {
            "collection": {
                "source": "REAL_PALACE_SNAPSHOT",
                "record_kind": "COLLECTION_SOURCE",
                "source_internal_id": segment["collection_id"],
                "payload": {
                    "collection_id": segment["collection_id"],
                    "name": segment["collection_name"],
                    "dimension": segment["dimension"],
                },
            },
            "segment": {
                "source": "REAL_PALACE_SNAPSHOT",
                "record_kind": "METADATA_SEGMENT_SOURCE",
                "source_internal_id": segment["id"],
                "payload": {
                    "segment_id": segment["id"],
                    "type": segment["type"],
                    "scope": segment["scope"],
                    "collection_id": segment["collection_id"],
                },
            },
            "embeddings": [self._metadata_record(row["id"]) for row in embedding_rows],
        }


class RealPalaceConsumptionLoop:
    def __init__(self, carrier: CarrierInformationLoop, source: RealPalaceSource):
        self.carrier = carrier
        self.source = source

    def materialize_sources(
        self,
        demand_id: str,
        count: int = 7,
        valid_until_utc: Optional[str] = None,
    ) -> list[dict]:
        source = self.source.structural_records(count)
        self.carrier.put_source(
            demand_id=demand_id,
            item_id="REAL-COLLECTION",
            source_kind="REAL_PALACE_COLLECTION",
            source_version=source["collection"]["source_internal_id"],
            source_payload=source["collection"],
            dependencies=[],
            valid_until_utc=valid_until_utc,
        )
        self.carrier.put_source(
            demand_id=demand_id,
            item_id="REAL-SEGMENT",
            source_kind="REAL_PALACE_SEGMENT",
            source_version=source["segment"]["source_internal_id"],
            source_payload=source["segment"],
            dependencies=["REAL-COLLECTION"],
            valid_until_utc=valid_until_utc,
        )
        records = source["embeddings"]
        item_by_parent: dict[str, str] = {}
        for index, record in enumerate(records):
            item_id = f"REAL-{index + 1}"
            dependencies = ["REAL-SEGMENT"]
            parent = record["metadata"].get("parent_drawer_id", {}).get("string")
            if parent and parent in item_by_parent:
                dependencies.append(item_by_parent[parent])
            self.carrier.put_source(
                demand_id=demand_id,
                item_id=item_id,
                source_kind="REAL_PALACE_METADATA",
                source_version=record["metadata"]["last_modified"]["string"] or "unknown",
                source_payload=record,
                dependencies=dependencies,
                valid_until_utc=valid_until_utc,
            )
            if parent:
                item_by_parent[parent] = item_id
        return records

    def invalidate_settlement(self, item_id: str, reason: str) -> dict:
        return self.carrier.invalidate_settlement(item_id, reason)

    def execute_real_demand(
        self,
        demand_id: str,
        advancement_id: str,
        count: int = 7,
        *,
        evaluated_at_utc: str,
    ) -> dict:
        def deterministic_consumer(item_id, source_payload, dependencies):
            payload_digest = digest(source_payload)
            if source_payload["record_kind"] != "EMBEDDING_METADATA":
                return {
                    "item_id": item_id,
                    "record_kind": source_payload["record_kind"],
                    "source_internal_id": source_payload["source_internal_id"],
                    "payload_digest": payload_digest,
                    "dependency_payload_digests": {
                        key: value.get("payload_digest")
                        for key, value in dependencies.items()
                    },
                }
            metadata = source_payload["metadata"]
            content = metadata.get("chroma:document", {})
            content_digest = content.get("sha256")
            if content_digest is None:
                content_digest = hashlib.sha256(b"").hexdigest()
            return {
                "item_id": item_id,
                "record_kind": source_payload["record_kind"],
                "source_internal_id": source_payload["source_internal_id"],
                "segment_id": source_payload["segment_id"],
                "embedding_id": source_payload["embedding_id"],
                "payload_digest": payload_digest,
                "content_sha256": content_digest,
                "metadata_digest": source_payload["metadata_digest"],
                "dependency_payload_digests": {
                    key: value.get("payload_digest")
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
            demand_id,
            advancement_id,
            deterministic_consumer,
            evaluated_at_utc=evaluated_at_utc,
        )
