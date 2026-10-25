"""Write-once Carrier persistence and verification; no semantic authority."""
from __future__ import annotations

import hashlib
import sqlite3
from pathlib import Path

from schemas import canonical_bytes


def persist_records(path: Path, records: list[dict]) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    try:
        connection.execute("CREATE TABLE evidence (record_key TEXT PRIMARY KEY, canonical_json BLOB NOT NULL, sha256 TEXT NOT NULL)")
        for record in records:
            payload = canonical_bytes(record)
            record_hash = hashlib.sha256(payload).hexdigest()
            try:
                connection.execute("INSERT INTO evidence VALUES (?, ?, ?)", (record["record_key"], payload, record_hash))
            except sqlite3.IntegrityError as exc:
                return {"state": "PERSIST_FAILED", "error": str(exc), "record_key": record["record_key"]}
        connection.commit()
        for record in records:
            row = connection.execute("SELECT canonical_json, sha256 FROM evidence WHERE record_key = ?", (record["record_key"],)).fetchone()
            if row is None or row[0] != canonical_bytes(record) or row[1] != hashlib.sha256(row[0]).hexdigest():
                return {"state": "POST_WRITE_CHECK_FAILED", "record_key": record["record_key"]}
    finally:
        connection.close()
    return {"state": "PERSISTED", "database_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "record_count": len(records)}
