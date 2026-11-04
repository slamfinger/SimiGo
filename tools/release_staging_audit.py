#!/usr/bin/env python3
"""Run the repository privacy predicates against one staging deliverable directory.

Two measurement objects that must never be merged:

* the repository audit -- `tools/open_source_audit.sh` plus
  `tools/release_artifact_audit.py` -- enumerates every hit in every tracked file
  of a tree. Its verdict is about the repository.
* this audit enumerates the bytes that are about to be published. Its verdict is
  about that directory only, and it is not evidence that the repository, its
  branches or its history are clean.

Every predicate is imported rather than restated, so this file cannot become a
looser audit by editing this file:

* forbidden literals, per-file container decoding (raw bytes plus Office / PDF /
  PNG decoded streams) and the self-exclusion set come from `release_artifact_audit`;
* the absolute home and temporary path patterns, and the deliverable scanner that
  reports hits as rule ids and offsets without echoing the value, come from
  `release_sanitize`.

Both engines run over the whole directory. A symlink, an unreadable file or a hit
in either engine fails the audit closed.

The PNG container is parsed by `tools/png_text_chunks.py` -- the same module the
repository audit now calls, so a comment compressed behind `keyword\\0method\\0` is
reachable from either entry and an uncertifiable container fails either verdict.
A container that cannot be certified -- bad CRC, out-of-range chunk length, missing
`IEND`, bytes after `IEND`, unsupported compression method, failed inflate, or an
image-suffixed file that is not a PNG at all -- is an error, never a pass, and such
a file is not counted as checked. The raw file bytes stay in scope: the whole file
is still scanned, so a literal the parser never reaches is still found. Counts are
per scanned view, so a literal visible in several views is counted once per view;
the verdict only cares that the list is non-empty.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import png_text_chunks  # noqa: E402
from png_text_chunks import PngStructureError  # noqa: E402
from release_artifact_audit import (  # noqa: E402
    FORBIDDEN,
    SKIP_FILES,
    findings,
    scan_file,
)
from release_sanitize import scan_deliverable  # noqa: E402

RULES = "staging-audit-2026-11-01.3"

# Re-exported under the names this file has always published, so a caller of the
# staging audit gets the shared parser rather than a second implementation:
# `png_text_views` certifies and returns the views (or raises), `png_views` returns
# (views, errors). These are the same function objects the repository audit uses.
png_text_views = png_text_chunks.parse
png_views = png_text_chunks.views_and_errors
PNG_SIGNATURE = png_text_chunks.SIGNATURE
PNG_TEXT_CHUNKS = png_text_chunks.TEXT_CHUNKS
PNG_DEFLATE = png_text_chunks.DEFLATE
PNG_MAX_KEYWORD = png_text_chunks.MAX_KEYWORD
PNG_CHUNK_TYPE_BYTES = png_text_chunks.CHUNK_TYPE_BYTES


class StagingAuditError(Exception):
    """A fail-closed refusal, reported without echoing the offending value."""


def enumerate_directory(deliverable_dir: Path) -> list[Path]:
    if not deliverable_dir.is_dir():
        raise StagingAuditError(f"staging directory missing: {deliverable_dir}")
    paths = sorted(deliverable_dir.rglob("*"))
    for path in paths:
        if path.is_symlink():
            # A link is a reference to bytes the audit did not read.
            raise StagingAuditError(
                f"symlink in staging directory: {path.relative_to(deliverable_dir).as_posix()}")
    files = [path for path in paths if path.is_file()]
    if not files:
        raise StagingAuditError(f"staging directory is empty: {deliverable_dir}")
    return files


def audit(deliverable_dir: Path) -> dict:
    """Return the per-directory verdict; never the offending values themselves."""
    files = enumerate_directory(deliverable_dir)
    report = {
        "rules": RULES,
        "directory": str(deliverable_dir),
        "checked": 0,
        "carriers_excluded": [],
        "artifact_hits": [],
        "sanitize_hits": [],
        "unreadable": [],
        "container_errors": [],
        "container_checked": {"office": 0, "pdf": 0, "image": 0, "other": 0},
    }
    for path in files:
        relative = path.relative_to(deliverable_dir).as_posix()
        if relative in {entry.as_posix() for entry in SKIP_FILES}:
            # Same self-exclusion the repository audit applies to its own rule
            # carriers: those files hold the literals by construction. Reported,
            # never silent, and it is the *same* set -- not a new exemption.
            report["carriers_excluded"].append(relative)
            continue
        try:
            kind, hits = scan_file(path)
        except PngStructureError as error:
            # The shared parser refused to certify this container, so the file is not
            # counted as checked: an unparsed image is not a scanned image. The raw
            # bytes are still searched, because a literal sitting outside the chunk
            # structure is a hit here too -- it simply cannot make the verdict clean.
            report["container_errors"].append(f"{relative} [image container]: {error}")
            data = path.read_bytes()
            raw_hits = findings(data)
            if raw_hits:
                report["artifact_hits"].append(
                    f"{relative} [uncertifiable container] x{len(raw_hits)}")
            violations = scan_deliverable(data)
            if violations:
                report["sanitize_hits"].append(f"{relative}: {', '.join(violations)}")
            continue
        except Exception as error:  # fail closed: an unreadable file is not a clean file
            report["unreadable"].append(f"{relative}: {type(error).__name__}")
            continue
        report["checked"] += 1
        if kind == "office container":
            report["container_checked"]["office"] += 1
        elif kind == "pdf container":
            report["container_checked"]["pdf"] += 1
        elif kind == "image container":
            report["container_checked"]["image"] += 1
        else:
            report["container_checked"]["other"] += 1
        if hits:
            report["artifact_hits"].append(f"{relative} [{kind}] x{len(hits)}")
        deliverable_violations = scan_deliverable(path.read_bytes())
        if deliverable_violations:
            report["sanitize_hits"].append(f"{relative}: {', '.join(deliverable_violations)}")
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dir", required=True, type=Path,
                        help="staging deliverable directory to audit")
    args = parser.parse_args(argv)

    print(f"STAGING AUDIT rules {RULES} directory {args.dir.resolve()}")
    print("NOTE: this audits the publishable tree only. The repository audit is")
    print("      tools/open_source_audit.sh; neither verdict implies the other.")
    try:
        report = audit(args.dir.resolve())
    except StagingAuditError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    for note in report["unreadable"]:
        print(f"FAIL: unable to audit {note}", file=sys.stderr)
    for note in report["container_errors"]:
        print(f"FAIL: uncertifiable container {note}", file=sys.stderr)
    for hit in report["artifact_hits"]:
        print(f"FAIL: forbidden token in staging file {hit}", file=sys.stderr)
    for hit in report["sanitize_hits"]:
        print(f"FAIL: staging file violates the redaction rule set {hit}", file=sys.stderr)
    if report["carriers_excluded"]:
        print("EXCLUDED (repository audit's own rule-carrier set, unchanged): "
              + ", ".join(report["carriers_excluded"]))
    containers = report["container_checked"]
    print(f"CHECKED {report['checked']} file(s); containers "
          f"office={containers['office']} pdf={containers['pdf']} "
          f"image={containers['image']} text_or_other={containers['other']}; "
          f"forbidden_literals={len(FORBIDDEN)}")
    if (report["unreadable"] or report["container_errors"]
            or report["artifact_hits"] or report["sanitize_hits"]):
        print(f"RESULT staging audit = FAIL ({len(report['artifact_hits'])} token file(s), "
              f"{len(report['sanitize_hits'])} rule-set violation(s), "
              f"{len(report['container_errors'])} uncertifiable container(s), "
              f"{len(report['unreadable'])} unreadable)", file=sys.stderr)
        return 1
    print("RESULT staging audit = PASS "
          f"({report['checked']} file(s) raw + decoded-container + redaction patterns; "
          "PNG text chunks parsed by field and inflated, uncertifiable containers "
          "would have failed this run)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
