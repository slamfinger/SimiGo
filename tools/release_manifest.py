#!/usr/bin/env python3
"""Derive and check the versioned release-input manifest and the exclusion register.

Two documents are produced from the tracked tree and nothing else:

* `release/release-inputs-v2.2.x.json` -- the per-file deliverable inputs, each entry
  exactly `{path, output}` so it can be handed straight to `release_sanitize.py build`;
* `release/release-exclusions-v2.2.x.json` -- every candidate that leaves the input set,
  one record per file with its path, SHA-256, reason, file type, repository-scan status
  and whether the reason applies to future releases.

Three properties are enforced rather than intended:

* **No directory glob.** A candidate is either declared or has its own record; a wildcard
  in either document is a check failure, so a whole directory can never be dropped by
  a rule that names no file.
* **The candidate set is fully accounted.** `declared + excluded == candidates`;
  `check` re-derives from `git ls-files` and fails on any non-`research/` tracked file
  that is in neither document. That is the completeness layer: a newly added file breaks
  staging acceptance until someone classifies it on purpose.
* **Exclusion is not a privacy claim.** Each record states whether the repository audit
  covers the file and what that coverage can see, including the blind spots that were
  measured rather than assumed. `research/` is absent from the deliverable because the
  deliverable is the product tree; it is not exempted from scanning, and the exclusion
  register stays silent about research files -- `check` reports them by count.

The documents are static, and that is a property rather than a style. Nothing in them
names a commit, a tree, a build time or an aggregate of the deliverable: a manifest that
described the round that wrote it would either go stale on the next cut or, worse, let a
stale file be presented as provenance for bytes this round never built. Those readings
belong to the provenance sidecar `release_chain.py` writes next to each staging tree,
where they can only ever describe the tree they were taken from. `check` enforces this
by refusing any key outside the fixed schema, so re-adding a self-referential field is
a failure and not a silent drift.

No count of the tree is committed either, and that is a merge property rather than
tidiness. Git merges two branches that both edited these documents by taking the union of
the two file lists -- correct, because both authors' files belong in the result -- and by
picking one side of every scalar. A committed aggregate is therefore the one thing a clean
textual merge can quietly desynchronise: `main` went stale exactly that way after a PR
whose own CI was green. With nothing but paths in the documents, the union of two true
lists is true, and every count lives in `check`'s output where it describes the tree it
was just measured on.

`build` and `gate` are unchanged: this tool only fixes the input set in version control
and proves the register is complete. The scan rules live in `release_artifact_audit.py`,
`png_text_chunks.py` and `release_sanitize.py` and are imported here, never restated.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import png_text_chunks  # noqa: E402
from release_artifact_audit import (  # noqa: E402
    SKIP_FILES,
    scan_file,
)

RULES = "release-manifest-2026-11-01.2"
MANIFEST_VERSION = 1
RELEASE_BRANCH = "v2.2.x"
RESEARCH_PREFIX = "research/"

INPUTS_FILE = "release/release-inputs-v2.2.x.json"
EXCLUSIONS_FILE = "release/release-exclusions-v2.2.x.json"

INPUTS_KEYS = frozenset({"manifest_version", "rules", "release_branch",
                         "directory_globs_used", "sources"})
EXCLUSIONS_KEYS = frozenset({"manifest_version", "rules", "release_branch",
                             "record_fields", "excluded"})
# Names that belong to a provenance sidecar, never to a versioned manifest. Refused
# wherever they appear, so the static documents cannot re-acquire a self-reference.
DYNAMIC_PROVENANCE_FIELDS = frozenset({
    "git_head", "git_tree", "source_commit", "source_tree", "generated_from",
    "generated_at", "build_time", "built_at", "timestamp", "staging_digest",
    "deliverable_digest", "aggregate", "aggregate_sha256", "manifest_sha256",
    "inputs_manifest_sha256", "exclusions_manifest_sha256", "sanitizer_sha256",
    "audit_engine_sha256", "ci_run",
})


# Reasons carried over verbatim from the round that measured them; the text is the
# record, so re-deriving must not paraphrase it.
RULE_CARRIER_REASONS = {
    "tools/open_source_audit.sh": "audit rule carrier: its split literals are the scan patterns",
    "tools/release_artifact_audit.py": "audit rule carrier: redaction would rewrite FORBIDDEN",
    "tools/release_sanitize.py": "rule carrier: the temp-path rule rewrites its own pattern",
    "tools/test_release_sanitize.py": "rule carrier: the temp-path rule guts its fixture",
}
NON_UTF8_REASON = "non-UTF-8 source: redaction of it cannot be proven"
# A line that tells the reader what to do next, not what is wrong. Printed without the
# FAIL prefix so a log's failures stay a list of defects.
REMEDY_PREFIX = "remedy: "

FILE_TYPES = {
    ".sh": "shell script",
    ".py": "python source",
    ".docx": "OOXML word-processing document (zip container)",
    ".pptx": "OOXML presentation (zip container)",
    ".xlsx": "OOXML spreadsheet (zip container)",
    ".pdf": "pdf document",
    ".png": "png image",
}

# What the repository audit can actually see, per engine, measured not assumed.
COVERAGE = {
    "office container": (
        "raw bytes plus every zip member, inflated where deflate applies"),
    "pdf container": (
        "raw bytes plus every stream that inflates; a stream that does not inflate is "
        "seen only as its compressed bytes"),
    "image container": (
        "raw bytes plus every text chunk the shared strict parser can certify: tEXt "
        "text, and zTXt/iTXt bodies after the keyword, flag and method fields are "
        "split and inflated; a container failing signature, chunk bounds, per-chunk "
        "CRC, IEND or trailing-byte checks is uncertifiable and never read as clean"),
    "text/binary": (
        "raw bytes plus the utf-8 round trip; `git grep -I` skips binary files, so for "
        "non-UTF-8 content this engine is the only one that reaches them"),
}
GENERIC_TYPE = "other text source"


class ManifestError(Exception):
    """A fail-closed refusal, reported without echoing file contents."""


def tracked_paths(root: Path) -> list[str]:
    """The tracked tree of `root`, not of whichever directory the process happens to be in."""
    result = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"], capture_output=True)
    if result.returncode != 0:
        raise ManifestError(f"{root} is not a git work tree (`git ls-files` failed)")
    paths = sorted(os.fsdecode(item) for item in result.stdout.split(b"\0") if item)
    if not paths:
        raise ManifestError(f"{root} tracks no files; refusing to certify an empty tree")
    return paths


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_type(rel: str, data: bytes) -> str:
    label = FILE_TYPES.get(Path(rel).suffix.lower())
    if label:
        return label
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        return "non-UTF-8 binary"
    return GENERIC_TYPE


def repository_scan(root: Path, rel: str, data: bytes) -> dict:
    """What the whole-tracked-tree audit sees for this file, measured on these bytes."""
    if Path(rel) in SKIP_FILES:
        return {
            "covered": False,
            "uncertifiable": False,
            "engine": None,
            "hits": None,
            "why": ("the repository audit excludes this path by its own SKIP_FILES rule; "
                    "the file carries the literals the audit searches for"),
            "coverage": "not opened by either repository engine",
        }
    try:
        kind, hits = scan_file(root / rel)
    except Exception as error:  # fail closed: an uncertifiable file is never "clean"
        return {
            "covered": False,
            "uncertifiable": True,
            "engine": None,
            "hits": None,
            "why": "the repository audit cannot open this file",
            "coverage": f"uncertifiable ({type(error).__name__})",
        }
    record = {
        "covered": True,
        "uncertifiable": False,
        "engine": kind,
        "hits": len(hits),
        "coverage": COVERAGE[kind],
    }
    if kind == "image container":
        # How many comments were actually decoded is part of what "covered" means,
        # so the register records the count. The hits themselves need no second
        # engine: the repository scan now inflates them the same way the staging
        # audit does, which is why this file no longer carries a stricter reading
        # alongside a looser one.
        record["png_text_chunk_views"] = len(png_text_chunks.parse(data))
    return record


def applies_to_future(rel: str, reason: str, data: bytes) -> dict:
    if rel in RULE_CARRIER_REASONS:
        return {
            "applies": True,
            "while": ("the file remains tracked and the sanitizer rules still redact "
                      "what the file uses as patterns"),
            "recheck_when": "the sanitizer rule set or these four files change",
        }
    return {
        "applies": True,
        "while": "the file remains non-UTF-8, which is when its redaction cannot be proven",
        "recheck_when": "the hash recorded here changes: a regenerated file is re-derived, "
                        "not inherited",
    }


def classify(root: Path) -> tuple[list[dict], list[dict], dict]:
    tracked = tracked_paths(root)
    research = [p for p in tracked if p.startswith(RESEARCH_PREFIX)]
    candidates = [p for p in tracked if not p.startswith(RESEARCH_PREFIX)]
    sources, excluded = [], []
    for rel in candidates:
        path = root / rel
        if not path.is_file():
            raise ManifestError(f"tracked file is not readable on disk: {rel}")
        data = path.read_bytes()
        if rel in RULE_CARRIER_REASONS:
            excluded.append(exclusion_record(rel, data, RULE_CARRIER_REASONS[rel], root))
            continue
        try:
            data.decode("utf-8")
        except UnicodeDecodeError:
            excluded.append(exclusion_record(rel, data, NON_UTF8_REASON, root))
            continue
        sources.append({"path": rel, "output": rel})
    stats = {
        "tracked": len(tracked),
        "research_not_declared": len(research),
        "non_research_candidates": len(candidates),
        "declared": len(sources),
        "excluded": len(excluded),
    }
    if stats["declared"] + stats["excluded"] != stats["non_research_candidates"]:
        raise ManifestError("accounting mismatch: the candidate set is not fully classified")
    return sources, excluded, stats


def exclusion_record(rel: str, data: bytes, reason: str, root: Path) -> dict:
    return {
        "path": rel,
        "sha256": _sha256(data),
        "bytes": len(data),
        "reason": reason,
        "file_type": file_type(rel, data),
        "repository_privacy_scan": repository_scan(root, rel, data),
        "applies_to_future_releases": applies_to_future(rel, reason, data),
        "release_branch_whole_tree_scan_required": not rel.startswith(RESEARCH_PREFIX),
    }


def documents(root: Path) -> tuple[dict, dict, dict]:
    sources, excluded, stats = classify(root)
    inputs_doc = {
        "manifest_version": MANIFEST_VERSION,
        "rules": RULES,
        "release_branch": RELEASE_BRANCH,
        "directory_globs_used": False,
        "sources": sources,
    }
    exclusions_doc = {
        "manifest_version": MANIFEST_VERSION,
        "rules": RULES,
        "release_branch": RELEASE_BRANCH,
        "record_fields": [
            "path", "sha256", "bytes", "reason", "file_type",
            "repository_privacy_scan", "applies_to_future_releases",
            "release_branch_whole_tree_scan_required",
        ],
        "excluded": excluded,
    }
    return inputs_doc, exclusions_doc, stats


def dump(doc: dict) -> str:
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


def derive(root: Path, inputs_out: Path, exclusions_out: Path) -> int:
    inputs_doc, exclusions_doc, stats = documents(root)
    for path, doc in ((inputs_out, inputs_doc), (exclusions_out, exclusions_doc)):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(dump(doc), encoding="utf-8")
    for key in ("tracked", "research_not_declared", "non_research_candidates",
                "declared", "excluded"):
        print(f"{key}={stats[key]}")
    print(f"PASS: derived {stats['declared']} input(s) and {stats['excluded']} "
          f"exclusion record(s) under rules {RULES}")
    return 0


def load(path: Path) -> dict:
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ManifestError(f"{path} is unreadable: {error}") from None
    if doc.get("manifest_version") != MANIFEST_VERSION:
        raise ManifestError(f"{path}: manifest_version {doc.get('manifest_version')!r} "
                            f"!= {MANIFEST_VERSION}")
    if doc.get("rules") != RULES:
        raise ManifestError(f"{path}: rules {doc.get('rules')!r} != {RULES}")
    return doc


def _key_names(container) -> set[str]:
    """Every dict key inside a parsed document, however deeply nested."""
    if isinstance(container, dict):
        return {str(key) for key in container} | {
            name for value in container.values() for name in _key_names(value)}
    if isinstance(container, list):
        return {name for item in container for name in _key_names(item)}
    return set()


def static_schema_errors(name: str, doc: dict, allowed: frozenset[str]) -> list[str]:
    """A versioned manifest may name files and their properties, and nothing else."""
    errors: list[str] = []
    unexpected = sorted(set(doc) - allowed)
    if unexpected:
        errors.append(f"{name} carries key(s) outside the static schema: "
                      f"{', '.join(unexpected)}")
    self_reference = sorted(DYNAMIC_PROVENANCE_FIELDS & _key_names(doc))
    if self_reference:
        errors.append(f"{name} carries dynamic provenance field(s) that belong to the "
                      f"chain sidecar, not to a versioned manifest: "
                      f"{', '.join(self_reference)}")
    return errors


def check(root: Path, inputs_path: Path, exclusions_path: Path) -> list[str]:
    """Every claim in the two documents, re-measured against the tracked tree."""
    errors: list[str] = []
    try:
        inputs_doc = load(inputs_path)
        exclusions_doc = load(exclusions_path)
    except ManifestError as error:
        return [str(error)]

    errors += static_schema_errors(INPUTS_FILE, inputs_doc, INPUTS_KEYS)
    errors += static_schema_errors(EXCLUSIONS_FILE, exclusions_doc, EXCLUSIONS_KEYS)
    if errors:
        return errors

    sources = inputs_doc.get("sources")
    excluded = exclusions_doc.get("excluded")
    if not isinstance(sources, list) or not sources:
        return ["input manifest declares no sources"]
    if not isinstance(excluded, list):
        return ["exclusion register has no records"]

    # Shape first: the input document must stay consumable by `release_sanitize build`,
    # and neither document may name a pattern instead of a file.
    for entry in sources:
        if not isinstance(entry, dict) or set(entry) != {"path", "output"}:
            errors.append(f"source entries must be exactly {{path, output}}: {entry!r}")
        else:
            if any(ch in entry["path"] + entry["output"] for ch in "*?[]$"):
                errors.append(f"source path is not an exact file: {entry['path']}")
            if entry["path"] != entry["output"]:
                errors.append(f"source renames inside the deliverable: {entry['path']}")
    for record in excluded:
        if not isinstance(record, dict):
            errors.append("exclusion records must be objects")
            continue
        missing = [f for f in exclusions_doc.get("record_fields", [])
                   if f not in record]
        if missing:
            errors.append(f"exclusion record {record.get('path')!r} lacks fields: "
                          f"{', '.join(missing)}")
        if any(ch in str(record.get("path", "")) for ch in "*?[]$"):
            errors.append(f"exclusion path is not an exact file: {record.get('path')}")

    if errors:
        return errors

    # Re-derive and compare membership before trusting any recorded attribute.
    derived_sources, derived_excluded, stats = classify(root)
    derived_input_paths = {e["path"] for e in derived_sources}
    declared_paths = {e["path"] for e in sources}
    register_paths = {r["path"] for r in excluded}
    derived_excluded_paths = {r["path"] for r in derived_excluded}

    unclassified = sorted({p for p in stats_paths(root)
                           if p not in declared_paths | register_paths})
    if unclassified:
        errors.append(
            f"{len(unclassified)} non-research tracked file(s) are in neither document "
            f"(first: {unclassified[0]}); classify them or add them to the inputs")
    for rel in sorted(declared_paths - derived_input_paths):
        errors.append(f"declared input is no longer a derived candidate: {rel}")
    for rel in sorted(derived_input_paths - declared_paths):
        errors.append(f"stale input list misses a current candidate: {rel}")
    for rel in sorted(register_paths - derived_excluded_paths):
        errors.append(f"exclusion record has no derived reason: {rel}")
    for rel in sorted(derived_excluded_paths - register_paths):
        errors.append(f"candidate is excluded by derivation but not registered: {rel}")
    if stats["declared"] != len(sources) or stats["excluded"] != len(excluded):
        # A duplicate entry makes the record count exceed the file set, which the
        # set comparison above cannot see.
        errors.append("a record is listed twice, or two records are missing")
    if errors:
        # The failure of this block is always the same failure: the tracked tree moved
        # under the documents. Say that, and name the one command that fixes it, so a
        # contributor does not have to reverse-engineer it from "in neither document".
        errors.append(REMEDY_PREFIX + "the tracked tree moved under the two documents: "
                      "run `python3 tools/release_manifest.py derive` and commit "
                      "release/*.json -- derive rewrites both documents from git ls-files")

    # Source files must still be buildable inputs: existing, unrenamed, UTF-8.
    for entry in sources:
        path = root / entry["path"]
        if entry["path"].startswith(RESEARCH_PREFIX):
            errors.append(f"a research file is declared as a deliverable input: {entry['path']}")
            continue
        if not path.is_file():
            errors.append(f"declared input is missing from the tree: {entry['path']}")
            continue
        try:
            path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            errors.append(f"declared input is no longer UTF-8, `build` would refuse it: "
                          f"{entry['path']}")

    # Exclusion records must describe the bytes that are actually on disk.
    by_path = {r["path"]: r for r in derived_excluded}
    for record in excluded:
        rel = record["path"]
        expect = by_path.get(rel)
        if expect is None:
            continue
        path = root / rel
        if not path.is_file():
            errors.append(f"exclusion record points at a missing file: {rel}")
            continue
        data = path.read_bytes()
        if _sha256(data) != record.get("sha256"):
            errors.append(f"excluded file changed since it was registered: {rel}")
        if record.get("bytes") != len(data):
            errors.append(f"excluded file size drift: {rel}")
        if record.get("reason") != expect["reason"]:
            errors.append(f"exclusion reason drifted from the derived reason: {rel}")
        if record.get("file_type") != expect["file_type"]:
            errors.append(f"file type drifted for: {rel}")
        if record.get("repository_privacy_scan") != expect["repository_privacy_scan"]:
            errors.append(f"repository scan reading drifted for: {rel}")
        if (record.get("applies_to_future_releases")
                != expect["applies_to_future_releases"]):
            errors.append(f"future-release applicability drifted for: {rel}")
        if record.get("release_branch_whole_tree_scan_required") is not True:
            errors.append(f"record drops the whole-tree scan requirement: {rel}")
        scan = record.get("repository_privacy_scan", {})
        if scan.get("covered") and scan.get("hits"):
            errors.append(f"registered file is not clean under the current "
                          f"repository rules: {rel}")
        if scan.get("uncertifiable"):
            # L3: an unreadable or malformed container is a refusal, never a pass.
            # Since the shared strict png parser landed this also covers a PNG whose
            # CRC, bounds, IEND or trailing bytes cannot be certified -- a container
            # that used to be scanned as raw bytes and reported clean.
            errors.append(f"registered file could not be certified by the repository "
                          f"audit ({scan.get('coverage')}): {rel}")
    return errors


def stats_paths(root: Path) -> list[str]:
    return [p for p in tracked_paths(root) if not p.startswith(RESEARCH_PREFIX)]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)

    derive_cmd = commands.add_parser("derive", help="write the two documents")
    derive_cmd.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    derive_cmd.add_argument("--inputs-out", type=Path)
    derive_cmd.add_argument("--exclusions-out", type=Path)

    check_cmd = commands.add_parser("check", help="prove the documents are complete")
    check_cmd.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    check_cmd.add_argument("--inputs", type=Path)
    check_cmd.add_argument("--exclusions", type=Path)

    args = parser.parse_args(argv)
    root = args.root.resolve()
    if args.command == "derive":
        inputs_out = args.inputs_out or root / INPUTS_FILE
        exclusions_out = args.exclusions_out or root / EXCLUSIONS_FILE
        try:
            return derive(root, inputs_out, exclusions_out)
        except ManifestError as error:
            print(f"FAIL: {error}", file=sys.stderr)
            return 1

    inputs_path = args.inputs or root / INPUTS_FILE
    exclusions_path = args.exclusions or root / EXCLUSIONS_FILE
    try:
        errors = check(root, inputs_path, exclusions_path)
    except ManifestError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    except Exception as error:  # a broken derivation is a refusal, not a pass
        print(f"FAIL: derivation could not be completed ({type(error).__name__})",
              file=sys.stderr)
        return 1
    for error in errors:
        if error.startswith(REMEDY_PREFIX):
            print(error)
        else:
            print(f"FAIL: {error}", file=sys.stderr)
    if errors:
        return 1
    # Measured on this tree, reported here, never committed: see the module docstring.
    stats = classify(root)[2]
    print(f"PASS: release manifest complete -- {stats['declared']} input(s), "
          f"{stats['excluded']} exclusion record(s), "
          f"{stats['non_research_candidates']} candidate(s) accounted, "
          f"no directory glob, every record hash-checked against the tree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
