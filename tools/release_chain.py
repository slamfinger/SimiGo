#!/usr/bin/env python3
"""Run the deliverable chain as one fail-closed sequence of steps.

The chain is `clean -> build -> syntax -> input hashes -> gate -> staging audit ->
provenance`. Each step runs only because the step before it passed, and the sequence
stops at the first failure. That ordering is the whole reason this file exists: a build
that fails part-way used to leave the previous round's staging tree on disk, and
a later gate pointed at that directory reported PASS about bytes this round never
built. Here a failed round removes the round's own artifacts and records the
failure, so there is nothing left to certify.

Two more properties the steps have to carry:

* the gate is bound to *this* round's manifest -- the provenance file is the one
  written moments earlier under the run directory, and every source is re-hashed
  against it, so a manifest from an older round or changed inputs cannot be
  dressed up as a pass;
* a deliverable file that redaction *rewrote* and that no longer parses is a build
  failure. The redaction rules can rewrite a file carrying its own patterns, and the
  content gate is blind to the resulting SyntaxError, so the syntax step catches it
  before the gate runs. Files the build left byte-identical are not judged here --
  their syntax is the repository audit's business, not this chain's.

The last step writes the provenance sidecar, and it is separate from the versioned
manifest for a reason (`#242`): `release/release-inputs-*.json` is committed, so if it
named the commit, tree, build time or digest of the round that wrote it, a later re-cut
of a different tree would either disagree with its own manifest or be certified against
the older one. The sidecar can carry those readings honestly because it lives in the run
directory and dies with the round: it describes exactly one staging tree, next to it.
Its deterministic identity covers the bytes in and the bytes out plus the code that
turned one into the other; `build_time` and the CI run are recorded but excluded from
that identity, and the file says which entries are excluded, so the boundary is readable
rather than implied. The sidecar also says whether the declared inputs are the bytes
that `source_commit` names -- if the work tree is dirty, replay from the commit alone is
not possible and the report must not imply that it is.

The verdict is about the staging tree only. The repository audit
(`tools/open_source_audit.sh`) is a separate evidence object and neither verdict
implies the other. Failure reports name files and steps; they never echo the
offending value.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_sanitize as sanitize  # noqa: E402
import release_staging_audit as staging  # noqa: E402

CHAIN = "release-chain-2026-11-01.2"
STEPS = ("clean", "build", "syntax", "input-hashes", "gate", "staging-audit",
         "provenance")
# The only names a previous round may have left in the run directory. Anything
# else is not ours to delete, so the run refuses rather than tidying.
RUN_ARTIFACTS = frozenset({"tree", "provenance.json", "chain.json",
                           "release-provenance.json"})
PROVENANCE_NAME = "release-provenance.json"

# The code that turned these inputs into this deliverable. Hashed from the directory
# this module actually ran from, so the sidecar names the engine that produced it.
TOOL_FILES = ("release_chain.py", "release_manifest.py", "release_sanitize.py",
              "release_artifact_audit.py", "release_staging_audit.py",
              "png_text_chunks.py")
IDENTITY_FIELDS = ("chain", "rules", "source_commit", "source_tree",
                   "inputs_manifest_sha256", "exclusions_manifest_sha256",
                   "tool_sha256", "staging_digest")
NOT_IN_IDENTITY = ("build_time", "ci", "inputs_at_commit")
PROVENANCE_RULES = "release-provenance-2026-11-01.1"
# What the sidecar says when there is no exclusions register to hash. Recorded as a
# value rather than a missing key, so "no register was passed" stays readable in the
# file instead of being inferred from an absent field.
NO_REGISTER = "not-provided"


class ChainError(Exception):
    """A fail-closed refusal, reported without echoing the offending value."""


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def clean(work: Path) -> list[str]:
    """Delete the previous round's artifacts and nothing else."""
    if not work.exists():
        return []
    if work.is_file() or work.is_symlink():
        raise ChainError(f"run directory is not a directory: {work}")
    removed: list[str] = []
    for path in sorted(work.iterdir()):
        if path.name not in RUN_ARTIFACTS:
            raise ChainError(
                f"run directory holds a file this tool does not own: {path.name}")
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink()
        removed.append(path.name)
    return removed


