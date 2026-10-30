#!/usr/bin/env python3
"""Negative tests for `tools/release_sanitize.py` (step 5 of the hygiene mechanism).

The point of these tests is the failure modes, not the happy path: sensitive content
must be unable to reach a deliverable directory even when the manifest is rewritten to
match it, and building must never alter a frozen original.

Every sensitive token used here is taken from `release_artifact_audit.FORBIDDEN`, and
the home prefix is assembled from parts, so this file itself carries none of them.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_sanitize as sanitize  # noqa: E402
from release_artifact_audit import FORBIDDEN, findings  # noqa: E402

HOME = "/" + "Users/" + "alice"
HOME_FILE = HOME + "/notes/plan.md"
TEMP_FILE = "/private/var/folders/ab/cdef/T/tmp-plan.md"


def sensitive_body() -> str:
    return "\n".join([
        "home: " + HOME_FILE,
        "temp: " + TEMP_FILE,
        "user: " + FORBIDDEN[1].decode(),
        "team: " + FORBIDDEN[2].decode(),
        "mail: " + FORBIDDEN[3].decode(),
        "",
    ])


class Workspace:
    """A throwaway repo root plus an input manifest naming one source."""

    def __init__(self, root: Path, body: str = "", name: str = "evidence.md") -> None:
        self.root = root
        self.src = root / "research" / "frozen" / name
        self.src.parent.mkdir(parents=True, exist_ok=True)
        self.src.write_text(body if body else sensitive_body(), encoding="utf-8")
        self.inputs = root / "inputs.json"
        self.write_inputs([{"path": "research/frozen/" + name, "output": name}])

    def write_inputs(self, sources: list[dict]) -> None:
        self.inputs.write_text(json.dumps(
            {"manifest_version": 1, "sources": sources}), encoding="utf-8")

    def build(self, out: Path, manifest: Path) -> dict:
        return sanitize.build(self.inputs, out, manifest, self.root)


class SanitizeTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)
        self.ws = Workspace(self.tmp)

    def test_build_redacts_every_class_and_leaves_the_source_untouched(self) -> None:
        before = self.ws.src.read_bytes()
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        record = self.ws.build(out, manifest)

        produced = (out / "evidence.md").read_text(encoding="utf-8")
        self.assertIn("<HOME>/notes/plan.md", produced)
        self.assertIn("<TMP>", produced)
        self.assertIn("<REDACTED:forbidden_1>", produced)
        self.assertIn("<REDACTED:forbidden_2>", produced)
        self.assertIn("<REDACTED:forbidden_3>", produced)
        self.assertEqual(findings(produced.encode()), [])
        self.assertIsNone(sanitize.HOME_PATH.search(produced))
        self.assertIsNone(sanitize.TEMP_PATH.search(produced))

        self.assertEqual(self.ws.src.read_bytes(), before, "a frozen original must not change")
        entry = record["sources"][0]
        self.assertEqual(entry["source"], "research/frozen/evidence.md")
        self.assertEqual(entry["source_sha256"], sanitize._sha256(before))
        self.assertEqual(entry["output_sha256"], sanitize._sha256(produced.encode()))
        self.assertNotIn("alice", json.dumps(record), "the manifest must not leak the redacted value")

    def test_only_explicitly_listed_sources_are_copied(self) -> None:
        stray = self.ws.root / "research" / "frozen" / "unlisted.md"
        stray.write_text(sensitive_body(), encoding="utf-8")
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        self.ws.build(out, manifest)
        self.assertEqual(sorted(p.name for p in out.iterdir()), ["evidence.md"])

    def test_gate_passes_on_a_freshly_built_deliverable(self) -> None:
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        self.ws.build(out, manifest)
        self.assertEqual(sanitize.gate(out, manifest), [])

    def test_gate_fails_when_sensitive_bytes_match_the_manifest(self) -> None:
        # The simulation that matters: redaction silently did nothing AND the manifest
        # was regenerated from the raw bytes, so hashes agree. Content must still fail.
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        self.ws.build(out, manifest)
        raw = self.ws.src.read_bytes()
        (out / "evidence.md").write_bytes(raw)
        spec = json.loads(manifest.read_text(encoding="utf-8"))
        spec["sources"][0]["output_sha256"] = sanitize._sha256(raw)
        spec["sources"][0]["output_bytes"] = len(raw)
        manifest.write_text(json.dumps(spec), encoding="utf-8")

        errors = sanitize.gate(out, manifest)
        self.assertTrue(any("forbidden token still present" in e for e in errors), errors)
        self.assertTrue(any("home path" in e for e in errors), errors)

    def test_gate_fails_on_altered_output(self) -> None:
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        self.ws.build(out, manifest)
        (out / "evidence.md").write_text("tampered\n", encoding="utf-8")
        errors = sanitize.gate(out, manifest)
        self.assertTrue(any("altered" in e for e in errors), errors)

    def test_gate_fails_on_undeclared_file(self) -> None:
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        self.ws.build(out, manifest)
        (out / "extra.md").write_text("not declared\n", encoding="utf-8")
        errors = sanitize.gate(out, manifest)
        self.assertTrue(any("undeclared file" in e for e in errors), errors)

    def test_gate_fails_on_missing_output(self) -> None:
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        self.ws.build(out, manifest)
        (out / "evidence.md").unlink()
        errors = sanitize.gate(out, manifest)
        self.assertTrue(any("missing" in e for e in errors), errors)

    def test_gate_fails_when_the_rule_set_changed(self) -> None:
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        self.ws.build(out, manifest)
        spec = json.loads(manifest.read_text(encoding="utf-8"))
        spec["rules_version"] = "sanitize-0.0.0"
        manifest.write_text(json.dumps(spec), encoding="utf-8")
        errors = sanitize.gate(out, manifest)
        self.assertTrue(any("rules_version" in e for e in errors), errors)

    def test_build_refuses_symlink_source_escaping_root(self) -> None:
        # The manifest names a path inside the root; the physical file it resolves
        # to is outside. String checks alone would pass this.
        outside_root = tempfile.TemporaryDirectory()
        self.addCleanup(outside_root.cleanup)
        outside = Path(outside_root.name) / "leak.md"
        outside.write_text(sensitive_body(), encoding="utf-8")
        link = self.ws.root / "research" / "frozen" / "link.md"
        link.symlink_to(outside)
        self.ws.write_inputs([{"path": "research/frozen/link.md", "output": "leak.md"}])
        with self.assertRaises(sanitize.SanitizeError) as caught:
            self.ws.build(self.tmp / "deliverable", self.tmp / "provenance.json")
        self.assertIn("escapes its root", str(caught.exception))
        self.assertFalse((self.tmp / "deliverable" / "leak.md").exists())

    def test_output_containment_is_physical_not_lexical(self) -> None:
        # "sub/escaped.md" looks relative and contains no "..", but "sub" is a link
        # to a directory outside --out. The guard must resolve before comparing.
        # (build() also refuses a non-empty --out first; this pins the guard itself.)
        out = self.tmp / "deliverable"
        out.mkdir()
        elsewhere = self.tmp / "elsewhere"
        elsewhere.mkdir()
        (out / "sub").symlink_to(elsewhere, target_is_directory=True)
        with self.assertRaises(sanitize.SanitizeError) as caught:
            sanitize._require_inside(out / "sub" / "escaped.md", out, "output path")
        self.assertIn("escapes", str(caught.exception))

    def test_gate_fails_on_a_symlinked_output(self) -> None:
        # The link target is clean and its hash matches the manifest; the deliverable
        # must still refuse to carry a reference instead of the bytes it claims.
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        self.ws.build(out, manifest)
        produced = out / "evidence.md"
        clean = self.tmp / "clean-copy.md"
        clean.write_bytes(produced.read_bytes())
        produced.unlink()
        produced.symlink_to(clean)
        errors = sanitize.gate(out, manifest)
        self.assertTrue(any("symlink" in e for e in errors), errors)

    def test_build_refuses_binary_source(self) -> None:
        binary = self.ws.root / "research" / "frozen" / "blob.bin"
        binary.write_bytes(b"\xff\xfe\x00" + FORBIDDEN[1])
        self.ws.write_inputs([{"path": "research/frozen/blob.bin", "output": "blob.bin"}])
        with self.assertRaises(sanitize.SanitizeError):
            self.ws.build(self.tmp / "deliverable", self.tmp / "provenance.json")

    def test_build_refuses_source_outside_root(self) -> None:
        self.ws.write_inputs([{"path": "../outside.md", "output": "outside.md"}])
        with self.assertRaises(sanitize.SanitizeError):
            self.ws.build(self.tmp / "deliverable", self.tmp / "provenance.json")

    def test_build_refuses_output_escaping_the_deliverable(self) -> None:
        self.ws.write_inputs([{"path": "research/frozen/evidence.md", "output": "../escape.md"}])
        with self.assertRaises(sanitize.SanitizeError):
            self.ws.build(self.tmp / "deliverable", self.tmp / "provenance.json")

    def test_build_refuses_duplicate_outputs_and_dirty_directory(self) -> None:
        self.ws.write_inputs([
            {"path": "research/frozen/evidence.md", "output": "same.md"},
            {"path": "research/frozen/evidence.md", "output": "same.md"},
        ])
        with self.assertRaises(sanitize.SanitizeError):
            self.ws.build(self.tmp / "deliverable", self.tmp / "provenance.json")

        self.ws.write_inputs([{"path": "research/frozen/evidence.md", "output": "evidence.md"}])
        dirty = self.tmp / "dirty"
        dirty.mkdir()
        (dirty / "leftover.md").write_text("old\n", encoding="utf-8")
        with self.assertRaises(sanitize.SanitizeError):
            self.ws.build(dirty, self.tmp / "provenance.json")

    def test_build_refuses_manifest_inside_the_deliverable(self) -> None:
        with self.assertRaises(sanitize.SanitizeError):
            self.ws.build(self.tmp / "deliverable", self.tmp / "deliverable" / "manifest.json")

    def test_failed_build_leaves_no_partial_deliverable(self) -> None:
        second = self.ws.root / "research" / "frozen" / "blob.bin"
        second.write_bytes(b"\xff\xfe")
        self.ws.write_inputs([
            {"path": "research/frozen/evidence.md", "output": "evidence.md"},
            {"path": "research/frozen/blob.bin", "output": "blob.bin"},
        ])
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        with self.assertRaises(sanitize.SanitizeError):
            self.ws.build(out, manifest)
        self.assertEqual(list(out.glob("**/*")), [], "no partial file may survive a failed build")
        self.assertFalse(manifest.exists(), "no manifest may be written by a failed build")

    def test_repeated_sanitize_is_idempotent(self) -> None:
        once, _ = sanitize.sanitize_text(sensitive_body())
        twice, applied = sanitize.sanitize_text(once)
        self.assertEqual(once, twice)
        self.assertEqual(applied, [])

    def test_cli_builds_then_gates_and_fails_closed_on_tamper(self) -> None:
        script = Path(sanitize.__file__).resolve()
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        build = subprocess.run(
            [sys.executable, str(script), "build",
             "--inputs", str(self.ws.inputs), "--out", str(out),
             "--manifest-out", str(manifest), "--root", str(self.tmp)],
            capture_output=True, text=True)
        self.assertEqual(build.returncode, 0, build.stderr)
        self.assertIn("PASS: built 1 file", build.stdout)

        gate = subprocess.run(
            [sys.executable, str(script), "gate", "--dir", str(out), "--manifest", str(manifest)],
            capture_output=True, text=True)
        self.assertEqual(gate.returncode, 0, gate.stderr)

        (out / "extra.md").write_text("smuggled\n", encoding="utf-8")
        gate = subprocess.run(
            [sys.executable, str(script), "gate", "--dir", str(out), "--manifest", str(manifest)],
            capture_output=True, text=True)
        self.assertEqual(gate.returncode, 1)
        self.assertIn("undeclared file", gate.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
