#!/usr/bin/env python3
"""Authoritative evidence-path loading and fail-closed preflight."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path


class EvidencePathError(RuntimeError):
    pass


@dataclass(frozen=True)
class EvidencePaths:
    repository_root: Path
    output_root: Path
    manifest: dict
    paths: dict[str, Path]

    def resolve(self, destination_id: str) -> Path:
        try:
            return self.paths[destination_id]
        except KeyError as exc:
            raise EvidencePathError(
                f"destination not authorized by path map: {destination_id}"
            ) from exc


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidencePathError(message)


def _destination_entries(manifest: dict) -> list[dict]:
    files = [
        item for item in manifest["artifact_destinations"] if item["type"] == "file"
    ]
    directories = [
        item for item in manifest["artifact_destinations"] if item["type"] == "directory"
    ]
    return files + directories


def _exclusive_probe(parent: Path, destination_id: str) -> dict:
    probe = parent / f".{destination_id}.evidence-path-probe"
    created = False
    try:
        descriptor = os.open(probe, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        created = True
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(b"evidence-path-binding-probe\n")
        writable = os.access(parent, os.W_OK)
        return {
            "created_exclusively": True,
            "probe_path": str(probe),
            "removed": probe.unlink() is None,
            "writable": writable,
        }
    except OSError as exc:
        if created and probe.exists():
            probe.unlink()
        raise EvidencePathError(f"evidence path probe failed for {destination_id}: {exc}") from exc


def load_and_preflight(repository_root: Path, output_root: Path) -> EvidencePaths:
    manifest_path = Path(__file__).with_name("EVIDENCE_PATH_BINDING_MANIFEST.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    _require(manifest.get("authoritative_path_map") is True, "non-authoritative path map")
    expected_root = repository_root / manifest["campaign_output_root_repository_relative"]
    _require(
        output_root.resolve() == expected_root.resolve(),
        f"campaign output root does not equal authoritative path-map root: {output_root}",
    )
    _require(output_root.exists() and not output_root.is_symlink(), "invalid campaign output root")
    _require(output_root.is_dir(), "campaign output root is not a directory")

    managed_paths: dict[str, Path] = {}
    for entry in manifest["created_directories"]:
        path = output_root / entry["output_relative_path"]
        _require(not path.is_symlink(), f"managed directory is symlink: {entry['directory_id']}")
        path.mkdir(parents=True, exist_ok=False)
        _require(path.is_dir(), f"managed directory is not directory: {entry['directory_id']}")
        managed_paths[entry["directory_id"]] = path

    results = []
    paths: dict[str, Path] = {}
    for entry in _destination_entries(manifest):
        destination_id = entry["destination_id"]
        path = output_root / entry["output_relative_path"]
        _require(not path.is_symlink(), f"destination is symlink: {destination_id}")
        parent = path.parent
        _require(parent.exists() and parent.is_dir(), f"destination parent invalid: {destination_id}")
        if entry["type"] == "directory":
            _require(path.is_dir(), f"directory destination invalid: {destination_id}")
            probe = _exclusive_probe(path, destination_id)
            exists = path.is_dir()
            is_symlink = path.is_symlink()
            is_directory = True
            fresh_required_absent = True
        else:
            _require(not path.exists(), f"fresh destination already exists: {destination_id}")
            probe = _exclusive_probe(parent, destination_id)
            exists = path.exists()
            is_symlink = path.is_symlink()
            is_directory = path.is_dir()
            fresh_required_absent = not exists and not is_symlink
        paths[destination_id] = path
        results.append({
            "destination_id": destination_id,
            "output_relative_path": entry["output_relative_path"],
            "required_stage": entry["required_stage"],
            "type": entry["type"],
            "parent_exists": parent.exists(),
            "parent_writable": os.access(parent, os.W_OK),
            "exists_before_campaign": exists,
            "is_symlink": is_symlink,
            "is_directory": is_directory,
            "fresh_required_absent": fresh_required_absent,
            "exclusive_write_probe": probe,
            "pass": (
                parent.exists()
                and os.access(parent, os.W_OK)
                and not is_symlink
                and probe["created_exclusively"]
                and probe["removed"]
            ),
        })

    _require(all(item["pass"] for item in results), "evidence path preflight failure")
    execution_record = {
        "authoritative_manifest": "EVIDENCE_PATH_BINDING_MANIFEST.json",
        "campaign_output_root": str(output_root),
        "independent_path_derivation": False,
        "overall_pass": True,
        "results": results,
    }
    record_path = paths["EVIDENCE_PATH_BINDING_EXECUTION"]
    record_path.write_text(
        json.dumps(execution_record, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    return EvidencePaths(repository_root, output_root, manifest, paths)