def discard(work: Path) -> list[str]:
    """Remove a failed round's staging output so no later step can certify it."""
    removed: list[str] = []
    for name in ("tree", "provenance.json", PROVENANCE_NAME):
        path = work / name
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
            removed.append(name)
        elif path.exists():
            path.unlink()
            removed.append(name)
    return removed


def check_python_outputs(tree: Path, records: list[dict]) -> tuple[list[str], int]:
    """Compile every .py output the build actually rewrote.

    Scope matters here. A file the build left byte-identical is the repository's
    own business -- this step exists for the measured incident, where redaction of a
    rule carrier produced a file that no longer parses while the content gate kept
    reporting PASS. So only rewritten files are judged, and the number judged is
    returned for the record: zero is an honest reading on a tree that needed no
    redaction, not a silent skip.

    Reported by file name and error class only: the failing line can itself be a
    rule carrier, and its text is exactly what must not reach a log.
    """
    errors: list[str] = []
    checked = 0
    for record in records:
        if not record.get("rules_applied") or not str(record.get("output", "")).endswith(".py"):
            continue
        relative = record["output"]
        path = tree / relative
        checked += 1
        if path.is_symlink():
            continue
        try:
            compile(path.read_text(encoding="utf-8"), relative, "exec")
        except (SyntaxError, UnicodeDecodeError, ValueError) as error:
            errors.append(f"{relative}: {type(error).__name__}")
    return errors, checked


def check_input_hashes(inputs_path: Path, manifest_path: Path, root: Path) -> list[str]:
    """Bind the gate to this round's build: same sources, same bytes, same count."""
    errors: list[str] = []
    try:
        declared = [entry["path"] for entry in sanitize.load_inputs(inputs_path)]
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (sanitize.SanitizeError, OSError, json.JSONDecodeError) as error:
        return [f"cannot bind the manifest to the inputs: {type(error).__name__}"]
    records = manifest.get("sources") or []
    if [record.get("source") for record in records] != declared:
        errors.append("the manifest does not list the same sources as the input manifest")
    for record in records:
        source = record.get("source")
        if not source:
            continue
        path = root / source
        if not path.is_file():
            errors.append(f"input disappeared after the build: {source}")
        elif _sha256(path.read_bytes()) != record.get("source_sha256"):
            errors.append(f"input changed after the build: {source}")
    return errors


def tool_sha256() -> dict[str, str]:
    """Hash of every engine file that ran this round, from the directory it ran from."""
    tools = Path(__file__).resolve().parent
    hashes = {}
    for name in TOOL_FILES:
        path = tools / name
        if not path.is_file():
            raise ChainError(f"the engine that ran this round is not readable: {name}")
        hashes[name] = _sha256(path.read_bytes())
    return hashes


def deliverable_digest(tree: Path, records: list[dict]) -> str:
    """A digest over the deliverable's own file identities, sorted by output path.

    Names and hashes only, so the digest is reproducible from the manifest without
    re-reading the tree, and two rounds that produced the same bytes agree. The gate
    has already re-hashed every one of these outputs against this manifest, so the
    probe here only catches the case where the manifest is being digested against a
    directory that is not the one it describes.

    The ordering is part of the recipe: sorted by the output *string*. A reader who
    replays it from the tree with path-component ordering gets a different digest on
    any nested deliverable, so a mismatch there is not evidence of changed bytes.
    """
    if not records:
        raise ChainError("the manifest names no deliverable file")
    lines = "".join(f"{record['output']}\t{record['output_sha256']}\n"
                    for record in sorted(records, key=lambda item: item["output"]))
    if not (tree / records[0]["output"]).is_file():
        raise ChainError("the manifest names a deliverable that is not on disk")
    return _sha256(lines.encode("utf-8"))


