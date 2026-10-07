#!/usr/bin/env python3
"""Database-backed IS carrier for SRS-REAL-CLOSURE-01.

This module implements the interface/schema accepted by Database-Carrier
Replication Design Package v0.1. It is a storage carrier only: it provides no
experiment semantics, no equivalence judgment, and no campaign orchestration.
"""
from __future__ import annotations

import contextlib
import hashlib
import os
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


_SCHEMA_SQL = """
CREATE TABLE is_objects (
    object_id TEXT PRIMARY KEY,
    byte_size INTEGER NOT NULL,
    content BLOB NOT NULL,
    created_order INTEGER NOT NULL UNIQUE,
    CHECK(length(object_id) = 64),
    CHECK(object_id = lower(object_id)),
    CHECK(byte_size >= 0),
    CHECK(created_order > 0)
);

CREATE TABLE is_index_entries (
    append_order INTEGER PRIMARY KEY,
    srs_identity TEXT NOT NULL,
    record_object TEXT NOT NULL REFERENCES is_objects(object_id)
);

CREATE TABLE dependency_entries (
    append_order INTEGER PRIMARY KEY,
    dependency_id TEXT NOT NULL,
    content_address TEXT NOT NULL REFERENCES is_objects(object_id),
    revision INTEGER NOT NULL CHECK(revision > 0),
    reason TEXT NOT NULL
);
"""

_REQUIRED_TABLES = {
    "is_objects": {
        "object_id", "byte_size", "content", "created_order",
    },
    "is_index_entries": {
        "append_order", "srs_identity", "record_object",
    },
    "dependency_entries": {
        "append_order", "dependency_id", "content_address", "revision",
        "reason",
    },
}

_LOGICAL_TABLES = frozenset(_REQUIRED_TABLES)


class DatabaseCarrierError(RuntimeError):
    """Base error for violations of the accepted database-backed IS contract."""


class ObjectByteMismatch(DatabaseCarrierError):
    """An existing object_id was presented with different object bytes."""


class MissingObject(DatabaseCarrierError):
    """A required object_id does not exist."""


class MissingLogicalEntry(DatabaseCarrierError):
    """A required logical entry does not exist."""


class InvalidEntry(DatabaseCarrierError):
    """An entry violates the accepted append-only interface."""


@dataclass(frozen=True)
class ObjectRecord:
    object_id: str
    byte_size: int
    content: bytes
    created_order: int


@dataclass(frozen=True)
class IndexRecord:
    append_order: int
    srs_identity: str
    record_object: str


@dataclass(frozen=True)
class DependencyRecord:
    append_order: int
    dependency_id: str
    content_address: str
    revision: int
    reason: str


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def schema_sql() -> str:
    """Return the exact accepted schema DDL."""
    return _SCHEMA_SQL


def required_tables() -> dict[str, set[str]]:
    """Return the accepted logical tables and required columns."""
    return {name: set(cols) for name, cols in _REQUIRED_TABLES.items()}


