#!/usr/bin/env python3
"""Archive-integrity checker for the state-layer migration.

Reads GOVERNANCE_DOC_MAP_20261020.csv and enforces one invariant:

    nothing outside docs/09-archive/ may reference an archived document by name

plus the mechanical checks that every KEEP_* document still sits at its original
path and every ARCHIVE_FOLD document is either still in place or present in the
archive.

Batch rule: ARCHIVE_FOLD documents still on disk form a frozen batch that will be
moved atomically later (the SRS / authorization line, held pending a human ruling
on Signer v0.7). A reference from one batch member to another is therefore safe
and is not a violation; a reference from outside the batch is.

The two state-layer pointer pages intentionally point at their own full copies
under docs/09-archive/state-layer/, so those two names are whitelisted.

Read-only. Exit code 0 = clean, 1 = violations found.

Usage:
    python3 docs/00-governance/state-layer-audit-20261020/verify_refs.py
"""

from __future__ import annotations

import csv
import os

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
GOV = os.path.join(REPO, "docs", "00-governance")
ARCHIVE = os.path.join(REPO, "docs", "09-archive")
AUDIT_DIR = os.path.dirname(os.path.abspath(__file__))
CSV_PATH = os.path.join(AUDIT_DIR, "GOVERNANCE_DOC_MAP_20261020.csv")
ARTIFACT_EXT = (".py", ".swift", ".sh", ".json", ".yml", ".yaml")
SKIP_DIRS = {".git", ".build", "__pycache__", "node_modules"}
WHITELIST = {
    "SESSION_CONTINUITY_20261008_FULL.md",
    "NEXT_SESSION_ENTRY_20261002_FULL.md",
}


def _read(path: str) -> str:
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            return fh.read()
    except OSError:
        return ""


def load_rows() -> list[dict[str, str]]:
    with open(CSV_PATH, encoding="utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh))


def _walk(suffixes: tuple[str, ...]) -> dict[str, str]:
    out: dict[str, str] = {}
    for dirpath, dirs, files in os.walk(REPO):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        if dirpath == ARCHIVE or dirpath.startswith(ARCHIVE + os.sep):
            continue
        if dirpath == AUDIT_DIR:
            continue
        for f in files:
            if f.endswith(suffixes):
                p = os.path.join(dirpath, f)
                out[p] = _read(p)
    return out


def find_in_archive(name: str) -> str | None:
    if not os.path.isdir(ARCHIVE):
        return None
    for dirpath, _dirs, files in os.walk(ARCHIVE):
        if name in files:
            return os.path.join(dirpath, name)
    return None


def main() -> int:
    rows = load_rows()
    md = _walk((".md",))
    artifacts = _walk(ARTIFACT_EXT)
    violations: list[str] = []

    # Members of the deferred batch: still on disk, scheduled to move together.
    frozen = {
        r["file"] for r in rows
        if r["disposition"] == "ARCHIVE_FOLD"
        and os.path.isfile(os.path.join(GOV, r["file"]))
    }

    def outside_batch(paths: list[str]) -> list[str]:
        return [p for p in paths if os.path.basename(p) not in frozen]

    for r in rows:
        name, disp = r["file"], r["disposition"]
        original = os.path.join(GOV, name)

        if disp.startswith("KEEP_"):
            if not os.path.isfile(original):
                violations.append(f"MISSING-KEEP: {name}")
            continue

        if name in WHITELIST:
            continue
        hits = outside_batch([p for p, t in md.items() if name in t])
        if hits:
            violations.append(
                f"FOLD-BUT-REFERENCED: {name} <- {len(hits)} doc(s), e.g. "
                f"{os.path.relpath(hits[0], REPO)}"
            )
        pinned = outside_batch([p for p, t in artifacts.items() if name in t])
        if pinned:
            violations.append(
                f"FOLD-BUT-ARTIFACT-REF: {name} <- {len(pinned)} artifact(s), e.g. "
                f"{os.path.relpath(pinned[0], REPO)}"
            )
        if not os.path.isfile(original) and not find_in_archive(name):
            violations.append(f"FOLDED-NO-DESTINATION: {name}")

    if violations:
        print(f"FAIL: {len(violations)} violation(s)")
        for v in violations[:40]:
            print("  -", v)
        if len(violations) > 40:
            print(f"  ... and {len(violations) - 40} more")
        return 1

    keep = sum(1 for r in rows if r["disposition"].startswith("KEEP_"))
    fold = sum(1 for r in rows if r["disposition"] == "ARCHIVE_FOLD")
    archived = fold - len(frozen)
    print(
        f"PASS: {keep} KEEP_* present, {fold} ARCHIVE_FOLD unreferenced "
        f"({archived} already archived, {len(frozen)} in frozen batch)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
