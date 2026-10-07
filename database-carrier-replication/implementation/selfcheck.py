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
        ok(carrier.get_dependency_history("none") == [], "canonical dependency-history API")

        d = b"D document"
        d_prime = b"D prime document"
        object_id = carrier.write_object(d)
        ok(carrier.get_object(object_id) == d, "object write/read bytes")
        ok(carrier.write_object(d) == object_id, "same-byte object idempotence")
        ok(carrier.verify_object(object_id), "object hash verification")

        divergent_id = hashlib.sha256(b"divergent").hexdigest()
        with carrier.atomic_write_group():
            carrier._write_object_in_txn(
                b"corrupt bytes", divergent_id, len(b"corrupt bytes")
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

        before_objects = carrier.connection.execute(
            "SELECT COUNT(*) FROM is_objects"
        ).fetchone()[0]
        try:
            with carrier.atomic_write_group():
                carrier.append_dependency_entry({
                    "dependency_id": "D-bad",
                    "content_address": "f" * 64,
                    "revision": 9,
                    "reason": "missing object",
                })
            ok(False, "failed logical group must raise")
        except MissingObject:
            ok(True, "failed logical group raised")
        count = carrier.connection.execute(
            "SELECT COUNT(*) FROM dependency_entries WHERE dependency_id='D-bad'"
        ).fetchone()[0]
        after_objects = carrier.connection.execute(
            "SELECT COUNT(*) FROM is_objects"
        ).fetchone()[0]
        ok(count == 0, "failed dependency append exposed none")
        ok(before_objects == after_objects, "failed group exposed no object")

        with carrier.atomic_write_group():
            dep_order = carrier.append_dependency_entry({
                "dependency_id": "D-1",
                "content_address": object_id,
                "revision": 1,
                "reason": "initial",
            })
            idx_order = carrier.append_index_entry({
                "srs_identity": "srs-1",
                "record_object": object_id,
            })
        current = carrier.resolve_current_dependency("D-1")
        history = carrier.get_dependency_history("D-1")
        alias = carrier.dependency_history("D-1")
        ok(current.revision == 1 and current.reason == "initial", "committed dependency current")
        ok(len(history) == 1 and history[0].revision == 1, "canonical dependency history")
        ok(alias == history, "compatibility alias has same behavior")
        with carrier.atomic_write_group():
            carrier.append_dependency_entry({
                "dependency_id": "D-1",
                "content_address": object_id,
                "revision": 2,
                "reason": "advance",
            })
        current = carrier.resolve_current_dependency("D-1")
        history = carrier.get_dependency_history("D-1")
        ok(current.revision == 2 and len(history) == 2, "nested transaction-safe append")

        try:
            carrier.connection.execute(
                "UPDATE is_objects SET content = X'00' WHERE object_id = ?",
                (object_id,),
            )
            ok(False, "UPDATE committed logical object must be denied")
        except sqlite3.DatabaseError:
            ok(True, "UPDATE committed logical object denied by authorizer")

        try:
            carrier.connection.execute(
                "DELETE FROM dependency_entries WHERE dependency_id = 'D-1'"
            )
            ok(False, "DELETE committed dependency history must be denied")
        except sqlite3.DatabaseError:
            ok(True, "DELETE committed dependency history denied by authorizer")

        try:
            carrier.connection.execute("DROP TABLE dependency_entries")
            ok(False, "DROP committed logical table must be denied")
        except sqlite3.DatabaseError:
            ok(True, "DROP committed logical table denied by authorizer")

        carrier.close()
        conn = sqlite3.connect(path)
        integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        dep_count = conn.execute(
            "SELECT COUNT(*) FROM dependency_entries WHERE dependency_id='D-1' "
            "AND revision=1"
        ).fetchone()[0]
        conn.close()
        ok(integrity == "ok", "closed database integrity")
        ok(dep_count == 1, "committed dependency row remained after authorizer tests")
        ok(tables == set(required_tables()), "closed database logical table set")

    print(f"SELFcheck={checks}/{checks}_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