def git_output(root: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(root), *args],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise ChainError(f"cannot name the source {' '.join(args)} for this run")
    return result.stdout.strip()


def source_identity(root: Path, sources: list[str]) -> dict:
    """The commit these bytes came from, and whether they are that commit's bytes.

    `inputs_at_commit` is the load-bearing field for replay: a work tree whose input
    files differ from `HEAD` cannot be re-produced from the commit alone, whatever
    the hashes in this file say. The answer is measured per declared input, so an
    unrelated edit somewhere else in the tree does not make the round look dirty.
    """
    commit = git_output(root, "rev-parse", "HEAD")
    tree_hash = git_output(root, "rev-parse", "HEAD^{tree}")
    tracked = [entry for entry in git_output(
        root, "ls-files", "-z", "--", *sources).split("\0") if entry]
    differing: set[str] = set()
    for listing in (git_output(root, "diff", "--name-only", "-z", "HEAD", "--", *sources),
                    git_output(root, "ls-files", "--others", "--exclude-standard", "-z",
                               "--", *sources)):
        differing.update(entry for entry in listing.split("\0") if entry)
    return {
        "source_commit": commit,
        "source_tree": tree_hash,
        "inputs_named": len(sources),
        "inputs_tracked": len(tracked),
        "inputs_differing_from_commit": len(differing),
        "inputs_at_commit": len(tracked) == len(sources) and not differing,
    }


def ci_identity() -> dict:
    """Where this round ran. A local run is labelled local, never left ambiguous."""
    run_id = os.environ.get("GITHUB_RUN_ID")
    if run_id:
        return {"provider": "github-actions", "run_id": run_id,
                "attempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
                "head_sha": os.environ.get("GITHUB_SHA"),
                "ref": os.environ.get("GITHUB_REF"), "explicitly_local": False}
    return {"provider": "local", "run_id": None, "attempt": None, "head_sha": None,
            "ref": None, "explicitly_local": True,
            "note": "no CI run id in the environment: this round has no remote evidence"}


def build_timestamp() -> str:
    """When this round ran. Named separately because a control has to be able to
    run two rounds at different times and show the identity is unchanged."""
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def provenance(report: dict, inputs_path: Path, exclusions_path: Path | None,
               manifest: dict, tree: Path, root: Path) -> dict:
    """The sidecar describing this round's staging tree, written next to it."""
    source = source_identity(root, [record["source"] for record in manifest["sources"]])
    identity = {
        "chain": report["chain"],
        "rules": report["rules"],
        "source_commit": source["source_commit"],
        "source_tree": source["source_tree"],
        "inputs_manifest_sha256": _sha256(inputs_path.read_bytes()),
        "exclusions_manifest_sha256": (_sha256(exclusions_path.read_bytes())
                                       if exclusions_path else NO_REGISTER),
        "tool_sha256": tool_sha256(),
        "staging_digest": deliverable_digest(tree, manifest["sources"]),
    }
    return {
        "provenance": PROVENANCE_RULES,
        "work": report["work"],
        "inputs_manifest": report["inputs"],
        "exclusions_manifest": str(exclusions_path) if exclusions_path else NO_REGISTER,
        "identity": identity,
        "identity_sha256": _sha256(json.dumps(identity, sort_keys=True,
                                             separators=(",", ":")).encode("utf-8")),
        "identity_fields": list(IDENTITY_FIELDS),
        "source": source,
        "identity_excludes": list(NOT_IN_IDENTITY),
        "build_time": build_timestamp(),
        "ci": ci_identity(),
        "deliverable": {
            "files": len(manifest["sources"]),
            "bytes": sum(record["output_bytes"] for record in manifest["sources"]),
            "redacted_files": sum(1 for record in manifest["sources"]
                                  if record["rules_applied"]),
        },
        "staging_audit": report["staging_audit"],
    }


