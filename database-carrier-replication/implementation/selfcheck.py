#!/usr/bin/env python3
"""Fail-closed storage selfcheck for the accepted database-backed IS carrier."""
from __future__ import annotations

import hashlib
import os
import sqlite3
import sys
import tempfile
from pathlib import Path

import db_is
from db_is import (
    DatabaseBackedIS,
    DatabaseCarrierError,
    MissingLogicalEntry,
    MissingObject,
    ObjectByteMismatch,
    schema_sql,
    required_tables,
)


def fail(message: str):
    raise AssertionError(message)


def main() -> int:
    checks = 0

    def ok(condition: bool, label: str):
        nonlocal checks
        checks += 1
        if not condition:
            fail(label)
        print(f"{checks:02d} PASS {label}")

    with tempfile.TemporaryDirectory(prefix="db-is-selfcheck-") as temp:
        path = os.path.join(temp, "is.sqlite")
        carrier = DatabaseBackedIS.init_empty(path)
        ok(carrier.connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "SQLite integrity")
        tables = {
            row[0] for row in carrier.connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name NOT LIKE 'sqlite_%'"
            )
        }
        ok(tables == set(required_tables()), "exact logical table set")

        d = b"D document"
        d_prime = b"D prime document"
        srs = b"SRS record bytes"
        continuation = b"continuation record bytes"

        object_id = carrier.write_object(d)
        ok(carrier.get_object(object_id) == d, "object write/read bytes")
        ok(carrier.write_object(d) == object_id, "same-byte object idempotence")
        ok(carrier.verify_object(object_id), "object hash verification")

        divergent = b"divergent object"
        divergent_id = hashlib.sha256(divergent).hexdigest()
        with carrier.transaction():
            carrier.connection.execute(
                "INSERT INTO is_objects "
                "(object_id, byte_size, content, created_order) VALUES "
                "(?, ?, ?, COALESCE((SELECT MAX(created_order) FROM is_objects), 0) + 1)",
                (divergent_id, len(divergent), b"corrupt bytes"),
            )
        try:
            carrier.get_object(divergent_id)
            ok(False, "divergent stored bytes must fail")
        except ObjectByteMismatch:
            ok(True, "divergent stored bytes rejected")

        try:
            carrier.get_object("0" * 64)
            ok(False, "missing object must fail")
        except MissingObject:
            ok(True, "missing object rejected")

        carrier.append_index_entry({
            "srs_identity": "srs-1",
            "record_object": object_id,
        })
        carrier.append_index_entry({
            "srs_identity": "srs-2",
            "record_object": object_id,
        })
        first = carrier.resolve_srs_identity("srs-1")
        second = carrier.resolve_srs_identity("srs-2")
        ok(first.record_object == object_id, "first-match SRS resolution")
        ok(second.append_order > first.append_order, "SRS append order preserved")

        carrier.append_dependency_entry({
            "dependency_id": "D-1",
            "content_address": object_id,
            "revision": 1,
            "reason": "initial",
        })
        carrier.append_dependency_entry({
            "dependency_id": "D-1",
            "content_address": object_id,
            "revision": 2,
            "reason": "advance",
        })
        current = carrier.resolve_current_dependency("D-1")
        history = carrier.dependency_history("D-1")
        ok(current.revision == 2 and current.reason == "advance", "LAST dependency current")
        ok(len(history) == 2 and history[0].revision == 1, "dependency history append-only")

        carrier.connection.execute("BEGIN IMMEDIATE")
        carrier.connection.execute(
            "INSERT INTO dependency_entries "
            "(append_order, dependency_id, content_address, revision, reason) VALUES "
            "(COALESCE((SELECT MAX(append_order) FROM dependency_entries), 0) + 1, "
            "'D-rollback', ?, 1, 'must rollback')",
            (object_id,),
        )
        carrier.connection.rollback()
        rows = carrier.connection.execute(
            "SELECT COUNT(*) FROM dependency_entries WHERE dependency_id = 'D-rollback'"
        ).fetchone()[0]
        ok(rows == 0, "failed logical group leaves no partial row")

        ok(
            not hasattr(carrier, "update_object")
            and not hasattr(carrier, "delete_object")
            and not hasattr(carrier, "rewrite_object"),
            "no carrier mutation API exposed",
        )
        source = Path(db_is.__file__).read_text(encoding="utf-8")
        ok("UPDATE is_objects" not in source, "no UPDATE logical-object SQL")
        ok("DELETE FROM is_objects" not in source, "no DELETE logical-object SQL")
        ok(
            "DELETE FROM dependency_entries" not in source,
            "no DELETE dependency-history SQL",
        )

        carrier.close()

        conn = sqlite3.connect(path)
        integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        tables = {
            row[0] for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name NOT LIKE 'sqlite_%'"
            )
        }
        conn.close()
        ok(integrity == "ok", "closed database integrity")
        ok(tables == set(required_tables()), "closed database logical table set")

    print(f"SELFcheck={checks}/{checks}_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
