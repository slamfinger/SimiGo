#!/usr/bin/env python3
"""G2 restore-eligibility gate.

Decides whether the settled result for one item may be restored from a carrier
database into a new Execution State. The gate touches the database read-only,
has no model import, launches no process and performs no network work, so a
refusal is always observable before any model load.

Frozen refusal codes (G2_PREREGISTRATION_20261020.md §7):
  SETTLEMENT_MISSING       settlement index entry, dependency entry or object gone
  OBJECT_DIGEST_MISMATCH   stored bytes no longer hash to the content address

Diagnostic codes exist for the other checks and are recorded per row; they never
replace the two frozen codes on the paths that use them.

Usage:
  python3 carrier_gate.py --db PATH --item ITEM --out RECORD.json \
      [--phase1-record RECORD.json] [--expect restored|refused]
"""

import argparse
import hashlib
import json
import os
import pathlib
import sqlite3
import sys

ROOT = pathlib.Path(__file__).resolve().parents[6]  # file -> batch -> g2 -> ... -> repo
sys.path.insert(0, str(ROOT / "execution-information-loop"))
sys.path.insert(0, str(ROOT / "database-carrier-replication" / "implementation"))

from carrier_loop import canonical, digest, validity_policy_identity  # noqa: E402
import db_is  # noqa: E402

SCHEMA_ID = "SIMIGO-G2-RESTORE-GATE-V1"
SETTLEMENT_MISSING = "SETTLEMENT_MISSING"
OBJECT_DIGEST_MISMATCH = "OBJECT_DIGEST_MISMATCH"


class Refusal(Exception):
    def __init__(self, code, detail, checks=None):
        super().__init__(detail)
        self.code = code
        self.detail = detail
        self.checks = checks or []


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def tree_digest(root):
    """Digest of every file under root: sha256 over sorted `<rel>:<sha256>`."""
    root = pathlib.Path(root)
    if root.is_file():
        return sha256_bytes(root.read_bytes())
    lines = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and not path.is_symlink():
            lines.append("%s:%s" % (path.relative_to(root).as_posix(),
                                    sha256_bytes(path.read_bytes())))
    return sha256_bytes("\n".join(lines).encode("utf-8"))


