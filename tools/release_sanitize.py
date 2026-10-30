#!/usr/bin/env python3
"""Build redacted copies of explicitly selected files, and gate a deliverable directory.

Two measurement objects that must never be conflated:

* **Tracked-tree audit** (`tools/open_source_audit.sh`, `tools/release_artifact_audit.py`)
  enumerates every hit in every tracked file. Frozen originals keep their bytes and
  their history; nothing here rewrites them.
* **Deliverable gate** (this tool) looks only at what is about to be published: the
  files named in an explicit input manifest are copied, the copies are redacted, and
  the result is checked file by file. Nothing is discovered implicitly -- a directory
  is never packaged wholesale, and `research/` is never blanket-excluded either.

Build (steps 1-3):
    tools/release_sanitize.py build --inputs release-inputs.json --out /tmp/deliverable \\
        --manifest-out /tmp/deliverable.manifest.json

    {"manifest_version": 1,
     "sources": [{"path": "research/.../evidence.md", "output": "evidence.md"}]}

Gate (step 4):
    tools/release_sanitize.py gate --dir /tmp/deliverable \\
        --manifest /tmp/deliverable.manifest.json

The provenance manifest records per source: repo-relative identifier, SHA-256 and size;
the sanitizer rule-set version; and the output path with its SHA-256 and size. It never
records the redacted values themselves. The gate fails closed when a file is missing,
undeclared, altered, still carries a forbidden token, still carries an absolute home or
temporary path, or when the manifest was produced by a different rule set.

The forbidden literals are imported from `release_artifact_audit.py` so the redaction
rules and the audit can never drift apart; this file therefore contains none of them.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_artifact_audit import FORBIDDEN  # noqa: E402  (single source of truth)

RULES_VERSION = "sanitize-2026-10-29.1"
MANIFEST_VERSION = 1

# Built by concatenation: this tool must not carry the literal it redacts.
HOME_PATH = re.compile("/" + "Users/" + r"[^/\s\"'`<>]+")
TEMP_PATH = re.compile(r"/private/var/folders/[^\s\"'`<>]+")


class SanitizeError(Exception):
    """A fail-closed refusal, reported without touching anything."""


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def literal_rules() -> list[tuple[str, str]]:
    return [(f"forbidden_{index}", literal.decode("ascii"))
            for index, literal in enumerate(FORBIDDEN)]


def sanitize_text(text: str) -> tuple[str, list[str]]:
    """Apply the explicit rule set in order. Idempotent: placeholders never match."""
    applied: list[str] = []
    redacted = text
    for rule_id, pattern, replacement in (
        ("home_paths", HOME_PATH, "<HOME>"),
        ("temp_paths", TEMP_PATH, "<TMP>"),
    ):
        redacted, hits = pattern.subn(replacement, redacted)
        if hits:
            applied.append(rule_id)
    for rule_id, literal in literal_rules():
        if literal in redacted:
            redacted = redacted.replace(literal, f"<REDACTED:{rule_id}>")
            applied.append(rule_id)
    return redacted, applied


def _offsets(data: bytes, needle: bytes) -> list[int]:
    found: list[int] = []
    start = 0
    while True:
        offset = data.find(needle, start)
        if offset < 0:
            return found
        found.append(offset)
        start = offset + 1


def scan_deliverable(data: bytes) -> list[str]:
    """The audit's predicates, reported as rule ids plus offsets only.

    A gate that echoes the leaked value into its own log re-publishes it in CI
    output and in any transcript of the failure. Rule id plus offset locates the
    hit without repeating it.
    """
    # Both views can see the same occurrence; report the larger count, never the
    # sum, so a single occurrence is never reported twice.
    decoded = data.decode("utf-8", "ignore").encode()
    views = [data] if decoded == data else [data, decoded]
    violations: list[str] = []
    for rule_id, literal in literal_rules():
        best_count, best_first = 0, 0
        for view in views:
            offsets = _offsets(view, literal.encode("ascii"))
            if len(offsets) > best_count:
                best_count, best_first = len(offsets), offsets[0]
        if best_count:
            violations.append(f"{rule_id} x{best_count} first@{best_first}")
    text = data.decode("utf-8", "ignore")
    for rule_id, pattern in (("home_paths", HOME_PATH), ("temp_paths", TEMP_PATH)):
        count = sum(1 for _ in pattern.finditer(text))
        if count:
            violations.append(f"{rule_id} x{count}")
    return violations


def _require_inside(path: Path, root: Path, what: str) -> None:
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError:
        raise SanitizeError(f"{what} escapes its root: {path}") from None


def _require_relative(value: str, what: str) -> Path:
    candidate = Path(value)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise SanitizeError(f"{what} must be a relative path without '..': {value}")
    return candidate


def load_inputs(inputs_path: Path) -> list[dict]:
    try:
        spec = json.loads(inputs_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SanitizeError(f"input manifest unreadable: {error}") from None
    if spec.get("manifest_version") != MANIFEST_VERSION:
        raise SanitizeError(
            f"input manifest_version must be {MANIFEST_VERSION}, got {spec.get('manifest_version')!r}")
    sources = spec.get("sources")
    if not isinstance(sources, list) or not sources:
        raise SanitizeError("input manifest must name at least one source")
    for entry in sources:
        if not isinstance(entry, dict) or set(entry) != {"path", "output"}:
            raise SanitizeError(f"each source needs exactly 'path' and 'output': {entry!r}")
    return sources


def build(inputs_path: Path, out_dir: Path, manifest_out: Path, root: Path) -> dict:
    sources = load_inputs(inputs_path)
    out_dir = out_dir.resolve()
    manifest_out = manifest_out.resolve()
    if manifest_out.is_relative_to(out_dir):
        raise SanitizeError("the provenance manifest must live outside the deliverable directory")
    if out_dir.exists() and any(out_dir.iterdir()):
        raise SanitizeError(f"deliverable directory is not empty: {out_dir}")

    records: list[dict] = []
    written: list[Path] = []
    seen_outputs: set[str] = set()
    try:
        for entry in sources:
            source = (root / _require_relative(entry["path"], "source path")).resolve()
            _require_inside(source, root, "source path")
            if not source.is_file():
                raise SanitizeError(f"source is not a readable file: {entry['path']}")
            output_rel = _require_relative(entry["output"], "output path")
            if output_rel.as_posix() in seen_outputs:
                raise SanitizeError(f"two sources map to the same output: {entry['output']}")
            destination = (out_dir / output_rel).resolve()
            _require_inside(destination, out_dir, "output path")

            raw = source.read_bytes()
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                raise SanitizeError(
                    f"cannot prove redaction of non-UTF-8 file: {entry['path']}") from None
            redacted, applied = sanitize_text(text)
            payload = redacted.encode("utf-8")
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(payload)
            written.append(destination)
            seen_outputs.add(output_rel.as_posix())
            records.append({
                "source": entry["path"],
                "source_sha256": _sha256(raw),
                "source_bytes": len(raw),
                "output": output_rel.as_posix(),
                "output_sha256": _sha256(payload),
                "output_bytes": len(payload),
                "rules_applied": applied,
            })
    except BaseException:
        # A partial deliverable must never be mistakable for a complete one.
        for path in written:
            path.unlink(missing_ok=True)
        raise

    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "rules_version": RULES_VERSION,
        "sources": records,
    }
    manifest_out.parent.mkdir(parents=True, exist_ok=True)
    manifest_out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
                            encoding="utf-8")
    return manifest


def gate(deliverable_dir: Path, manifest_path: Path) -> list[str]:
    errors: list[str] = []
    deliverable_dir = deliverable_dir.resolve()
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"provenance manifest unreadable: {error}"]
    if manifest.get("manifest_version") != MANIFEST_VERSION:
        errors.append(
            f"manifest_version {manifest.get('manifest_version')!r} != {MANIFEST_VERSION}")
    if manifest.get("rules_version") != RULES_VERSION:
        errors.append(
            f"rules_version {manifest.get('rules_version')!r} != {RULES_VERSION}: "
            "rebuild the deliverable with the current rule set")
    records = manifest.get("sources")
    if not isinstance(records, list) or not records:
        return errors + ["provenance manifest declares no outputs"]

    declared: set[str] = set()
    for record in records:
        output = record.get("output", "")
        declared.add(output)
        destination = deliverable_dir / output
        if destination.is_symlink():
            # A link is a reference to bytes the manifest does not describe; the
            # content check below would follow it and pass while the packaged
            # tree carries something else.
            errors.append(f"declared output is a symlink: {output}")
            continue
        if not destination.is_file():
            errors.append(f"declared output missing: {output}")
            continue
        data = destination.read_bytes()
        if _sha256(data) != record.get("output_sha256") or len(data) != record.get("output_bytes"):
            errors.append(f"declared output altered since the manifest was written: {output}")
        violations = scan_deliverable(data)
        literals = [v for v in violations if v.startswith("forbidden_")]
        home = [v for v in violations if v.startswith("home_paths")]
        temp = [v for v in violations if v.startswith("temp_paths")]
        if literals:
            errors.append(f"forbidden token still present in {output}: {', '.join(literals)}")
        if home:
            errors.append(f"absolute home path still present in {output}: {', '.join(home)}")
        if temp:
            errors.append(f"absolute temporary path still present in {output}: {', '.join(temp)}")

    if deliverable_dir.is_dir():
        for path in sorted(deliverable_dir.rglob("*")):
            relative = path.relative_to(deliverable_dir).as_posix()
            if path.is_symlink():
                errors.append(f"symlink in deliverable directory: {relative}")
            elif path.is_file() and relative not in declared:
                errors.append(f"undeclared file in deliverable directory: {relative}")
    else:
        errors.append(f"deliverable directory missing: {deliverable_dir}")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)

    build_cmd = commands.add_parser("build", help="copy the listed sources and redact the copies")
    build_cmd.add_argument("--inputs", required=True, type=Path)
    build_cmd.add_argument("--out", required=True, type=Path)
    build_cmd.add_argument("--manifest-out", required=True, type=Path)
    build_cmd.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1],
                           help="root that source paths are relative to (default: repo root)")

    gate_cmd = commands.add_parser("gate", help="fail closed unless the deliverable matches")
    gate_cmd.add_argument("--dir", required=True, type=Path)
    gate_cmd.add_argument("--manifest", required=True, type=Path)

    args = parser.parse_args(argv)
    if args.command == "build":
        try:
            manifest = build(args.inputs, args.out, args.manifest_out, args.root)
        except SanitizeError as error:
            print(f"FAIL: {error}", file=sys.stderr)
            return 1
        for record in manifest["sources"]:
            rules = ", ".join(record["rules_applied"]) or "none"
            print(f"REDACTED {record['source']} -> {record['output']} [{rules}]")
        print(f"PASS: built {len(manifest['sources'])} file(s) under rules {RULES_VERSION}")
        return 0

    errors = gate(args.dir, args.manifest)
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    if errors:
        return 1
    print("PASS: deliverable matches its provenance manifest and carries no forbidden token")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
