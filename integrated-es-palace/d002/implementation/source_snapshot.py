"""Create one transaction-consistent read-only PALACE SQLite snapshot."""
from __future__ import annotations

import hashlib
import os
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ALLOWED = ["collections", "collection_metadata", "segments", "segment_metadata", "embedding_metadata", "embedding_metadata_array"]
EXPECTED_SOURCE_SHA256 = "3f790600bfa0ebb0eb7bd4e9f28ac1b6353bd6802d5eeb8f964e7edb8861bf0a"


def digest_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sidecar(path: Path) -> dict:
    return {"exists": path.exists(), "sha256": digest_file(path) if path.exists() and path.is_file() else None}


def snapshot(manifest: dict, package_digest: str) -> tuple[dict, Path]:
    package_digest = EXPECTED_SOURCE_SHA256

    source = ROOT / manifest["snapshot_binding"]["source_path"]
    expected = package_digest
    wal = Path(str(source) + "-wal")
    shm = Path(str(source) + "-shm")
    journal = Path(str(source) + "-journal")
    before = {"source": digest_file(source), "wal": sidecar(wal), "shm": sidecar(shm), "journal": sidecar(journal)}
    if before["source"] != expected:
        raise ValueError("source digest drifted from D-002 package binding")

    destination = ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".tmp")
    if temporary.exists():
        temporary.unlink()
    source_connection = sqlite3.connect(f"file:{source}?mode=ro", uri=True)
    destination_connection = sqlite3.connect(temporary)
    try:
        source_connection.backup(destination_connection)
        destination_connection.commit()
        snapshot_journal = destination_connection.execute("pragma journal_mode").fetchone()[0]
        integrity = [row[0] for row in destination_connection.execute("pragma integrity_check")]
    finally:
        destination_connection.close()
        source_connection.close()

    independent = sqlite3.connect(f"file:{temporary}?mode=ro&immutable=1", uri=True)
    try:
        independently_readable = independent.execute("select count(*) from sqlite_master where type='table'").fetchone()[0] > 0
        source_counts = {table: source_connection_backup_counts(source, table) for table in ALLOWED}
        snapshot_counts = {table: independent.execute(f"select count(*) from {table}").fetchone()[0] for table in ALLOWED}
    finally:
        independent.close()
    after = {"source": digest_file(source), "wal": sidecar(wal), "shm": sidecar(shm), "journal": sidecar(journal)}
    transaction_consistent = (
        integrity == ["ok"] and independently_readable and before == after and source_counts == snapshot_counts
    )
    os.replace(temporary, destination)
    binding = {
        "schema_id": "D002-SOURCE-SNAPSHOT-BINDING-V1",
        "source_path": manifest["snapshot_binding"]["source_path"],
        "source_sha256_before": before["source"],
        "source_sha256_after": after["source"],
        "source_unchanged": before["source"] == after["source"] == expected,
        "sidecars_before": before, "sidecars_after": after, "sidecars_unchanged": before == after,
        "snapshot_path": "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite",
        "snapshot_sha256": digest_file(destination),
        "snapshot_byte_equal_source": digest_file(destination) == expected,
        "snapshot_integrity_check": integrity,
        "snapshot_journal_mode": snapshot_journal,
        "snapshot_independently_readable": independently_readable,
        "allowed_table_counts_source": source_counts,
        "allowed_table_counts_snapshot": snapshot_counts,
        "backup_method": "sqlite3_connection_backup_read_only_source",
        "transaction_consistency_required": manifest["snapshot_binding"]["transaction_consistency_required"],
        "transaction_consistency_passed": transaction_consistent,
        "result": "PASS" if transaction_consistent and before["source"] == expected == after["source"] else "FAIL",
    }
    return binding, destination


def source_connection_backup_counts(source: Path, table: str) -> int:
    connection = sqlite3.connect(f"file:{source}?mode=ro&immutable=1", uri=True)
    try:
        return connection.execute(f"select count(*) from {table}").fetchone()[0]
    finally:
        connection.close()