def run(inputs_path: Path, work: Path, root: Path,
        exclusions_path: Path | None = None) -> tuple[dict, int]:
    """Execute the chain. Returns (report, exit status); no step runs after a failure."""
    work = work.resolve()
    report: dict = {
        "chain": CHAIN,
        "rules": {"sanitize": sanitize.RULES_VERSION, "staging_audit": staging.RULES},
        "inputs": str(inputs_path),
        "exclusions": str(exclusions_path) if exclusions_path else NO_REGISTER,
        "work": str(work),
        "root": str(root),
        "steps": [],
        "cleaned": [],
        "failed_step": None,
        "detail": None,
        "not_run": [],
        "removed_after_failure": [],
    }

    def step(name: str, status: str, **fields: object) -> None:
        report["steps"].append({"step": name, "status": status, **fields})

    def fail(name: str, detail: str, *, keep: bool = False, **fields: object) -> tuple[dict, int]:
        step(name, "fail", **fields)
        report["failed_step"] = name
        report["detail"] = detail
        report["not_run"] = list(STEPS[STEPS.index(name) + 1:])
        if not keep:
            # A failed round must leave nothing that a later step could certify.
            report["removed_after_failure"] = discard(work)
        return report, 1

    try:
        report["cleaned"] = clean(work)
    except ChainError as error:
        # Nothing was deleted: a directory holding a file this tool does not own is
        # refused intact, not tidied.
        return fail("clean", str(error), keep=True)
    step("clean", "pass", removed=len(report["cleaned"]))

    tree = work / "tree"
    manifest_path = work / "provenance.json"
    try:
        manifest = sanitize.build(inputs_path, tree, manifest_path, root)
    except Exception as error:  # noqa: BLE001 -- any build failure stops the chain
        return fail("build", f"{type(error).__name__}: {error}",
                    residual_files=len(list(tree.rglob("*"))) if tree.is_dir() else 0)
    step("build", "pass", files=len(manifest["sources"]))

    try:
        syntax_errors, redacted_python = check_python_outputs(tree, manifest["sources"])
    except Exception as error:  # noqa: BLE001
        return fail("syntax", f"{type(error).__name__}")
    if syntax_errors:
        return fail("syntax", "; ".join(syntax_errors),
                    broken_files=len(syntax_errors),
                    note="the content gate cannot see a redaction that breaks a file")
    step("syntax", "pass", redacted_python=redacted_python,
         unchanged_python_files_not_judged=len(list(tree.rglob("*.py"))) - redacted_python)

    hash_errors = check_input_hashes(inputs_path, manifest_path, root)
    if hash_errors:
        return fail("input-hashes", "; ".join(hash_errors))
    step("input-hashes", "pass", verified=len(manifest["sources"]))

    try:
        gate_errors = sanitize.gate(tree, manifest_path)
    except Exception as error:  # noqa: BLE001 -- an unusable gate is a failed gate
        return fail("gate", f"{type(error).__name__}")
    if gate_errors:
        return fail("gate", "; ".join(gate_errors), violations=len(gate_errors))
    step("gate", "pass", files=len(manifest["sources"]))

    try:
        audit_report = staging.audit(tree)
    except Exception as error:  # noqa: BLE001 -- an audit that cannot run has not passed
        return fail("staging-audit", str(error), checked=len(list(tree.rglob("*"))))
    report["staging_audit"] = {
        key: audit_report[key]
        for key in ("rules", "checked", "carriers_excluded", "artifact_hits",
                    "sanitize_hits", "unreadable", "container_errors", "container_checked")
    }
    blocked = (audit_report["artifact_hits"] or audit_report["sanitize_hits"]
               or audit_report["unreadable"] or audit_report["container_errors"])
    if blocked:
        return fail("staging-audit",
                    f"{len(audit_report['artifact_hits'])} token file(s), "
                    f"{len(audit_report['sanitize_hits'])} rule violation(s), "
                    f"{len(audit_report['container_errors'])} uncertifiable container(s), "
                    f"{len(audit_report['unreadable'])} unreadable",
                    checked=audit_report["checked"])
    step("staging-audit", "pass", checked=audit_report["checked"])

    try:
        sidecar = provenance(report, inputs_path, exclusions_path, manifest, tree, root)
    except ChainError as error:
        # The round built a clean tree it cannot name: no commit, no engine file, no
        # digest. Nothing is left to certify, so the tree goes with the failure.
        return fail("provenance", str(error))
    except Exception as error:  # noqa: BLE001 -- detail names the class, never a path
        return fail("provenance", f"{type(error).__name__}")
    sidecar_path = work / PROVENANCE_NAME
    try:
        # Written through the same rules as the log, because the sidecar legitimately
        # carries the absolute run paths.
        sidecar_path.write_text(
            publishable(json.dumps(sidecar, indent=2, ensure_ascii=False)) + "\n",
            encoding="utf-8")
    except OSError as error:
        return fail("provenance", f"cannot write {PROVENANCE_NAME}: {type(error).__name__}")
    report["provenance"] = sidecar
    step("provenance", "pass", files=sidecar["deliverable"]["files"],
         identity_sha256=sidecar["identity_sha256"][:16],
         inputs_at_commit=sidecar["source"]["inputs_at_commit"],
         ci=sidecar["ci"]["provider"])
    return report, 0