class DatabaseBackedIS:
    """A database-backed IS storage carrier.

    No experiment semantics are implemented here. All mutations are append-only
    at the logical interface; UPDATE and DELETE statements are denied by this
    connection's authorizer.
    """

    def __init__(self, database_path: str | os.PathLike[str]):
        self.database_path = os.fspath(database_path)
        self._transaction_depth = 0
        self.connection = sqlite3.connect(self.database_path)
        self.connection.row_factory = sqlite3.Row
        self.connection.execute("PRAGMA foreign_keys = ON")
        self.connection.set_authorizer(self._authorizer)

    def _authorizer(
        self,
        action: int,
        arg1: str | None,
        arg2: str | None,
        database_name: str | None,
        trigger_name: str | None,
    ) -> int:
        # SQLite action codes used here:
        # DELETE=9, UPDATE=23, ALTER_TABLE=29, DROP_TABLE=32.
        if action not in (9, 23, 29, 32):
            return sqlite3.SQLITE_OK
        names = {str(arg1 or ""), str(arg2 or "")}
        if names & _LOGICAL_TABLES:
            return sqlite3.SQLITE_DENY
        return sqlite3.SQLITE_OK

    @classmethod
    def init_empty(cls, database_path: str | os.PathLike[str]) -> "DatabaseBackedIS":
        path = Path(database_path)
        if path.exists() or path.is_symlink():
            raise FileExistsError(f"database already exists: {path}")
        path.parent.mkdir(parents=True, exist_ok=True)
        carrier = cls(path)
        carrier.connection.executescript(_SCHEMA_SQL)
        carrier.connection.commit()
        carrier.validate_schema()
        return carrier

    def close(self) -> None:
        self.connection.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()

    @contextlib.contextmanager
    def transaction(self) -> Iterator[None]:
        """Provide one atomic logical write group."""
        self.connection.execute("BEGIN IMMEDIATE")
        self._transaction_depth += 1
        try:
            yield
        except BaseException:
            self.connection.rollback()
            raise
        else:
            self.connection.commit()
        finally:
            self._transaction_depth -= 1

    @contextlib.contextmanager
    def atomic_write_group(self) -> Iterator[None]:
        """Compose multiple append-only writes as one atomic logical group.

        Reentrant use joins the surrounding accepted logical write group.
        """
        if self._transaction_depth:
            yield
            return
        with self.transaction():
            yield

    def validate_schema(self) -> None:
        rows = self.connection.execute(
            "SELECT name, sql FROM sqlite_master "
            "WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        ).fetchall()
        actual = {row["name"]: row for row in rows}
        if set(actual) != set(_REQUIRED_TABLES):
            raise DatabaseCarrierError(
                f"schema table mismatch: {sorted(actual)}"
            )
        for table, required in _REQUIRED_TABLES.items():
            info = self.connection.execute(f"PRAGMA table_info({table})").fetchall()
            columns = {row["name"] for row in info}
            if not required.issubset(columns):
                raise DatabaseCarrierError(
                    f"schema column mismatch for {table}: {sorted(columns)}"
                )
        result = self.connection.execute("PRAGMA integrity_check").fetchone()
        if result is None or result[0] != "ok":
            raise DatabaseCarrierError("SQLite integrity_check failed")

    def _next_append_order(self, table: str) -> int:
        row = self.connection.execute(
            f"SELECT COALESCE(MAX(append_order), 0) + 1 FROM {table}"
        ).fetchone()
        return int(row[0])

    def _next_created_order(self) -> int:
        row = self.connection.execute(
            "SELECT COALESCE(MAX(created_order), 0) + 1 FROM is_objects"
        ).fetchone()
        return int(row[0])

    def write_object(self, content: bytes) -> str:
        if not isinstance(content, bytes):
            raise TypeError("object content must be bytes")
        object_id = sha256_hex(content)
        byte_size = len(content)
        with self.atomic_write_group():
            self._write_object_in_txn(content, object_id, byte_size)
        return object_id

    def _write_object_in_txn(self, content: bytes, object_id: str, byte_size: int):
        existing = self.connection.execute(
            "SELECT content FROM is_objects WHERE object_id = ?",
            (object_id,),
        ).fetchone()
        if existing is not None:
            stored = bytes(existing["content"])
            if stored != content:
                raise ObjectByteMismatch(object_id)
            return
        created_order = self._next_created_order()
        self.connection.execute(
            "INSERT INTO is_objects "
            "(object_id, byte_size, content, created_order) VALUES (?, ?, ?, ?)",
            (object_id, byte_size, content, created_order),
        )

    def atomic_dependency_materialization(
        self,
        content: bytes,
        dependency_entry: Mapping[str, object],
    ) -> tuple[str, int]:
        """Write one D/D' object and dependency mapping as one atomic group."""
        if not isinstance(content, bytes):
            raise TypeError("object content must be bytes")
        object_id = sha256_hex(content)
        with self.atomic_write_group():
            self._write_object_in_txn(content, object_id, len(content))
            append_order = self._append_dependency_in_txn(
                dependency_entry, content_address=object_id
            )
        return object_id, append_order

    def get_object(self, object_id: str) -> bytes:
        row = self.connection.execute(
            "SELECT content FROM is_objects WHERE object_id = ?",
            (object_id,),
        ).fetchone()
        if row is None:
            raise MissingObject(object_id)
        content = bytes(row["content"])
        if sha256_hex(content) != object_id:
            raise ObjectByteMismatch(object_id)
        return content

    def verify_object(self, object_id: str) -> bool:
        try:
            content = self.get_object(object_id)
        except MissingObject:
            return False
        return sha256_hex(content) == object_id

    def object_record(self, object_id: str) -> ObjectRecord:
        row = self.connection.execute(
            "SELECT object_id, byte_size, content, created_order "
            "FROM is_objects WHERE object_id = ?",
            (object_id,),
        ).fetchone()
        if row is None:
            raise MissingObject(object_id)
        return ObjectRecord(
            object_id=row["object_id"],
            byte_size=int(row["byte_size"]),
            content=bytes(row["content"]),
            created_order=int(row["created_order"]),
        )

    def append_index_entry(self, entry: Mapping[str, object]) -> int:
        if set(entry) != {"srs_identity", "record_object"}:
            raise InvalidEntry("index entry fields do not match accepted contract")
        srs_identity = entry["srs_identity"]
        record_object = entry["record_object"]
        if not isinstance(srs_identity, str) or not srs_identity:
            raise InvalidEntry("srs_identity must be a nonempty string")
        if not isinstance(record_object, str) or len(record_object) != 64:
            raise InvalidEntry("record_object must be a 64-character object id")
        with self.atomic_write_group():
            append_order = self._append_index_in_txn(srs_identity, record_object)
        return append_order

    def _append_index_in_txn(self, srs_identity: str, record_object: str) -> int:
        if self.connection.execute(
            "SELECT 1 FROM is_objects WHERE object_id = ?",
            (record_object,),
        ).fetchone() is None:
            raise MissingObject(record_object)
        append_order = self._next_append_order("is_index_entries")
        self.connection.execute(
            "INSERT INTO is_index_entries "
            "(append_order, srs_identity, record_object) VALUES (?, ?, ?)",
            (append_order, srs_identity, record_object),
        )
        return append_order

    def resolve_srs_identity(self, srs_identity: str) -> IndexRecord:
        row = self.connection.execute(
            "SELECT append_order, srs_identity, record_object "
            "FROM is_index_entries "
            "WHERE srs_identity = ? "
            "ORDER BY append_order ASC LIMIT 1",
            (srs_identity,),
        ).fetchone()
        if row is None:
            raise MissingLogicalEntry(srs_identity)
        return IndexRecord(
            append_order=int(row["append_order"]),
            srs_identity=row["srs_identity"],
            record_object=row["record_object"],
        )

    def index_entries(self) -> list[IndexRecord]:
        rows = self.connection.execute(
            "SELECT append_order, srs_identity, record_object "
            "FROM is_index_entries ORDER BY append_order ASC"
        ).fetchall()
        return [
            IndexRecord(
                append_order=int(row["append_order"]),
                srs_identity=row["srs_identity"],
                record_object=row["record_object"],
            )
            for row in rows
        ]

    def append_dependency_entry(self, entry: Mapping[str, object]) -> int:
        required = {"dependency_id", "content_address", "revision", "reason"}
        if set(entry) != required:
            raise InvalidEntry("dependency entry fields do not match accepted contract")
        dependency_id = entry["dependency_id"]
        content_address = entry["content_address"]
        revision = entry["revision"]
        reason = entry["reason"]
        if not isinstance(dependency_id, str) or not dependency_id:
            raise InvalidEntry("dependency_id must be a nonempty string")
        if not isinstance(content_address, str) or len(content_address) != 64:
            raise InvalidEntry("content_address must be a 64-character object id")
        if isinstance(revision, bool) or not isinstance(revision, int) or revision <= 0:
            raise InvalidEntry("revision must be a positive integer")
        if not isinstance(reason, str) or not reason:
            raise InvalidEntry("reason must be a nonempty string")
        with self.atomic_write_group():
            append_order = self._append_dependency_in_txn(
                entry, content_address=content_address
            )
        return append_order

    def _append_dependency_in_txn(
        self,
        entry: Mapping[str, object],
        *,
        content_address: str,
    ) -> int:
        dependency_id = entry["dependency_id"]
        revision = entry["revision"]
        reason = entry["reason"]
        if self.connection.execute(
            "SELECT 1 FROM is_objects WHERE object_id = ?",
            (content_address,),
        ).fetchone() is None:
            raise MissingObject(content_address)
        append_order = self._next_append_order("dependency_entries")
        self.connection.execute(
            "INSERT INTO dependency_entries "
            "(append_order, dependency_id, content_address, revision, reason) "
            "VALUES (?, ?, ?, ?, ?)",
            (append_order, dependency_id, content_address, revision, reason),
        )
        return append_order

    def resolve_current_dependency(
        self, dependency_id: str
    ) -> DependencyRecord:
        row = self.connection.execute(
            "SELECT append_order, dependency_id, content_address, revision, reason "
            "FROM dependency_entries "
            "WHERE dependency_id = ? "
            "ORDER BY append_order DESC LIMIT 1",
            (dependency_id,),
        ).fetchone()
        if row is None:
            raise MissingLogicalEntry(dependency_id)
        return DependencyRecord(
            append_order=int(row["append_order"]),
            dependency_id=row["dependency_id"],
            content_address=row["content_address"],
            revision=int(row["revision"]),
            reason=row["reason"],
        )

    def get_dependency_history(self, dependency_id: str) -> list[DependencyRecord]:
        rows = self.connection.execute(
            "SELECT append_order, dependency_id, content_address, revision, reason "
            "FROM dependency_entries "
            "WHERE dependency_id = ? ORDER BY append_order ASC",
            (dependency_id,),
        ).fetchall()
        return [
            DependencyRecord(
                append_order=int(row["append_order"]),
                dependency_id=row["dependency_id"],
                content_address=row["content_address"],
                revision=int(row["revision"]),
                reason=row["reason"],
            )
            for row in rows
        ]

    def dependency_history(self, dependency_id: str) -> list[DependencyRecord]:
        """Compatibility alias for get_dependency_history."""
        return self.get_dependency_history(dependency_id)
