#!/usr/bin/env python3
"""Emit the G7b runner manifest for the reviewed G3/D1 worktree.

The D1 protocol requires a `runner_manifest_sha256` that binds the executed
binaries to the reviewed source (protocol section 4, step 4 and section 11.5).
Git HEADs alone cannot do that here: the reviewed implementation lives in
untracked files, in local-only commits, in uncommitted vendor edits and in a
nested submodule pointer. This tool records all of those layers and derives two
digests:

  source_sha256  content identity of the source snapshot (no binaries)
  runner_sha256  source identity plus the build artifacts that exist

Neither digest is a claim that the build is fresh. Freshness is reported
separately and never enters a digest, so rebuilding identical bytes does not
change identity.

Usage:
  python3 tools/g3_runner_manifest.py --out <path>
  python3 tools/g3_runner_manifest.py --verify <path>

Exit status is non-zero when verification fails or when a required artifact is
missing and --require-artifacts was passed.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_ID = "G3-D1-RUNNER-MANIFEST-V3"
DIGEST_SCHEMA_ID = "G3-D1-SOURCE-DIGEST-V3"
ROOT = Path(__file__).resolve().parent.parent

# The digest rules are part of the frozen identity: editing any of these strings
# changes `source_sha256`, so the definition cannot drift silently.
DIGEST_RULES = {
    "schema": DIGEST_SCHEMA_ID,
    "encoding": (
        "UTF-8 JSON; json.dumps(sort_keys=True, separators=(',', ':'), "
        "ensure_ascii=False); SHA-256 over the resulting bytes"
    ),
    "source_covers": [
        "schema_id and digest_rules (these rules are themselves frozen)",
        "scope (dirs, files, governance prefix)",
        "files[]: path, type, sha256, size, mode, link_target (sorted by path)",
        "vendor_repos[]: path, head, tree, dirty_files[], tracked_diff_sha256, submodules[]",
        "build_inputs: package/resolved hashes, root package hashes, path roots, pin count",
        "archives[]: kind, repo, path, sha256, size, prerequisite, full_history, head, commit_count, file_count",
    ],
    "source_excludes": [
        "generated_at_utc, toolchain (environment, not source)",
        "boundary and entry_guards (derived checks over covered bytes, recomputed on verify)",
        "outer_repo branch/remotes/remote_ref_count/local_only_head/head_in_remote_branch",
        "files[].git_state (tracking state, not content)",
        "vendor_repos[] branch/remotes/remote_ref_count/head_in_remote_branch/local_only_head",
        "artifact_stamp, artifacts[], runner_sha256, open_conditions, source_revision",
        "d1_execution_binding (status, not source)",
    ],
    "runner_covers": [
        "all source_covers fields",
        "artifacts[]: path, expected, present, kind, sha256, size",
        "artifact_stamp: source_sha256, artifacts_sha256, commands (command + exit only), toolchain",
    ],
    "runner_excludes": [
        "artifact mtime_utc and fresh_against_scope (ordering, not identity)",
        "artifact_stamp.built_at_utc (a timestamp, not identity)",
        "artifact_stamp.source_sha256_matches (a verification flag, already implied)",
        "artifact_stamp.commands[].stdout_tail/stderr_tail (build log, not identity)",
        "generated_at_utc, runner_sha256, open_conditions, source_revision",
        "d1_execution_binding (status, not source)",
    ],
    "self_reference_exclusions": [
        "runner-manifest.json and its .sha256 sidecar are not in files[]",
        "the archive directory is not in files[]",
        "source_sha256 does not include runner_sha256 or artifact_stamp",
        "runner_sha256 does not include itself; it includes source_sha256 as a value",
    ],
    "stability": (
        "source_sha256 depends only on covered content and these rules; "
        "runner_sha256 additionally depends on artifact bytes and toolchain, "
        "so two builds of identical sources+artifacts yield the same runner_sha256"
    ),
    "sorting": (
        "files[] by path; archives[] by (repo, kind, path); vendor_repos[] in "
        "VENDOR_REPOS order; vendor dirty_files[] by path; submodules[] by path"
    ),
    "filesystem_semantics": (
        "files[] records type (file|symlink), permission bits, and symlink target; "
        "the outer tar preserves the same type, mode and link target"
    ),
}

# Files a build of the reviewed package actually consumes, plus the governance
# text the run is authorized under and this tool (so the manifest names its own
# producer). Anything outside this list is deliberately NOT frozen.
SCOPE_DIRS = [
    "simigo2-experimental/Sources",
    "simigo2-experimental/Tests",
]
SCOPE_FILES = [
    ".gitignore",
    # The root package is a different build path from the reviewed one (remote
    # pins instead of local vendor paths). It is recorded so the difference is
    # auditable, but it is NOT a build input of the stamped binaries.
    "Package.swift",
    "Package.resolved",
    "simigo2-experimental/Package.swift",
    "simigo2-experimental/Package.resolved",
    "tools/g3_runner_manifest.py",
    "tools/g3_build_stamped.py",
    "tools/g3_execution_identity.py",
]
GOVERNANCE_DIR = "docs/00-governance"
GOVERNANCE_PREFIX = "SIMIGO2_G3_"

VENDOR_REPOS = ["vendor/mlx-swift", "vendor/mlx-swift-lm"]

# Artifacts that must exist and be built from the frozen snapshot. A present but
# STALE binary is not bound to the sources, so both absence and staleness are
# G7b failures for this set.
ARTIFACTS = [
    "simigo2-experimental/.build/out/Products/Debug/g3-swift-isolation-entry",
    "simigo2-experimental/.build/out/Products/Debug/SimiGo2ExperimentalTests.xctest",
    "simigo2-experimental/.build/out/Products/Debug/SimiGoRuntimeContractTests.xctest",
    # Phase 1 (G6/G7a/G7b/G8a): the real D1 worker, supervisor and their test
    # bundle. They are now EXPECTED, so a missing or stale worker fails the
    # artifact gate — the precondition for a genuine `bound` execution identity.
    "simigo2-experimental/.build/out/Products/Debug/G3D1Worker",
    "simigo2-experimental/.build/out/Products/Debug/G3D1Supervisor",
    "simigo2-experimental/.build/out/Products/Debug/G3D1SupervisorTests.xctest",
]

# D1 targets that do not exist yet. Phase 1 promoted the worker/supervisor/tests
# into ARTIFACTS above, so this list is now empty. It is retained (never removed)
# so the `--require-artifacts` semantics stay: a future not-yet-built target goes
# here when it is recorded-but-open, and an absent WORKER means G6 is open, not
# that G7b is green.
PENDING_ARTIFACTS: list[str] = []

# G8b: the D1 gate control point is the only target allowed to sit between the
# authorization layer and the contract module. Its dependency set is a
# machine-checkable boundary: it can reach the MLX-free contract and NOTHING that
# can run a model or the ungated continuation. A change to this edge is a change
# to the frozen Package.swift and therefore to `source_sha256`.
D1_ENTRY_TARGET = "G3SwiftIsolationEntry"
D1_ENTRY_ALLOWED_TARGETS = ["SimiGoRuntimeContract"]
# The ungated surface lives here. A future D1 worker must not depend on it
# directly; it may only reach it through its reviewed facade target.
UNGATED_SURFACE_TARGETS = ["SimiGo2Experimental"]
D1_WORKER_TARGET = "G3D1Worker"
# The shared contract-only logic the worker and supervisor both link. The worker's
# isolation is only real transitively: G3D1Worker -> G3D1WorkerCore -> contract, so
# the closure (not just the direct edge) must never reach the ungated surface.
D1_WORKER_CORE_TARGET = "G3D1WorkerCore"

SKIP_DIR_NAMES = {".build", "__pycache__", ".git", ".swiftpm"}

# Only these in-scope paths actually feed the Swift build. Freshness must be
# measured against them alone: this tool and the repo's .gitignore are frozen
# for review, but editing them does not make an existing binary stale.
BUILD_INPUT_PREFIXES = (
    "simigo2-experimental/Sources/",
    "simigo2-experimental/Tests/",
    "simigo2-experimental/Package.swift",
    "simigo2-experimental/Package.resolved",
)


def is_build_input(path: str) -> bool:
    return path.startswith(BUILD_INPUT_PREFIXES)


def run_git(repo: Path, *args: str) -> tuple[int, str]:
    proc = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode, proc.stdout.strip()


def run_git_raw(repo: Path, *args: str) -> tuple[int, str]:
    """Like run_git but preserves leading whitespace.

    Porcelain v1 begins worktree-only changes with a space (` M path`); stripping
    it shifts every field and silently corrupts the path and the status code.
    """
    proc = subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode, proc.stdout.rstrip("\n")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def dir_digest(path: Path) -> tuple[str, int]:
    """Content digest of a bundle directory: sorted relative paths + file bytes."""
    entries: list[tuple[str, str]] = []
    total = 0
    for child in sorted(path.rglob("*")):
        if child.is_file() and not child.is_symlink():
            entries.append((child.relative_to(path).as_posix(), sha256_file(child)))
            total += child.stat().st_size
    payload = json.dumps(entries, separators=(",", ":"), ensure_ascii=False)
    return sha256_bytes(payload.encode("utf-8")), total


def utc(ts: float) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def git_status_map(repo: Path, pathspecs: list[str]) -> dict[str, str]:
    """path -> porcelain status code for tracked changes and untracked files."""
    _, raw = run_git_raw(
        repo, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--", *pathspecs
    )
    mapping: dict[str, str] = {}
    tokens = raw.split("\0")
    index = 0
    while index < len(tokens):
        entry = tokens[index]
        index += 1
        if not entry:
            continue
        code, path = entry[:2], entry[3:]
        if code[0] in "RC" and index < len(tokens):
            index += 1  # -z puts the rename source in the next token
        if "D" in code:
            mapping[path] = "deleted"
        elif code == "??":
            mapping[path] = "untracked"
        elif code[0] != " ":
            mapping[path] = "staged"
        else:
            mapping[path] = "modified"
    return mapping


def collect_scope_files() -> list[dict]:
    status = git_status_map(ROOT, SCOPE_DIRS + SCOPE_FILES)
    files: list[dict] = []

    def add(path: Path) -> None:
        rel = path.relative_to(ROOT).as_posix()
        # Preserve filesystem semantics, not only bytes: a symlink is recorded
        # with its target, and the mode keeps the executable bit. The tar
        # carrier reproduces the same type/mode/target.
        if path.is_symlink():
            target = os.readlink(path)
            data = target.encode("utf-8")
            files.append(
                {
                    "path": rel,
                    "type": "symlink",
                    "sha256": sha256_bytes(data),
                    "size": len(data),
                    "mode": path.lstat().st_mode & 0o777,
                    "link_target": target,
                    "git_state": status.get(rel, "clean"),
                }
            )
            return
        if not path.is_file():
            return
        st = path.stat()
        files.append(
            {
                "path": rel,
                "type": "file",
                "sha256": sha256_file(path),
                "size": st.st_size,
                "mode": stat.S_IMODE(st.st_mode),
                "link_target": None,
                "git_state": status.get(rel, "clean"),
            }
        )

    for rel_dir in SCOPE_DIRS:
        base = ROOT / rel_dir
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*")):
            if any(part in SKIP_DIR_NAMES for part in path.relative_to(base).parts):
                continue
            add(path)
    for rel_file in SCOPE_FILES:
        add(ROOT / rel_file)
    gov = ROOT / GOVERNANCE_DIR
    if gov.is_dir():
        for path in sorted(gov.iterdir()):
            if path.is_file() and path.name.startswith(GOVERNANCE_PREFIX):
                add(path)
    return sorted(files, key=lambda item: item["path"])


def status_counts(repo: Path) -> dict[str, int]:
    """Repo-wide counts only: unrelated work is counted, never hashed."""
    _, raw = run_git_raw(repo, "status", "--porcelain=v1", "--untracked-files=all")
    counts = {"untracked": 0, "modified": 0, "staged": 0}
    for line in raw.splitlines():
        if not line.strip():
            continue
        code = line[:2]
        if code == "??":
            counts["untracked"] += 1
        elif code[0] != " ":
            counts["staged"] += 1
        else:
            counts["modified"] += 1
    return counts


def repo_snapshot(
    repo_rel: str,
    include_submodules: bool = True,
    dirty_pathspecs: list[str] | None = None,
) -> dict:
    repo = ROOT / repo_rel
    head_code, head = run_git(repo, "rev-parse", "HEAD")
    if head_code != 0:
        return {"path": repo_rel, "error": "not a git repository"}
    _, branch = run_git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    _, tree = run_git(repo, "rev-parse", "HEAD^{tree}")
    upstream_code, upstream = run_git(
        repo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"
    )
    _, containing = run_git(repo, "branch", "-r", "--contains", "HEAD")
    remote_containment = sorted(
        line.strip() for line in containing.splitlines() if line.strip()
    )
    _, remote_raw = run_git(repo, "remote", "-v")
    remotes: dict[str, str] = {}
    for line in remote_raw.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] not in remotes:
            remotes[parts[0]] = parts[1]
    _, remote_refs = run_git(repo, "branch", "-r")
    remote_ref_count = len([line for line in remote_refs.splitlines() if line.strip()])

    status = git_status_map(repo, dirty_pathspecs or ["."])
    dirty: list[dict] = []
    for rel, code in sorted(status.items()):
        on_disk = repo / rel
        dirty.append(
            {
                "path": rel,
                "status": code,
                "sha256": sha256_file(on_disk) if on_disk.is_file() else None,
            }
        )

    diff_code, diff = run_git(repo, "diff", "HEAD", "--binary", *(dirty_pathspecs or []))
    submodules: list[dict] = []
    if include_submodules:
        _, sub_raw = run_git(repo, "submodule", "status", "--recursive")
        for line in sub_raw.splitlines():
            if not line.strip():
                continue
            marker, rest = line[0], line[1:]
            parts = rest.split()
            if len(parts) < 2:
                continue
            sub_path, sub_head = parts[1], parts[0]
            info: dict = {
                "path": sub_path,
                "head": sub_head,
                "initialized": marker != "-",
                "pointer_matches": marker != "+",
            }
            sub_dir = repo / sub_path
            if info["initialized"] and sub_dir.is_dir():
                sub_branch_code, sub_branch = run_git(
                    sub_dir, "rev-parse", "--abbrev-ref", "HEAD"
                )
                info["branch"] = sub_branch if sub_branch_code == 0 else None
                _, sub_containing = run_git(
                    sub_dir, "branch", "-r", "--contains", "HEAD"
                )
                info["remote_containment"] = sorted(
                    item.strip() for item in sub_containing.splitlines() if item.strip()
                )
                _, sub_status = run_git(
                    sub_dir, "status", "--porcelain=v1", "--untracked-files=all"
                )
                info["dirty"] = bool(sub_status.strip())
            submodules.append(info)

    return {
        "path": repo_rel,
        "head": head,
        "branch": branch,
        "tree": tree,
        "upstream": upstream if upstream_code == 0 else None,
        "remotes": [
            {"name": name, "url": url} for name, url in sorted(remotes.items())
        ],
        "remote_ref_count": remote_ref_count,
        "head_in_remote_branch": remote_containment,
        "local_only_head": not remote_containment,
        "dirty_files": dirty,
        "dirty_files_scope": (
            "declared scope only" if dirty_pathspecs is not None else "whole repository"
        ),
        "tracked_diff_sha256": sha256_bytes(diff.encode("utf-8")) if diff else None,
        "submodules": submodules,
    }


def toolchain() -> dict:
    proc = subprocess.run(
        ["swift", "--version"], capture_output=True, text=True, check=False
    )
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    return {
        "swift": lines[:2],
        "swift_exit": proc.returncode,
        "macos": platform.mac_ver()[0],
        "machine": platform.machine(),
        "python": platform.python_version(),
    }


def build_inputs(files: list[dict]) -> dict:
    by_path = {item["path"]: item for item in files}
    package = by_path.get("simigo2-experimental/Package.swift", {})
    resolved = by_path.get("simigo2-experimental/Package.resolved", {})
    resolved_text = ""
    resolved_path = ROOT / "simigo2-experimental/Package.resolved"
    if resolved_path.is_file():
        resolved_text = resolved_path.read_text(encoding="utf-8", errors="replace")
    return {
        "package_swift_sha256": package.get("sha256"),
        "package_resolved_sha256": resolved.get("sha256"),
        # Snapshot completeness only: the root manifest builds the same sources
        # but pins REMOTE forks, so it does not include the vendor observer fix.
        # A D1 worker must be built from simigo2-experimental/Package.swift.
        "root_package_swift_sha256": by_path.get("Package.swift", {}).get("sha256"),
        "root_package_resolved_sha256": by_path.get("Package.resolved", {}).get("sha256"),
        # Directly usable as the marker's `package_sha256`.
        "package_sha256": sha256_bytes(
            json.dumps(
                [package.get("sha256"), resolved.get("sha256")],
                separators=(",", ":"),
            ).encode("utf-8")
        ),
        "path_dependency_roots": ["../vendor/mlx-swift", "../vendor/mlx-swift-lm"],
        # Path dependencies are not written to Package.resolved, so a zero here
        # means the lockfile records no identity for either fork.
        "resolved_fork_pin_count": resolved_text.count('"mlx-swift'),
    }


def artifact_snapshot(newest_scope_mtime: float | None) -> list[dict]:
    artifacts: list[dict] = []
    for rel in ARTIFACTS + PENDING_ARTIFACTS:
        expected = rel in ARTIFACTS
        path = ROOT / rel
        if not path.exists():
            artifacts.append({"path": rel, "present": False, "expected": expected})
            continue
        if path.is_dir():
            digest, size = dir_digest(path)
            mtime = max(
                (child.stat().st_mtime for child in path.rglob("*") if child.is_file()),
                default=path.stat().st_mtime,
            )
            kind = "bundle"
        else:
            digest, size = sha256_file(path), path.stat().st_size
            mtime = path.stat().st_mtime
            kind = "executable"
        artifacts.append(
            {
                "path": rel,
                "expected": expected,
                "present": True,
                "kind": kind,
                "sha256": digest,
                "size": size,
                "mtime_utc": utc(mtime),
                # Freshness compares wall-clock build time to wall-clock source
                # time. It is evidence about ordering, not about content, so it
                # never enters a digest.
                "fresh_against_scope": (
                    newest_scope_mtime is None or mtime >= newest_scope_mtime
                ),
            }
        )
    return artifacts


def normalize_bundle_dir(bundle_dir: Path) -> Path:
    """Resolve an archive directory against ROOT, never against the process cwd.

    `git -C <vendor>` changes the meaning of a relative target path; a relative
    archive dir would then be created inside the vendor repo (or fail), and the
    manifest would record a null hash without failing. Normalizing once keeps
    `--out` and the archive hashes pointing at the same files.
    """
    return (bundle_dir if bundle_dir.is_absolute() else ROOT / bundle_dir).resolve()


def outer_worktree_archive(
    bundle_dir: Path, files: list[dict], write: bool = True
) -> dict:
    """Freeze the FULL BYTES of every in-scope file, not just its hash.

    Per-file SHA256 proves identity only for someone who already has the bytes.
    The reviewed implementation lives in untracked files and uncommitted edits,
    so a third party cannot obtain it from the outer HEAD. This deterministic
    tar (sorted entries, zeroed mtime/uid/gid, no compression) is the carrier:
    extracting it reproduces the exact snapshot the manifest names.
    """
    payload = io.BytesIO()
    with tarfile.open(fileobj=payload, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for item in files:
            info = tarfile.TarInfo(item["path"])
            info.mtime = 0
            info.mode = item["mode"]
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            if item["type"] == "symlink":
                info.type = tarfile.SYMTYPE
                info.linkname = item["link_target"]
                info.size = 0
                tar.addfile(info)
                continue
            data = (ROOT / item["path"]).read_bytes()
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
    data = payload.getvalue()
    target = bundle_dir / "outer_worktree.tar"
    if write:
        target.write_bytes(data)
    return {
        "kind": "worktree-archive",
        "repo": ".",
        "path": target.name,
        "sha256": sha256_bytes(data),
        "size": len(data),
        "file_count": len(files),
        "format": "posix-tar",
        "preserves": ["type", "mode", "link_target", "bytes"],
        "content": "full bytes of every in-scope file",
    }


def archive_snapshot(
    bundle_dir: Path, files: list[dict], write: bool = True
) -> list[dict]:
    """Freeze commits that no remote can serve, and uncommitted vendor diffs.

    A manifest that names a local-only commit is not reproducible: nobody else
    can obtain that object. A bundle makes the commit transportable and the
    recorded SHA256 makes it immutable for this snapshot. The outer worktree
    archive carries the untracked/uncommitted outer sources themselves.
    """
    archives: list[dict] = []
    bundle_dir = normalize_bundle_dir(bundle_dir)
    if write:
        bundle_dir.mkdir(parents=True, exist_ok=True)
    repo_rels = list(VENDOR_REPOS)
    for repo_rel in VENDOR_REPOS:
        repo = ROOT / repo_rel
        _, sub_raw = run_git(repo, "submodule", "status", "--recursive")
        for line in sub_raw.splitlines():
            if not line.strip():
                continue
            parts = line[1:].split()
            if len(parts) >= 2:
                repo_rels.append(f"{repo_rel}/{parts[1]}")

    for repo_rel in repo_rels:
        repo = ROOT / repo_rel
        if not (repo / ".git").exists():
            continue
        code, local = run_git(repo, "rev-list", "HEAD", "--not", "--remotes")
        commits = local.split() if code == 0 else []
        _, remote_refs = run_git(repo, "branch", "-r")
        has_remote_refs = bool([line for line in remote_refs.splitlines() if line.strip()])
        safe = repo_rel.replace("/", "_")
        if commits:
            if has_remote_refs:
                base_code, base = run_git(repo, "rev-parse", f"{commits[-1]}^")
            else:
                # No remote-tracking refs: every commit looks local, so a
                # parent-based range would be meaningless. Freeze full history.
                base_code, base = 1, ""
            target = bundle_dir / f"{safe}.bundle"
            if base_code == 0:
                created = 0
                if write:
                    created, _ = run_git(
                        repo, "bundle", "create", str(target), f"{base}..HEAD", "HEAD"
                    )
                if (write and created == 0 or not write) and target.is_file():
                    archives.append(
                        {
                            "kind": "git-bundle",
                            "repo": repo_rel,
                            "path": target.name,
                            "sha256": sha256_file(target),
                            "size": target.stat().st_size,
                            "prerequisite": base,
                            "full_history": False,
                            "head": commits[0],
                            "commit_count": len(commits),
                        }
                    )
                else:
                    archives.append(
                        {
                            "kind": "git-bundle",
                            "repo": repo_rel,
                            "path": target.name,
                            "sha256": None,
                            "size": None,
                            "prerequisite": base,
                            "full_history": False,
                            "head": commits[0],
                            "commit_count": len(commits),
                        }
                    )
            else:
                target = bundle_dir / f"{safe}.bundle"
                created = 0
                if write:
                    created, _ = run_git(repo, "bundle", "create", str(target), "HEAD")
                present = target.is_file()
                archives.append(
                    {
                        "kind": "git-bundle",
                        "repo": repo_rel,
                        "path": target.name,
                        "sha256": sha256_file(target) if present else None,
                        "size": target.stat().st_size if present else None,
                        "prerequisite": None,
                        "full_history": True,
                        "head": commits[0],
                        "commit_count": len(commits),
                    }
                )
        _, dirty_diff = run_git(repo, "diff", "HEAD", "--binary")
        if dirty_diff:
            target = bundle_dir / f"{safe}.worktree.diff"
            if write:
                target.write_text(dirty_diff + "\n", encoding="utf-8")
            archives.append(
                {
                    "kind": "worktree-diff",
                    "repo": repo_rel,
                    "path": target.name,
                    "sha256": sha256_file(target) if target.is_file() else None,
                    "size": target.stat().st_size if target.is_file() else None,
                }
            )
    archives.append(outer_worktree_archive(bundle_dir, files, write))
    return sorted(archives, key=lambda item: (item["repo"], item["kind"], item["path"]))


def package_graph() -> dict:
    """Target dependency graph, straight from SwiftPM's own manifest parse."""
    proc = subprocess.run(
        ["swift", "package", "dump-package"],
        cwd=ROOT / "simigo2-experimental",
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        return {"available": False, "exit": proc.returncode, "targets": {}}
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError as error:
        return {"available": False, "exit": proc.returncode, "error": str(error), "targets": {}}
    targets: dict[str, list[str]] = {}
    for target in data.get("targets", []):
        deps: list[str] = []
        for dep in target.get("dependencies", []):
            if "byName" in dep:
                deps.extend(x for x in dep["byName"] if isinstance(x, str))
            elif "product" in dep:
                product = dep["product"]
                deps.append(product[0] if product and product[0] else "?")
            elif "target" in dep:
                deps.extend(x for x in dep["target"] if isinstance(x, str))
            else:
                deps.append("?")
        targets[target["name"]] = sorted(set(deps))
    return {"available": True, "exit": proc.returncode, "targets": targets}


def boundary_snapshot() -> dict:
    """G8b-A checks over the target dependency graph, plus the G8b-B non-claim.

    D1 adopts threat model CASE A: the worker is a reviewed, cooperating
    component. Under Case A the question is not "can an actively hostile
    in-process caller reach an ungated API" (it can: the executor module is
    linked and its public methods are public). The question is whether the
    reviewed entry's dependency set and calling convention are frozen and
    checkable. These checks answer that at the module level; they prove CODE
    UNREACHABILITY FOR THE REVIEWED ENTRY, not resistance to a bypass.

    Case B (structural closure of every ungated API) is NOT claimed and is
    recorded as `non_claims`, not as an open condition: it is out of scope by
    decision, not pending work.
    """
    graph = package_graph()
    targets = graph.get("targets", {})
    checks: list[dict] = []

    entry = targets.get(D1_ENTRY_TARGET)
    entry_ok = graph.get("available", False) and entry is not None and set(entry) <= set(
        D1_ENTRY_ALLOWED_TARGETS
    )
    checks.append(
        {
            "id": "G8b-A.entry_dependency_set",
            "subject": D1_ENTRY_TARGET,
            "observed": entry,
            "allowed": D1_ENTRY_ALLOWED_TARGETS,
            "evidence_class": "module_unreachability",
            "passed": entry_ok,
        }
    )
    for forbidden in UNGATED_SURFACE_TARGETS:
        checks.append(
            {
                "id": f"G8b-A.entry_excludes.{forbidden}",
                "subject": D1_ENTRY_TARGET,
                "observed": entry,
                "forbidden": forbidden,
                "evidence_class": "module_unreachability",
                "passed": graph.get("available", False)
                and entry is not None
                and forbidden not in entry,
            }
        )
    worker = targets.get(D1_WORKER_TARGET)
    checks.append(
        {
            "id": "G8b-A.worker_dependency_set",
            "subject": D1_WORKER_TARGET,
            "observed": worker,
            "forbidden": UNGATED_SURFACE_TARGETS,
            "evidence_class": "module_unreachability",
            "applicable": worker is not None,
            "note": (
                None
                if worker is not None
                else "target absent (G6 gap); this check binds as soon as the D1 worker target exists"
            ),
            "passed": worker is None
            or not (set(worker) & set(UNGATED_SURFACE_TARGETS)),
        }
    )

    # Transitive closure: the worker's isolation is only real if NONE of the
    # targets it links (directly or through its shared core lib) reach the
    # ungated surface. A direct-edge check alone could be satisfied while a
    # helper target pulled in SimiGo2Experimental, so the closure is the claim.
    def closure(name: str) -> set[str]:
        seen: set[str] = set()
        stack = [name]
        while stack:
            cur = stack.pop()
            for dep in targets.get(cur, []):
                if dep not in seen:
                    seen.add(dep)
                    stack.append(dep)
        return seen

    worker_closure = closure(D1_WORKER_TARGET) if worker is not None else None
    checks.append(
        {
            "id": "G8b-A.worker_transitive_closure_excludes_ungated",
            "subject": D1_WORKER_TARGET,
            "observed": sorted(worker_closure) if worker_closure is not None else None,
            "forbidden": UNGATED_SURFACE_TARGETS,
            "evidence_class": "module_unreachability",
            "applicable": worker is not None,
            "passed": worker is None
            or not (set(worker_closure or set()) & set(UNGATED_SURFACE_TARGETS)),
        }
    )
    return {
        "method": "swift package dump-package",
        "threat_model": "case_a_reviewed_cooperating_worker",
        "available": graph.get("available", False),
        "targets": {
            name: targets.get(name)
            for name in sorted(
                set(targets)
                & {
                    D1_ENTRY_TARGET,
                    D1_WORKER_TARGET,
                    D1_WORKER_CORE_TARGET,
                    *UNGATED_SURFACE_TARGETS,
                }
            )
        },
        "checks": checks,
        "non_claims": [
            "G8b-B: no claim that an actively hostile caller is structurally prevented "
            "from calling the ungated public API of the linked executor module",
            "a second PID and a supervisor do not by themselves close G8b-B: the worker "
            "still links the executor module unless a separate facade/visibility "
            "mechanism is proven",
            "G8b-A covers the reviewed entry's dependency set, calling convention and "
            "artifact identity; it is not a sandbox",
        ],
    }


GUARD_SOURCES = {
    "runner": "simigo2-experimental/Sources/SimiGoRuntimeContract/G3DualArmRunner.swift",
    "executor": "simigo2-experimental/Sources/SimiGo2Experimental/MLXPrefixRecomputeExecutor.swift",
}


def _read_scope(path: str) -> str:
    file = ROOT / path
    return file.read_text(encoding="utf-8") if file.is_file() else ""


def _gated_executor_body(source: str) -> str | None:
    """The post-gate body that owns the session admission guard."""
    start = source.find("func runGatedGeneration(")
    end = source.find("// MARK: - Per-arm cache-backed G3 generation", start)
    if start < 0 or end < 0:
        return None
    return source[start:end]


def _public_gated_entry_body(source: str) -> str | None:
    """The public `continueExecutionG3` body that must delegate inside the gate."""
    anchor = "let run = try await G3FirstGenerationEntry.runAsync("
    idx = source.find(anchor)
    if idx < 0:
        return None
    start = source.rfind("public func continueExecutionG3(", 0, idx)
    end = source.find("/// The body of the cleared-gate closure", idx)
    if start < 0 or end < 0:
        return None
    return source[start:end]


def entry_guard_snapshot() -> dict:
    """G8a structural checks, recorded next to the module boundary.

    These answer "is the refusal placed before the side effects?" at the source
    level. They are NOT runtime-refusal evidence: the executor guard sits behind
    a cleared gate, and no trusted live provider exists to clear it. The runtime
    refusal has TWO independent layers: the runner wiring tests (no dispatch
    without a session) and the gated-body admission test (no model entry, no
    binding consumption).
    """
    runner = _read_scope(GUARD_SOURCES["runner"])
    executor = _read_scope(GUARD_SOURCES["executor"])
    body = _gated_executor_body(executor)
    checks: list[dict] = []

    required = (
        re.search(
            r"makeCacheSession:\s*G3PerArmCacheSessionFactory(?=\s*[,)])", runner
        )
        is not None
    )
    optional = (
        re.search(r"makeCacheSession:\s*G3PerArmCacheSessionFactory\s*\?", runner)
        is not None
    ) or (
        re.search(r"makeCacheSession:\s*G3PerArmCacheSessionFactory\s*=\s*nil", runner)
        is not None
    )
    checks.append(
        {
            "id": "G8a.runner_factory_required",
            "subject": GUARD_SOURCES["runner"],
            "evidence_class": "type_enforced",
            "observed": {"required_parameter": required, "optional_form": optional},
            "passed": required and not optional,
        }
    )

    public_body = _public_gated_entry_body(executor)
    if public_body is None:
        checks.append(
            {
                "id": "G8a.public_entry_delegates_inside_gate",
                "subject": GUARD_SOURCES["executor"],
                "evidence_class": "source_order",
                "observed": None,
                "passed": False,
                "note": "public gated entry body not found",
            }
        )
    else:
        gate = public_body.find("G3FirstGenerationEntry.runAsync(")
        delegate = public_body.find("self.runGatedGeneration(")
        side_effects = {
            token: public_body.find(token)
            for token in (
                "context.model(",
                "consumeBinding(",
                "claimContinuation()",
                "G3RunSettlement(",
            )
        }
        checks.append(
            {
                "id": "G8a.public_entry_delegates_inside_gate",
                "subject": GUARD_SOURCES["executor"],
                "evidence_class": "source_order",
                "observed": {
                    "gate_offset": gate,
                    "delegate_offset": delegate,
                    "side_effect_offsets": side_effects,
                },
                "passed": 0 <= gate < delegate
                and all(offset < 0 for offset in side_effects.values()),
            }
        )

    if body is None:
        checks.append(
            {
                "id": "G8a.executor_guard_precedes_side_effects",
                "subject": GUARD_SOURCES["executor"],
                "evidence_class": "source_order",
                "observed": None,
                "passed": False,
                "note": "gated method body not found",
            }
        )
    else:
        guard = body.find("guard let session = self.g3CacheSession else {")
        raise_at = body.find("missingCacheSession(", max(guard, 0))
        call = body.find("continueExecutionG3WithPerArmCache(")
        side_effects = {
            token: body.find(token)
            for token in (
                "context.model(",
                "consumeBinding(",
                "claimContinuation()",
                "G3RunSettlement(",
            )
        }
        checks.append(
            {
                "id": "G8a.executor_guard_precedes_side_effects",
                "subject": GUARD_SOURCES["executor"],
                "evidence_class": "source_order",
                "observed": {
                    "guard_offset": guard,
                    "throw_offset": raise_at,
                    "per_arm_call_offset": call,
                    "side_effect_offsets": side_effects,
                },
                "passed": 0 <= guard < raise_at < call
                and all(offset < 0 for offset in side_effects.values()),
            }
        )
        checks.append(
            {
                "id": "G8a.executor_no_recompute_fallback",
                "subject": GUARD_SOURCES["executor"],
                "evidence_class": "source_order",
                "observed": {
                    "ungated_call_offsets": [
                        match.start()
                        for match in re.finditer(r"self\.continueExecution\s*\(", body)
                    ]
                },
                "passed": re.search(r"self\.continueExecution\s*\(", body) is None,
            }
        )
        # The negative test drives this exact function. A conditional-compilation
        # branch would mean the tested body is not necessarily the shipped one.
        checks.append(
            {
                "id": "G8a.gated_body_has_no_conditional_compilation",
                "subject": GUARD_SOURCES["executor"],
                "evidence_class": "source_order",
                "observed": {"directives": re.findall(r"#(?:if|elseif|else|endif)\b", body)},
                "passed": re.search(r"#(?:if|elseif|else|endif)\b", body) is None,
            }
        )

    return {"method": "source scan of the gated executor entry", "checks": checks}


EXECUTION_RECORD = "docs/02-evidence/g3-d1-source-freeze/execution/execution-identity.json"


def execution_binding_snapshot(manifest: dict) -> dict:
    """Attach the execution-identity record WITHOUT creating a digest cycle.

    The record binds `source_sha256` + `runner_sha256` + the staged worker hash.
    Both digests exclude this section, so stamping the record's own hash back
    into the manifest leaves the digests the record names unchanged. That is
    what lets the chain close: manifest -> record -> marker -> launched PID,
    with no field that has to contain its own hash.
    """
    record = ROOT / EXECUTION_RECORD
    if not record.is_file():
        return {
            "status": "unclosed",
            "record": EXECUTION_RECORD,
            "reason": "no execution identity record",
            "source_sha256_matches": None,
            "runner_sha256_matches": None,
        }
    payload = json.loads(record.read_text(encoding="utf-8"))
    named = payload.get("manifest") or {}
    source_matches = named.get("source_sha256") == manifest["source_sha256"]
    runner_matches = named.get("runner_sha256") == manifest["runner_sha256"]
    reasons: list[str] = []
    if not source_matches:
        reasons.append("record names a different source_sha256")
    if not runner_matches:
        reasons.append("record names a different runner_sha256")
    recorded_status = payload.get("status")
    status = recorded_status if not reasons else "stale"
    if recorded_status == "unclosed":
        reasons.append(payload.get("reason") or "record is unclosed")
    snapshot = {
        "status": status,
        "record": EXECUTION_RECORD,
        "record_sha256": sha256_file(record),
        "stand_in": bool(payload.get("stand_in")),
        "source_sha256_matches": source_matches,
        "runner_sha256_matches": runner_matches,
        "worker": payload.get("worker", {}).get("path"),
        "worker_sha256": payload.get("worker", {}).get("sha256"),
        "marker": (payload.get("marker") or {}).get("id"),
        "marker_consumed": (payload.get("marker") or {}).get("consumed"),
        "launch_pid": (payload.get("launch") or {}).get("pid"),
        "launch_running_executable": (payload.get("launch") or {}).get(
            "running_executable_path"
        ),
        "launch_match": (payload.get("launch") or {}).get("match"),
        "reasons": reasons,
    }
    if status == "control-only":
        reasons.append(
            "control-only stand-in: the mechanism was demonstrated, but the D1 worker is absent"
        )
        snapshot["note"] = (
            "mechanism demonstrated with a stand-in binary; this is NOT a bound "
            "D1 worker and does not close G7b execution identity"
        )
    return snapshot


def open_conditions(manifest: dict) -> list[str]:
    conditions: list[str] = []
    outer = manifest["outer_repo"]
    if manifest["build_inputs"]["resolved_fork_pin_count"] == 0:
        conditions.append(
            "Package.resolved records no pin for either vendored fork (path dependencies)"
        )
    if outer["dirty_files"]:
        conditions.append(
            f"outer worktree has {len(outer['dirty_files'])} in-scope files that differ from HEAD"
        )
    untracked = [
        item["path"] for item in manifest["files"] if item["git_state"] == "untracked"
    ]
    if untracked:
        conditions.append(
            f"{len(untracked)} in-scope source files are untracked (not in any commit)"
        )
    for repo in manifest["vendor_repos"]:
        if repo.get("local_only_head"):
            conditions.append(
                f"{repo['path']} HEAD {repo['head'][:9]} is not contained in any remote branch"
            )
        if repo.get("remote_ref_count") == 0:
            conditions.append(
                f"{repo['path']} has no remote-tracking refs; published state is unknowable"
            )
        if repo.get("dirty_files"):
            conditions.append(
                f"{repo['path']} has {len(repo['dirty_files'])} uncommitted file(s)"
            )
        for sub in repo.get("submodules", []):
            if sub.get("initialized") and not sub.get("remote_containment"):
                conditions.append(
                    f"{repo['path']}/{sub['path']} submodule HEAD {sub['head'][:9]} "
                    "is not contained in any remote branch"
                )
            if sub.get("initialized") and sub.get("dirty"):
                conditions.append(
                    f"{repo['path']}/{sub['path']} submodule worktree is dirty"
                )
    for archive in manifest.get("archives", []):
        if archive.get("sha256") is None:
            conditions.append(f"archive missing: {archive['path']}")
    binding = manifest.get("d1_execution_binding") or {}
    if binding.get("status") != "bound":
        conditions.append(
            "execution identity not bound: "
            f"{binding.get('status')}"
            + (f" ({'; '.join(binding.get('reasons') or [])})" if binding.get("reasons") else "")
        )
    stamp = manifest.get("artifact_stamp") or {}
    stamped_paths = set(stamp.get("artifacts_sha256") or {})
    for artifact in manifest["artifacts"]:
        if not artifact.get("present"):
            if artifact.get("expected", True):
                conditions.append(f"required artifact absent: {artifact['path']}")
            else:
                conditions.append(
                    f"pending D1 artifact not built (G6/G7a): {artifact['path']}"
                )
        elif (
            artifact.get("fresh_against_scope") is False
            and artifact["path"] not in stamped_paths
        ):
            # mtime is only a fallback signal. A stamp that names this artifact's
            # hash together with the post-build source digest supersedes it.
            conditions.append(f"artifact older than the frozen sources: {artifact['path']}")
    boundary = manifest.get("boundary", {})
    if not boundary.get("available"):
        conditions.append("target dependency graph unavailable; G8b boundary not evaluated")
    for check in boundary.get("checks", []):
        if not check.get("passed"):
            conditions.append(f"G8b boundary check failed: {check['id']}")
    guards = manifest.get("entry_guards", {})
    for check in guards.get("checks", []):
        if not check.get("passed"):
            conditions.append(f"G8a entry-guard check failed: {check['id']}")
    stamp = manifest.get("artifact_stamp")
    if not stamp:
        conditions.append(
            "no artifact stamp: binaries are not bound to the frozen source digest"
        )
    elif not stamp.get("source_sha256_matches"):
        conditions.append("artifact stamp was produced from a different source digest")
    return conditions


def compute_digests(manifest: dict) -> tuple[str, str]:
    # Repo-wide status counts are context, not identity: writing this manifest
    # adds untracked files, so counting them inside the digest would make the
    # digest drift on the very act of recording it.
    outer = {
        key: value
        for key, value in manifest["outer_repo"].items()
        if key != "repo_wide_status_counts"
    }
    # Source identity is CONTENT ONLY. Environment (toolchain, timestamps) and
    # derived checks (boundary, entry guards) are recorded but excluded: a
    # checker edit must not look like a source change, and a clock must not
    # change identity. Every exclusion is named in DIGEST_RULES.
    source_payload = {
        "schema_id": manifest["schema_id"],
        "digest_rules": manifest["digest_rules"],
        "scope": manifest["scope"],
        "outer_repo": outer,
        "vendor_repos": manifest["vendor_repos"],
        "build_inputs": manifest["build_inputs"],
        "files": manifest["files"],
        "archives": manifest["archives"],
    }
    source_digest = sha256_bytes(
        json.dumps(source_payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode(
            "utf-8"
        )
    )
    runner_artifacts = [
        {key: value for key, value in art.items() if key not in ("mtime_utc", "fresh_against_scope")}
        for art in manifest["artifacts"]
    ]
    stamp = manifest.get("artifact_stamp")
    stamp_identity = None
    if stamp:
        # built_at_utc is a build time and source_sha256_matches is the builder's
        # own assertion; neither is part of the identity being digested. The
        # stamp's source_sha256 (a value) still binds the artifacts to the source.
        stamp_identity = {
            key: value
            for key, value in stamp.items()
            if key not in ("built_at_utc", "source_sha256_matches")
        }
        if isinstance(stamp_identity.get("commands"), list):
            # A build log line is diagnostics, not identity: identical commands
            # can print different progress tails on an incremental rebuild.
            stamp_identity["commands"] = [
                {"command": item.get("command"), "exit": item.get("exit")}
                for item in stamp_identity["commands"]
                if isinstance(item, dict)
            ]
    runner_payload = dict(
        source_payload,
        artifacts=runner_artifacts,
        artifact_stamp=stamp_identity,
    )
    runner_digest = sha256_bytes(
        json.dumps(runner_payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode(
            "utf-8"
        )
    )
    return source_digest, runner_digest


def build_manifest(
    bundle_dir: Path | None = None,
    write_archives: bool = True,
    artifact_stamp: dict | None = None,
) -> dict:
    files = collect_scope_files()
    newest = max(
        (
            (ROOT / item["path"]).stat().st_mtime
            for item in files
            if is_build_input(item["path"])
        ),
        default=None,
    )
    archives = archive_snapshot(bundle_dir, files, write_archives) if bundle_dir else []
    manifest: dict = {
        "schema_id": SCHEMA_ID,
        "digest_rules": DIGEST_RULES,
        "generated_at_utc": utc(datetime.now(tz=timezone.utc).timestamp()),
        "scope": {
            "dirs": SCOPE_DIRS,
            "files": SCOPE_FILES,
            "governance_prefix": f"{GOVERNANCE_DIR}/{GOVERNANCE_PREFIX}",
            "excluded": ["simigo2-experimental/.build", "**/__pycache__", ".git"],
        },
        "toolchain": toolchain(),
        "outer_repo": repo_snapshot(
            ".", include_submodules=True, dirty_pathspecs=SCOPE_DIRS + SCOPE_FILES
        ),
        "vendor_repos": [repo_snapshot(rel) for rel in VENDOR_REPOS],
        "build_inputs": build_inputs(files),
        "boundary": boundary_snapshot(),
        "entry_guards": entry_guard_snapshot(),
        "files": files,
        "archive_dir": (
            normalize_bundle_dir(bundle_dir).relative_to(ROOT).as_posix()
            if bundle_dir and normalize_bundle_dir(bundle_dir).is_relative_to(ROOT)
            else None
        ),
        "archives": archives,
        "artifacts": artifact_snapshot(newest),
        # Written by tools/g3_build_stamped.py. It records the source digest
        # measured BEFORE the build, so `source_sha256` equality after the build
        # is evidence that the artifacts were produced from this snapshot —
        # stronger than mtime ordering, which a file save can invalidate without
        # changing any byte.
        "artifact_stamp": artifact_stamp,
        "scope_newest_mtime_utc": utc(newest) if newest else None,
        "repo_context": {
            "note": "counts only; unrelated work is never hashed or digested",
            "outer_status_counts": status_counts(ROOT),
            "vendor_status_counts": {
                rel: status_counts(ROOT / rel) for rel in VENDOR_REPOS
            },
        },
    }
    manifest["source_sha256"], manifest["runner_sha256"] = compute_digests(manifest)
    manifest["source_revision"] = (
        f"{manifest['outer_repo']['head'][:8]}+g3.{manifest['source_sha256'][:12]}"
    )
    # Recorded after the digests (it names them) and excluded from both, so
    # re-stamping with the record present cannot move either digest.
    manifest["d1_execution_binding"] = execution_binding_snapshot(manifest)
    manifest["open_conditions"] = open_conditions(manifest)
    return manifest


def verify_outer_archive(manifest: dict) -> list[str]:
    """Header-level check: the tar must name the reviewed type/mode/target/bytes.

    A matching archive SHA-256 only proves the archive bytes did not change. It
    does not prove extraction yields the reviewed filesystem semantics, so this
    walks the members and compares them to `files[]`. `extract_roundtrip`
    below goes one step further and stats the extracted tree.
    """
    archive_dir = manifest.get("archive_dir")
    if not archive_dir:
        return ["archive_dir missing; cannot verify the outer carrier"]
    archive = ROOT / archive_dir / "outer_worktree.tar"
    if not archive.is_file():
        return [f"outer archive missing: {archive.relative_to(ROOT).as_posix()}"]
    want = {item["path"]: item for item in manifest.get("files", [])}
    problems: list[str] = []
    # Hash the FILE ON DISK. Recomputing the tar from the worktree proves what a
    # fresh archive would contain, not that the recorded carrier is unchanged:
    # trailing bytes after the end-of-archive marker are ignored by tarfile and
    # would otherwise pass both the member walk and the extraction check.
    recorded = next(
        (
            item
            for item in manifest.get("archives", [])
            if item.get("path") == archive.name
        ),
        None,
    )
    on_disk = sha256_file(archive)
    if not recorded or recorded.get("sha256") != on_disk:
        problems.append(
            f"outer archive digest drift: {on_disk[:16]} != "
            f"{str((recorded or {}).get('sha256'))[:16]}"
        )
    with tarfile.open(archive) as tar:
        members = {member.name: member for member in tar.getmembers()}
        for name in sorted(set(want) | set(members)):
            if name not in members:
                problems.append(f"archive missing member: {name}")
                continue
            if name not in want:
                problems.append(f"archive extra member: {name}")
                continue
            item, member = want[name], members[name]
            if item.get("type") == "symlink":
                if not member.issym():
                    problems.append(f"archive type drift: {name}")
                elif member.linkname != item.get("link_target"):
                    problems.append(f"archive link target drift: {name}")
                continue
            if not member.isfile():
                problems.append(f"archive type drift: {name}")
                continue
            if (member.mode & 0o777) != item.get("mode"):
                problems.append(f"archive mode drift: {name}")
            extracted = tar.extractfile(member)
            if extracted is None:
                problems.append(f"archive member unreadable: {name}")
            elif sha256_bytes(extracted.read()) != item.get("sha256"):
                problems.append(f"archive content drift: {name}")
    return problems


def extract_roundtrip(manifest: dict, target: Path | None = None) -> tuple[list[str], dict]:
    """Extract the outer carrier and STAT the resulting worktree.

    Reading tar headers proves what the archive says; it does not prove what a
    restore produces. This extracts every member into a scratch directory and
    compares `lstat` type, permission bits, symlink target and bytes against
    `files[]`, then reports how many of each kind were actually exercised.
    """
    archive_dir = manifest.get("archive_dir")
    if not archive_dir:
        return ["archive_dir missing; cannot round-trip the outer carrier"], {}
    archive = ROOT / archive_dir / "outer_worktree.tar"
    if not archive.is_file():
        return [f"outer archive missing: {archive.relative_to(ROOT).as_posix()}"], {}
    want = {item["path"]: item for item in manifest.get("files", [])}
    scratch = Path(tempfile.mkdtemp(prefix="g3-roundtrip-")) if target is None else target
    problems: list[str] = []
    stats = {"files": 0, "symlinks": 0, "executable": 0}
    try:
        with tarfile.open(archive) as tar:
            members = tar.getmembers()
            for member in members:
                name = member.name
                if name.startswith("/") or ".." in Path(name).parts:
                    problems.append(f"unsafe archive member: {name}")
            if problems:
                return problems, stats
            tar.extractall(scratch)
        seen: set[str] = set()
        for rel, item in sorted(want.items()):
            path = scratch / rel
            seen.add(rel)
            if item["type"] == "symlink":
                stats["symlinks"] += 1
                if not path.is_symlink():
                    problems.append(f"restored type drift: {rel}")
                elif os.readlink(path) != item.get("link_target"):
                    problems.append(f"restored link target drift: {rel}")
                continue
            if path.is_symlink() or not path.is_file():
                problems.append(f"restored type drift: {rel}")
                continue
            stats["files"] += 1
            mode = stat.S_IMODE(path.stat().st_mode)
            if mode != item.get("mode"):
                problems.append(f"restored mode drift: {rel} ({oct(mode)} != {oct(item.get('mode'))})")
            if mode & 0o111:
                stats["executable"] += 1
            if sha256_file(path) != item.get("sha256"):
                problems.append(f"restored content drift: {rel}")
        for path in sorted(scratch.rglob("*")):
            rel = path.relative_to(scratch).as_posix()
            if path.is_dir():
                continue  # implied by its members
            if rel not in seen and rel not in want:
                problems.append(f"restored extra path: {rel}")
    finally:
        if target is None:
            shutil.rmtree(scratch, ignore_errors=True)
    stats["expected"] = len(want)
    return problems, stats


def verify(
    path: Path,
    require_artifacts: bool = False,
    require_boundary: bool = False,
    require_execution_binding: bool = False,
) -> int:
    expected = json.loads(path.read_text(encoding="utf-8"))
    archive_dir = expected.get("archive_dir")
    actual = build_manifest(
        ROOT / archive_dir if archive_dir else None,
        write_archives=False,
        # The stamp is part of the recorded runner identity: dropping it here
        # would make every stamped manifest fail its own verification.
        artifact_stamp=expected.get("artifact_stamp"),
    )
    problems: list[str] = []
    if expected.get("source_sha256") != actual["source_sha256"]:
        problems.append(
            f"source_sha256 {expected.get('source_sha256')} != {actual['source_sha256']}"
        )
    if expected.get("runner_sha256") != actual["runner_sha256"]:
        problems.append(
            f"runner_sha256 {expected.get('runner_sha256')} != {actual['runner_sha256']}"
        )
    def file_identity(item: dict) -> tuple:
        return (
            item.get("sha256"),
            item.get("type"),
            item.get("mode"),
            item.get("link_target"),
        )

    old_files = {item["path"]: file_identity(item) for item in expected.get("files", [])}
    new_files = {item["path"]: file_identity(item) for item in actual["files"]}
    for item in sorted(set(old_files) | set(new_files)):
        if old_files.get(item) != new_files.get(item):
            problems.append(f"file drift: {item}")
    for old_repo, new_repo in zip(expected.get("vendor_repos", []), actual["vendor_repos"]):
        if old_repo.get("head") != new_repo.get("head"):
            problems.append(f"vendor head drift: {new_repo['path']}")
        if old_repo.get("tracked_diff_sha256") != new_repo.get("tracked_diff_sha256"):
            problems.append(f"vendor diff drift: {new_repo['path']}")
    # Compare by path, not by position: `zip` silently ignores an archive or
    # artifact that disappeared, which is exactly the drift this must catch.
    old_archives = {item["path"]: item.get("sha256") for item in expected.get("archives", [])}
    new_archives = {item["path"]: item.get("sha256") for item in actual.get("archives", [])}
    for name in sorted(set(old_archives) | set(new_archives)):
        if old_archives.get(name) != new_archives.get(name):
            problems.append(f"archive drift: {name}")
    old_artifacts = {item["path"]: item.get("sha256") for item in expected.get("artifacts", [])}
    new_artifacts = {item["path"]: item.get("sha256") for item in actual.get("artifacts", [])}
    for name in sorted(set(old_artifacts) | set(new_artifacts)):
        if old_artifacts.get(name) != new_artifacts.get(name):
            problems.append(f"artifact drift: {name}")
    problems.extend(verify_outer_archive(expected))
    if archive_dir:
        # Every carrier must still be the recorded bytes, whether or not the
        # rebuild would reproduce them.
        for item in expected.get("archives", []):
            path = ROOT / archive_dir / item["path"]
            if not item.get("sha256"):
                problems.append(f"archive has no recorded hash: {item['path']}")
            elif not path.is_file():
                problems.append(f"archive absent on disk: {item['path']}")
            elif sha256_file(path) != item["sha256"]:
                problems.append(f"archive bytes drifted: {item['path']}")
    roundtrip_problems, roundtrip = extract_roundtrip(expected)
    problems.extend(roundtrip_problems)
    if problems:
        print("VERIFY FAIL")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print(
        "ROUNDTRIP PASS "
        f"{roundtrip.get('expected')}/{roundtrip.get('expected')} "
        f"files={roundtrip.get('files')} symlinks={roundtrip.get('symlinks')} "
        f"executable={roundtrip.get('executable')}"
    )
    print(f"VERIFY PASS {actual['runner_sha256']}")
    if not (require_artifacts or require_boundary or require_execution_binding):
        return 0
    # A verify run with requirement flags must gate on the RECORDED final state,
    # otherwise `--verify --require-execution-binding` silently passes an unclosed
    # binding. The checks read the manifest under review, so the verdict is bound
    # to the same round of products that the digest check just validated.
    return requirement_checks(
        expected,
        require_artifacts,
        require_boundary,
        require_execution_binding,
    )


def requirement_checks(
    manifest: dict,
    require_artifacts: bool,
    require_boundary: bool,
    require_execution_binding: bool = False,
) -> int:
    if require_artifacts:
        # A present-but-stale binary is not bound to the snapshot: it may have
        # been built from different sources. Both conditions fail closed.
        # Pending D1 targets (G6) are reported but do not fail THIS gate.
        stamp = manifest.get("artifact_stamp") or {}
        stamped = bool(stamp.get("source_sha256_matches")) and stamp.get(
            "artifacts_sha256"
        ) == {
            art["path"]: art.get("sha256")
            for art in manifest["artifacts"]
            if art.get("expected", True)
        }
        unusable = [
            f"{art['path']} ({'absent' if not art.get('present') else 'stale'})"
            for art in manifest["artifacts"]
            if art.get("expected", True)
            and (
                not art.get("present")
                or (art.get("fresh_against_scope") is False and not stamped)
            )
        ]
        if not stamped:
            unusable.append("artifact stamp missing or not bound to this source digest")
        if unusable:
            print("UNBOUND ARTIFACTS")
            for item in unusable:
                print(f"  - {item}")
            return 2
        # An archive with no hash is not a carrier: extraction cannot be
        # verified against it. A failed bundle create must fail the gate, not
        # be recorded as a null and silently skipped.
        unbound_archives = [
            archive["path"]
            for archive in manifest.get("archives", [])
            if not archive.get("sha256")
        ]
        if unbound_archives:
            print("UNBOUND ARCHIVES")
            for name in unbound_archives:
                print(f"  - {name}")
            return 2
    if require_boundary:
        boundary = manifest["boundary"]
        guards = manifest.get("entry_guards", {})
        failed = [check for check in boundary["checks"] if not check.get("passed")]
        failed += [check for check in guards.get("checks", []) if not check.get("passed")]
        if not boundary.get("available") or failed:
            print("BOUNDARY FAIL")
            for check in failed:
                print(f"  - {check['id']} observed={check.get('observed')}")
            return 2
        print(
            f"BOUNDARY PASS {len(boundary['checks'])} G8b-A module checks + "
            f"{len(guards.get('checks', []))} G8a entry-guard checks"
        )
        for non_claim in boundary.get("non_claims", []):
            print(f"G8b-B NON-CLAIM {non_claim}")
    binding = manifest.get("d1_execution_binding") or {}
    print(
        "EXECUTION BINDING "
        f"{binding.get('status')} worker={binding.get('worker')} "
        f"marker_consumed={binding.get('marker_consumed')} "
        f"launch_match={binding.get('launch_match')}"
    )
    if require_execution_binding and binding.get("status") != "bound":
        print("UNBOUND EXECUTION IDENTITY")
        for reason in binding.get("reasons") or [f"status is {binding.get('status')}"]:
            print(f"  - {reason}")
        return 2
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, help="write the manifest JSON here")
    parser.add_argument("--sha256-out", type=Path, help="write a sha256 sidecar here")
    parser.add_argument(
        "--bundle-dir",
        type=Path,
        help="freeze local-only commits and vendor diffs here (defaults beside --out)",
    )
    parser.add_argument("--verify", type=Path, help="recompute and compare to a manifest")
    parser.add_argument(
        "--require-artifacts",
        action="store_true",
        help="fail when any EXPECTED artifact is absent or older than the frozen sources",
    )
    parser.add_argument(
        "--require-boundary",
        action="store_true",
        help="fail when a G8b-A target-dependency boundary check fails",
    )
    parser.add_argument(
        "--require-execution-binding",
        action="store_true",
        help="fail unless the real D1 worker is bound and launched (G6/G7b)",
    )
    args = parser.parse_args()

    if args.verify:
        return verify(
            args.verify,
            args.require_artifacts,
            args.require_boundary,
            args.require_execution_binding,
        )

    bundle_dir = args.bundle_dir
    if bundle_dir is None and args.out:
        bundle_dir = args.out.parent / "archives"
    if bundle_dir is not None:
        # git runs with cwd=<vendor repo>, so a relative target would resolve
        # inside that repo instead of the workspace.
        bundle_dir = (ROOT / bundle_dir).resolve() if not bundle_dir.is_absolute() else bundle_dir.resolve()

    manifest = build_manifest(bundle_dir)
    text = json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print(f"wrote {args.out}")
    else:
        sys.stdout.write(text)

    sidecar = args.sha256_out
    if sidecar is None and args.out:
        sidecar = args.out.with_suffix(args.out.suffix + ".sha256")
    if sidecar:
        sidecar.parent.mkdir(parents=True, exist_ok=True)
        sidecar.write_text(
            f"{manifest['runner_sha256']}  {args.out.name}\n", encoding="utf-8"
        )
        print(f"wrote {sidecar}")

    print(f"source_revision {manifest['source_revision']}")
    print(f"source_sha256   {manifest['source_sha256']}")
    print(f"runner_sha256   {manifest['runner_sha256']}")
    print(f"files           {len(manifest['files'])}")
    for condition in manifest["open_conditions"]:
        print(f"open            {condition}")
    return requirement_checks(
        manifest,
        args.require_artifacts,
        args.require_boundary,
        args.require_execution_binding,
    )


if __name__ == "__main__":
    raise SystemExit(main())
