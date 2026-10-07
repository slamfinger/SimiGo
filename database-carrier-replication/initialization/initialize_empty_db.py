#!/usr/bin/env python3
"""Initialize one auditable empty database-backed IS.

This tool creates only the accepted empty schema. It never inserts logical IS
rows, performs logical import, or authorizes a campaign.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

IMPLEMENTATION_DIR = Path(__file__).resolve().parent.parent / "implementation"
sys.path.insert(0, str(IMPLEMENTATION_DIR))

from db_is import DatabaseBackedIS  # noqa: E402


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def git_output(*args: str) -> str:
    repo = IMPLEMENTATION_DIR.parent.parent
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "output",
        nargs="?",
        default=str(Path(__file__).resolve().parent / "empty_is.sqlite"),
    )
    args = parser.parse_args()
    output = Path(args.output).resolve()
    if output.exists() or output.is_symlink():
        raise FileExistsError(f"refusing to overwrite: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)

    implementation_files = [
        IMPLEMENTATION_DIR / "db_is.py",
        IMPLEMENTATION_DIR / "schema.sql",
        IMPLEMENTATION_DIR / "selfcheck.py",
        IMPLEMENTATION_DIR / "README.md",
    ]
    artifact_hashes = {
        str(p.relative_to(IMPLEMENTATION_DIR)): sha256_file(p)
        for p in implementation_files
    }

    carrier = DatabaseBackedIS.init_empty(output)
    integrity = carrier.connection.execute("PRAGMA integrity_check").fetchone()[0]
    if integrity != "ok":
        raise RuntimeError("SQLite integrity_check failed")
    tables = {
        row[0] for row in carrier.connection.execute(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )
    }
    expected = {"is_objects", "is_index_entries", "dependency_entries"}
    if tables != expected:
        raise RuntimeError(f"schema table mismatch: {sorted(tables)}")
    counts = {
        table: carrier.connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        for table in sorted(expected)
    }
    if any(counts.values()):
        raise RuntimeError("initialized database is not empty")
    carrier.close()

    implementation_commit = git_output("rev-parse", "HEAD")
    manifest = {
        "manifest_identity": "DATABASE_IS_EMPTY_INITIALIZATION_MANIFEST_005",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "exact_execution_repository_commit": implementation_commit,
        "database_path": str(output),
        "database_sha256": sha256_file(output),
        "database_byte_size": output.stat().st_size,
        "engine": {
            "python_version": platform.python_version(),
            "sqlite_version": sqlite3.sqlite_version,
            "platform": platform.platform(),
        },
        "implementation_artifact_sha256": artifact_hashes,
        "logical_row_counts": counts,
        "logical_import": False,
        "campaign_state": "NOT_AUTHORIZED",
    }
    manifest_path = output.parent / "INITIALIZATION_MANIFEST.json"
    manifest_path.write_text(
        json.dumps(manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    print(f"initialized empty database-backed IS: {output}")
    print(f"manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