def connect_readonly(path):
    uri = pathlib.Path(path).resolve().as_uri() + "?mode=ro&immutable=1"
    connection = sqlite3.connect(uri, uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def check_schema(connection):
    present = {row["name"] for row in connection.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    expected = db_is.required_tables()
    missing = sorted(set(expected) - present)
    if missing:
        raise Refusal("SCHEMA_INVALID", "missing tables: %s" % missing)
    for table, columns in expected.items():
        actual = {row["name"] for row in connection.execute(
            "PRAGMA table_info(%s)" % table)}
        absent = sorted(columns - actual)
        if absent:
            raise Refusal("SCHEMA_INVALID", "%s missing columns %s" % (table, absent))


def latest_index(connection, identity):
    row = connection.execute(
        "SELECT append_order,srs_identity,record_object FROM is_index_entries "
        "WHERE srs_identity=? ORDER BY append_order DESC LIMIT 1",
        (identity,)).fetchone()
    return dict(row) if row else None


def latest_dependency(connection, dependency_id):
    row = connection.execute(
        "SELECT append_order,dependency_id,content_address,revision,reason "
        "FROM dependency_entries WHERE dependency_id=? "
        "ORDER BY append_order DESC LIMIT 1", (dependency_id,)).fetchone()
    return dict(row) if row else None


def read_object(connection, object_id):
    row = connection.execute(
        "SELECT object_id,byte_size,content FROM is_objects WHERE object_id=?",
        (object_id,)).fetchone()
    if row is None:
        return None
    return {"object_id": row["object_id"], "byte_size": row["byte_size"],
            "content": bytes(row["content"])}


def evaluate(db_path, item_id, phase1_record=None):
    """Run the frozen gate. Returns a record; never writes to the database."""
    checks = []

    def record(name, ok, detail=None, code=None):
        row = {"check": name, "ok": bool(ok)}
        if detail is not None:
            row["detail"] = detail
        if code is not None:
            row["code"] = code
        checks.append(row)
        if not ok:
            raise Refusal(code or "GATE_CHECK_FAILED", detail or name, checks)

    connection = connect_readonly(db_path)
    try:
        check_schema(connection)
        checks.append({"check": "schema", "ok": True})

        settlement_identity = "settlement:%s" % item_id
        index_entry = latest_index(connection, settlement_identity)
        record("settlement_index_present", index_entry is not None,
               "index entry %s" % settlement_identity, SETTLEMENT_MISSING)

        dependency = latest_dependency(connection, settlement_identity)
        record("settlement_dependency_present", dependency is not None,
               "dependency entry %s" % settlement_identity, SETTLEMENT_MISSING)

        object_id = index_entry["record_object"]
        record("settlement_pointer_agrees",
               dependency["content_address"] == object_id,
               "index=%s dependency=%s" % (object_id, dependency["content_address"]),
               OBJECT_DIGEST_MISMATCH)

        stored = read_object(connection, object_id)
        record("settlement_object_present", stored is not None,
               "object %s" % object_id, SETTLEMENT_MISSING)

        actual_digest = sha256_bytes(stored["content"])
        record("settlement_bytes_match_address", actual_digest == object_id,
               "computed=%s address=%s" % (actual_digest, object_id),
               OBJECT_DIGEST_MISMATCH)
        record("settlement_byte_size_matches", stored["byte_size"] == len(stored["content"]),
               "declared=%d actual=%d" % (stored["byte_size"], len(stored["content"])),
               OBJECT_DIGEST_MISMATCH)

        value = json.loads(stored["content"].decode("utf-8"))
        record("settlement_schema", value.get("schema_id") == "EINFO-SETTLEMENT-V1",
               str(value.get("schema_id")), "SETTLEMENT_NOT_SETTLED")
        record("settlement_state_settled", value.get("state") == "SETTLED",
               str(value.get("state")), "SETTLEMENT_NOT_SETTLED")

        result = value.get("result") or {}
        r1_canonical = result.get("r1_canonical")
        r1_sha = result.get("r1_sha256")
        recalculated = digest(json.loads(r1_canonical)) if r1_canonical else None
        record("r1_digest_matches_payload",
               r1_canonical is not None and recalculated == r1_sha,
               "recomputed=%s recorded=%s" % (recalculated, r1_sha),
               OBJECT_DIGEST_MISMATCH)

        if phase1_record is not None:
            record("r1_matches_phase1_record", r1_sha == phase1_record.get("r1_sha256"),
                   "gate=%s phase1=%s" % (r1_sha, phase1_record.get("r1_sha256")),
                   OBJECT_DIGEST_MISMATCH)
            record("r1_canonical_matches_phase1_record",
                   r1_canonical == phase1_record.get("r1_canonical"),
                   "canonical text byte-equal", OBJECT_DIGEST_MISMATCH)

        basis = value.get("basis") or {}
        source_identity = "item:%s" % item_id
        source_entry = latest_index(connection, source_identity)
        record("source_present", source_entry is not None,
               source_identity, "SOURCE_IDENTITY_MISMATCH")
        source_object = read_object(connection, source_entry["record_object"])
        record("source_bytes_match_address",
               source_object is not None
               and sha256_bytes(source_object["content"]) == source_object["object_id"],
               "source object %s" % source_entry["record_object"],
               "SOURCE_IDENTITY_MISMATCH")
        source_value = json.loads(source_object["content"].decode("utf-8"))
        record("source_object_identity_agrees",
               basis.get("source_item_object_id") == source_object["object_id"],
               "basis=%s current=%s" % (basis.get("source_item_object_id"),
                                        source_object["object_id"]),
               "SOURCE_IDENTITY_MISMATCH")
        record("source_version_agrees",
               basis.get("source_version") == source_value.get("source_version"),
               "basis=%s current=%s" % (basis.get("source_version"),
                                        source_value.get("source_version")),
               "SOURCE_IDENTITY_MISMATCH")

        closure = list(source_value.get("dependencies") or [])
        record("dependency_closure_agrees", sorted(closure) == sorted(
            basis.get("dependency_ids") or []),
               "current=%s basis=%s" % (closure, basis.get("dependency_ids")),
               "DEPENDENCY_CLOSURE_MISMATCH")
        resolved_closure = {}
        for dependency_id in closure:
            entry = latest_index(connection, "item:%s" % dependency_id)
            record("dependency_present:%s" % dependency_id, entry is not None,
                   "item:%s" % dependency_id, "DEPENDENCY_CLOSURE_MISMATCH")
            body = read_object(connection, entry["record_object"])
            record("dependency_bytes_match_address:%s" % dependency_id,
                   body is not None
                   and sha256_bytes(body["content"]) == body["object_id"],
                   entry["record_object"], "DEPENDENCY_CLOSURE_MISMATCH")
            record("dependency_object_agrees:%s" % dependency_id,
                   (basis.get("dependency_object_ids") or {}).get(dependency_id)
                   == body["object_id"],
                   "basis=%s current=%s"
                   % ((basis.get("dependency_object_ids") or {}).get(dependency_id),
                      body["object_id"]),
                   "DEPENDENCY_CLOSURE_MISMATCH")
            resolved_closure[dependency_id] = body["object_id"]

        policy = source_value.get("validity_policy")
        policy_identity = validity_policy_identity(policy)
        record("validity_policy_digest_agrees",
               policy_identity["policy_sha256"] == basis.get("validity_policy_sha256"),
               "current=%s basis=%s" % (policy_identity["policy_sha256"],
                                        basis.get("validity_policy_sha256")),
               "VALIDITY_BASIS_MISMATCH")
        record("validity_current", policy_identity["policy_version"]
               == basis.get("validity_policy_version"),
               "version %s" % policy_identity["policy_version"],
               "VALIDITY_BASIS_MISMATCH")

        demand_identity = "demand:%s" % source_value.get("demand_id")
        demand_entry = latest_index(connection, demand_identity)
        record("demand_present", demand_entry is not None, demand_identity,
               "DEMAND_MISMATCH")
        demand_value = json.loads(
            read_object(connection, demand_entry["record_object"])["content"])
        record("demand_requires_item", item_id in demand_value["required_item_ids"],
               "required=%s" % demand_value["required_item_ids"], "DEMAND_MISMATCH")

        return {
            "schema_id": SCHEMA_ID,
            "decision": "RESTORED",
            "code": None,
            "checks": checks,
            "all_checks_pass": True,
            "item_id": item_id,
            "settlement": {
                "object_id": object_id,
                "dependency_revision": dependency["revision"],
                "sha256": actual_digest,
                "byte_size": stored["byte_size"],
                "r1_canonical": r1_canonical,
                "r1_sha256": r1_sha,
            },
            "source": {
                "object_id": source_object["object_id"],
                "source_kind": source_value.get("source_kind"),
                "source_version": source_value.get("source_version"),
                "demand_id": source_value.get("demand_id"),
            },
            "dependency_closure": {"ids": closure, "object_ids": resolved_closure},
            "validity_basis": {
                "policy_sha256": policy_identity["policy_sha256"],
                "policy_version": policy_identity["policy_version"],
                "policy_source": policy_identity["policy_source"],
                "valid_until_utc": source_value.get("valid_until_utc"),
            },
            "model_loaded": False,
        }
    finally:
        connection.close()


def refused_record(code, detail, checks):
    return {
        "schema_id": SCHEMA_ID,
        "decision": "REFUSED",
        "code": code,
        "detail": detail,
        "checks": checks,
        "all_checks_pass": False,
        "model_loaded": False,
    }


def run_gate(db_path, item_id, phase1_record=None):
    before = tree_digest(db_path)
    try:
        body = evaluate(db_path, item_id, phase1_record=phase1_record)
    except Refusal as refusal:
        body = refused_record(refusal.code, refusal.detail, refusal.checks)
    except Exception as error:  # noqa: BLE001 - the gate must record any failure
        body = refused_record("GATE_ERROR", "%s: %s" % (type(error).__name__, error),
                              [])
    body["database"] = str(db_path)
    body["database_tree_digest_before"] = before
    body["database_tree_digest_after"] = tree_digest(db_path)
    body["database_unchanged"] = (
        body["database_tree_digest_before"] == body["database_tree_digest_after"])
    return body


def write_once(path, payload):
    with open(path, "x", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--item", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--phase1-record")
    parser.add_argument("--expect", choices=["restored", "refused"], default=None)
    args = parser.parse_args()

    phase1 = None
    if args.phase1_record:
        phase1 = json.loads(pathlib.Path(args.phase1_record).read_text(encoding="utf-8"))
        phase1 = {"r1_canonical": phase1.get("r1_canonical"),
                  "r1_sha256": phase1.get("r1_sha256")}

    body = run_gate(args.db, args.item, phase1)
    body["expectation"] = args.expect
    body["expectation_met"] = (
        None if args.expect is None
        else (body["decision"] == "RESTORED") == (args.expect == "restored"))
    body["pid"] = os.getpid()
    write_once(args.out, body)
    print(json.dumps({"decision": body["decision"], "code": body["code"]}))
    if args.expect and not body["expectation_met"]:
        sys.exit(4)
    sys.exit(0)


if __name__ == "__main__":
    main()