def publishable(text: str) -> str:
    """Run a log line through the redaction rules before it leaves this tool.

    The report legitimately carries the absolute run-directory path, and on a
    developer machine that is exactly the kind of path this rule set exists to keep
    out of a log, an evidence file or a CI transcript.
    """
    return sanitize.sanitize_text(text)[0]


def report_lines(report: dict) -> list[str]:
    lines = [f"CHAIN {report['chain']} rules sanitize={report['rules']['sanitize']} "
             f"staging_audit={report['rules']['staging_audit']}"]
    for entry in report["steps"]:
        details = ", ".join(f"{key}={value}" for key, value in entry.items()
                            if key not in {"step", "status"})
        lines.append(f"STEP {entry['step']} {entry['status'].upper()}"
                     + (f" ({details})" if details else ""))
    if report["failed_step"]:
        lines.append(f"CHAIN RESULT = FAIL at step {report['failed_step']}")
        lines.append(f"  detail: {report['detail']}")
        lines.append(f"  steps NOT run: {', '.join(report['not_run']) or 'none'}")
        lines.append(f"  round artifacts removed: "
                     f"{', '.join(report['removed_after_failure']) or 'none'}")
    else:
        lines.append("CHAIN RESULT = PASS "
                     f"({len(report['steps'])}/{len(STEPS)} steps, no step skipped)")
    if "provenance" in report:
        # The boundary is stated in the transcript, not only inside the sidecar.
        lines.append(f"PROVENANCE {PROVENANCE_NAME}: identity excludes "
                     f"{', '.join(NOT_IN_IDENTITY)}")
    return [publishable(line) for line in lines]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--inputs", required=True, type=Path,
                        help="input manifest naming the release inputs, file by file")
    parser.add_argument("--work", required=True, type=Path,
                        help="run directory for the staging tree, manifest and report")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1],
                        help="root that source paths are relative to (default: repo root)")
    parser.add_argument("--exclusions", type=Path,
                        help="the per-file exclusions register to hash into the sidecar; "
                             "omitted means this round has no register, and the sidecar "
                             "says so instead of guessing one")
    parser.add_argument("--report", type=Path,
                        help="also write the chain report here (outside the run directory)")
    args = parser.parse_args(argv)

    exclusions = args.exclusions.resolve() if args.exclusions else None
    report, code = run(args.inputs.resolve(), args.work, args.root.resolve(), exclusions)
    stream = sys.stderr if code else sys.stdout
    for line in report_lines(report):
        print(line, file=stream)
    serialised = publishable(json.dumps(report, indent=2, ensure_ascii=False)) + "\n"
    report_path = Path(report["work"]) / "chain.json"
    if report_path.parent.is_dir():
        report_path.write_text(serialised, encoding="utf-8")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(serialised, encoding="utf-8")
    print("NOTE: this is the staging chain only. The repository audit is "
          "tools/open_source_audit.sh; neither verdict implies the other.", file=stream)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
