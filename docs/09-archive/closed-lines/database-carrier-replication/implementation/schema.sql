-- SRS-REAL-CLOSURE-01 database-backed IS logical stores.
-- This schema contains no experiment semantics and no carrier-specific
-- decision input. The API enforces immutability and append-only behavior.
PRAGMA foreign_keys = ON;

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
