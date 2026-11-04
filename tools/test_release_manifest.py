#!/usr/bin/env python3
"""Controls for the versioned release manifest and exclusion register.

Each control states what it must make fail. The load-bearing claim is the
completeness layer: a tracked file that is in neither document must break the
check, so "everything was classified" stays a measurement instead of an intention.
"""

from __future__ import annotations

import io
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_manifest as manifest  # noqa: E402
import release_sanitize as sanitize  # noqa: E402
from release_artifact_audit import scan_file  # noqa: E402

# Assembled so this file is not itself a rule carrier.
HOME = "/" + "Users/" + "alice"
PATH_LITERAL = b"/" + b"Users/" + b"someone"
BIN = b"\xff\xfe not utf-8 at all\n"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

# The fixture tracks the product files but never the two documents it generates,
# the way the real repository versions them deliberately: counts stay meaningful.
COMMIT_PATHSPEC = [".", ":(exclude)release"]


def png_chunk(kind: bytes, data: bytes, crc: int | None = None) -> bytes:
    import binascii
    checksum = (binascii.crc32(kind + data) & 0xFFFFFFFF) if crc is None else crc
    return len(data).to_bytes(4, "big") + kind + data + checksum.to_bytes(4, "big")


def png_with_compressed_comment(private: bytes) -> bytes:
    import zlib
    payload = b"comment\x00\x00" + zlib.compress(private)
    return (PNG_SIGNATURE + png_chunk(b"IHDR", b"\0" * 13)
            + png_chunk(b"zTXt", payload)
            + png_chunk(b"IEND", b""))


def office_bytes(text: str) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("word/document.xml", f"<w:doc>{text}</w:doc>")
    return buffer.getvalue()


class Repo:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.run("init", "-q")

    def run(self, *args: str) -> None:
        subprocess.run(["git", "-C", str(self.root), *args], check=True,
                       capture_output=True)

    def write(self, rel: str, content) -> None:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode("utf-8"))

    def commit(self) -> None:
        self.run("add", "-A", "--", *COMMIT_PATHSPEC)
        self.run("-c", "user.name=t", "-c", "user.email=t@example.invalid",
                 "commit", "-q", "-m", "fixture")

    def documents(self) -> tuple[dict, dict]:
        return (json.loads((self.root / manifest.INPUTS_FILE).read_text(encoding="utf-8")),
                json.loads((self.root / manifest.EXCLUSIONS_FILE).read_text(encoding="utf-8")))

    def patch(self, which: str, rel: str, mutate) -> None:
        path = self.root / (manifest.INPUTS_FILE if which == "inputs"
                            else manifest.EXCLUSIONS_FILE)
        doc = json.loads(path.read_text(encoding="utf-8"))
        for entry in doc["sources" if which == "inputs" else "excluded"]:
            if entry["path"] == rel:
                mutate(entry)
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8")


class ManifestTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="release-manifest-test.")
        self.addCleanup(self._tmp.cleanup)
        self.repo = Repo(Path(self._tmp.name))
        self.repo.write("README.md", "# product\n")
        self.repo.write("docs/guide.md", f"home was {HOME}/x\n")
        self.repo.write("docs/other.md", "clean text\n")
        self.repo.write("research/evidence.md", f"evidence at {HOME}/y\n")
        self.repo.write("office/report.docx", office_bytes("plain content"))
        self.repo.write("artifacts/blob.bin", BIN)
        for rel in manifest.RULE_CARRIER_REASONS:
            self.repo.write(rel, "#!/usr/bin/env bash\n# carrier stub\n")
        self.repo.commit()
        self.derive()

    @property
    def root(self) -> Path:
        return self.repo.root

    def derive(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(0, manifest.derive(self.root,
                                                self.root / manifest.INPUTS_FILE,
                                                self.root / manifest.EXCLUSIONS_FILE))

    def run_check(self) -> tuple[int, str]:
        errors, out = io.StringIO(), io.StringIO()
        with redirect_stderr(errors), redirect_stdout(out):
            code = manifest.main(["check", "--root", str(self.root)])
        return code, errors.getvalue() + out.getvalue()

    def check_errors(self) -> list[str]:
        code, text = self.run_check()
        self.assertEqual(1, code, f"expected the check to fail:\n{text}")
        return [line for line in text.splitlines() if line.startswith("FAIL:")]

    def record_for(self, rel: str) -> dict:
        _, exclusions = self.repo.documents()
        matches = [r for r in exclusions["excluded"] if r["path"] == rel]
        self.assertEqual(1, len(matches), f"{rel} is not registered once: {matches}")
        return matches[0]

    # ---- the clean case ----

    def test_derive_and_check_pass(self) -> None:
        code, text = self.run_check()
        self.assertEqual(0, code, text)
        inputs, _ = self.repo.documents()
        self.assertEqual({"tracked": 10, "research_not_declared": 1,
                          "non_research_candidates": 9, "declared": 3,
                          "excluded": 6}, inputs["accounting"])
        self.assertIs(False, inputs["directory_globs_used"])
        self.assertIn("no directory glob", text)

    def test_records_carry_every_registered_field(self) -> None:
        _, exclusions = self.repo.documents()
        for record in exclusions["excluded"]:
            for field in exclusions["record_fields"]:
                self.assertIn(field, record, record["path"])
            self.assertIn(record["repository_privacy_scan"]["covered"], (True, False))

    def test_research_is_accounted_by_count_and_never_registered(self) -> None:
        inputs, exclusions = self.repo.documents()
        listed = ({e["path"] for e in inputs["sources"]}
                  | {r["path"] for r in exclusions["excluded"]})
        self.assertNotIn("research/evidence.md", listed)
        self.assertEqual(1, inputs["accounting"]["research_not_declared"])

    def test_rule_carriers_keep_their_recorded_reasons(self) -> None:
        for rel, reason in manifest.RULE_CARRIER_REASONS.items():
            self.assertEqual(reason, self.record_for(rel)["reason"])
        self.assertFalse(self.record_for("tools/open_source_audit.sh")
                         ["repository_privacy_scan"]["covered"])
        self.assertTrue(self.record_for("tools/release_sanitize.py")
                        ["repository_privacy_scan"]["covered"])

    def test_container_records_state_what_the_repository_engine_reaches(self) -> None:
        office = self.record_for("office/report.docx")["repository_privacy_scan"]
        self.assertEqual("office container", office["engine"])
        self.assertIn("every zip member", office["coverage"])
        blob = self.record_for("artifacts/blob.bin")["repository_privacy_scan"]
        self.assertIn("skips binary files", blob["coverage"])

    def test_documents_are_reproducible(self) -> None:
        first = (self.root / manifest.INPUTS_FILE).read_bytes()
        again = self.root / "scratch"
        again.mkdir()
        manifest.derive(self.root, again / "inputs.json", again / "exclusions.json")
        self.assertEqual(first, (again / "inputs.json").read_bytes())

    def test_input_document_is_consumable_by_build(self) -> None:
        sources = sanitize.load_inputs(self.root / manifest.INPUTS_FILE)
        self.assertEqual(3, len(sources))
        self.assertEqual({"path", "output"}, set(sources[0]))

    def test_the_documents_classify_themselves_once_tracked(self) -> None:
        # CI runs against a committed tree, where these two files are tracked like any
        # other candidate. Staying consistent therefore means listing themselves and
        # being re-derived in the same commit -- not an exemption for the manifest.
        self.repo.run("add", "-A")
        self.repo.run("-c", "user.name=t", "-c", "user.email=t@example.invalid",
                      "commit", "-q", "-m", "track the documents")
        stale = self.check_errors()
        self.assertTrue(any("neither document" in e for e in stale), stale)
        self.derive()
        code, text = self.run_check()
        self.assertEqual(0, code, text)
        inputs, _ = self.repo.documents()
        self.assertEqual(5, inputs["accounting"]["declared"])
        declared = {e["path"] for e in inputs["sources"]}
        self.assertIn(manifest.INPUTS_FILE, declared)
        self.assertIn(manifest.EXCLUSIONS_FILE, declared)

    # ---- completeness: the load-bearing controls ----

    def test_a_new_tracked_file_breaks_staging_acceptance(self) -> None:
        self.repo.write("docs/newcomer.md", "just added\n")
        self.repo.commit()
        code, text = self.run_check()
        self.assertEqual(1, code, text)
        self.assertIn("in neither document", text)
        self.assertIn("docs/newcomer.md", text)
        self.derive()
        code, text = self.run_check()
        self.assertEqual(0, code, text)

    def test_an_excluded_candidate_must_still_be_registered(self) -> None:
        self.repo.write("artifacts/second.bin", BIN)
        self.repo.commit()
        self.assertTrue(any("not registered" in e for e in self.check_errors()))

    def test_a_stale_input_fails(self) -> None:
        self.repo.patch("inputs", "docs/other.md",
                        lambda entry: entry.update(path="docs/gone.md",
                                                   output="docs/gone.md"))
        self.assertTrue(any("stale input list misses" in e for e in self.check_errors()))

    # ---- a record must describe the bytes that are actually there ----

    def test_hash_drift_of_an_excluded_file_fails(self) -> None:
        self.repo.write("artifacts/blob.bin", BIN + b"and more\n")
        self.assertTrue(any("changed since it was registered" in e
                            for e in self.check_errors()))

    def test_a_registered_hit_is_never_reported_as_clean(self) -> None:
        self.repo.write("artifacts/leak.bin", PATH_LITERAL + BIN)
        self.repo.commit()
        self.derive()
        # x2 is the repository engine's own counting: the raw bytes and the utf-8
        # round trip are concatenated, so one occurrence is seen in both views.
        self.assertEqual(2, self.record_for("artifacts/leak.bin")
                         ["repository_privacy_scan"]["hits"])
        self.assertTrue(any("not clean under the current repository rules" in e
                            for e in self.check_errors()))

    def test_compressed_png_comment_is_now_recorded_as_a_repository_hit(self) -> None:
        # Before the shared strict parser this fixture was the register's honest record
        # of a blind spot: hits=0 from the repository engine, 1 from a stricter second
        # reading. Both entries now inflate the same chunk, so the compressed comment
        # is a plain repository hit and the ordinary registered-hit refusal applies.
        self.repo.write("artifacts/hidden.png", png_with_compressed_comment(PATH_LITERAL))
        self.repo.commit()
        self.derive()
        scan = self.record_for("artifacts/hidden.png")["repository_privacy_scan"]
        self.assertEqual(1, scan["hits"])
        self.assertEqual(1, scan["png_text_chunk_views"])
        self.assertTrue(any("not clean under the current repository rules" in e
                            for e in self.check_errors()))

    def test_a_clean_compressed_png_stays_a_pass(self) -> None:
        self.repo.write("artifacts/hidden.png", png_with_compressed_comment(b"srgb profile"))
        self.repo.commit()
        self.derive()
        code, text = self.run_check()
        self.assertEqual(0, code, text)
        scan = self.record_for("artifacts/hidden.png")["repository_privacy_scan"]
        self.assertEqual(0, scan["hits"])
        self.assertEqual(1, scan["png_text_chunk_views"])
        self.assertIn("inflated", scan["coverage"])

    def test_an_uncertifiable_png_is_a_refusal_not_a_clean_record(self) -> None:
        # The container is content-clean: only its structure is wrong. Raw-byte scanning
        # alone would have called this covered, which is the gap the shared parser closes
        # for the whole-tree audit as well as for staging.
        broken = (PNG_SIGNATURE + png_chunk(b"tEXt", b"comment\x00clean", crc=0xDEADBEEF)
                  + png_chunk(b"IEND", b""))
        self.repo.write("artifacts/broken.png", broken)
        self.repo.commit()
        self.derive()
        scan = self.record_for("artifacts/broken.png")["repository_privacy_scan"]
        self.assertTrue(scan["uncertifiable"])
        self.assertEqual("uncertifiable (PngStructureError)", scan["coverage"])
        self.assertTrue(any("could not be certified" in e for e in self.check_errors()))

    # ---- the documents stay static: #242 ----

    def test_the_derived_documents_carry_no_self_reference(self) -> None:
        inputs, exclusions = self.repo.documents()
        self.assertEqual(set(manifest.INPUTS_KEYS), set(inputs))
        self.assertEqual(set(manifest.EXCLUSIONS_KEYS), set(exclusions))
        self.assertNotIn("generated_from", inputs)

    def test_a_provenance_field_injected_into_the_manifest_is_refused(self) -> None:
        path = self.root / manifest.INPUTS_FILE
        doc = json.loads(path.read_text(encoding="utf-8"))
        doc["generated_from"] = {"git_head": "0" * 40}
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8")
        errors = self.check_errors()
        self.assertTrue(any("dynamic provenance field" in e for e in errors), errors)

    def test_a_provenance_field_hidden_in_accounting_is_refused(self) -> None:
        # A self-reference smuggled one level down is still a self-reference: the
        # document would claim to describe a commit while looking like a count.
        path = self.root / manifest.INPUTS_FILE
        doc = json.loads(path.read_text(encoding="utf-8"))
        doc["accounting"]["source_commit"] = "0" * 40
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8")
        errors = self.check_errors()
        self.assertTrue(any("dynamic provenance field" in e for e in errors), errors)

    def test_a_key_outside_the_static_schema_is_refused(self) -> None:
        path = self.root / manifest.EXCLUSIONS_FILE
        doc = json.loads(path.read_text(encoding="utf-8"))
        doc["staging_digest"] = "a" * 64
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n",
                        encoding="utf-8")
        self.assertTrue(any("outside the static schema" in e for e in self.check_errors()))

    def test_uncertifiable_container_fails_closed(self) -> None:
        self.repo.write("office/broken.docx", b"PK\x03\x04\xff\xfe not a real archive")
        self.repo.commit()
        self.derive()
        self.assertTrue(self.record_for("office/broken.docx")
                        ["repository_privacy_scan"]["uncertifiable"])
        self.assertTrue(any("could not be certified" in e for e in self.check_errors()))

    # ---- the two prohibitions the owner stated ----

    def test_a_directory_glob_is_refused_in_either_document(self) -> None:
        self.repo.patch("inputs", "docs/guide.md",
                        lambda entry: entry.update(path="docs/*", output="docs/*"))
        self.assertTrue(any("not an exact file" in e for e in self.check_errors()))
        self.derive()
        self.repo.patch("exclusions", "artifacts/blob.bin",
                        lambda record: record.update(path="artifacts/*"))
        self.assertTrue(any("not an exact file" in e for e in self.check_errors()))

    def test_reason_text_may_not_be_paraphrased(self) -> None:
        self.repo.patch("exclusions", "artifacts/blob.bin",
                        lambda record: record.update(reason="binary, skip"))
        self.assertTrue(any("reason drifted" in e for e in self.check_errors()))

    def test_the_whole_tree_scan_requirement_cannot_be_dropped(self) -> None:
        self.repo.patch("exclusions", "office/report.docx",
                        lambda record: record.update(
                            release_branch_whole_tree_scan_required=False))
        self.assertTrue(any("drops the whole-tree scan requirement" in e
                            for e in self.check_errors()))

    def test_dropping_a_field_from_a_record_fails(self) -> None:
        self.repo.patch("exclusions", "artifacts/blob.bin",
                        lambda record: record.pop("sha256"))
        self.assertTrue(any("lacks fields" in e for e in self.check_errors()))

    def test_a_research_file_cannot_be_declared_as_an_input(self) -> None:
        self.repo.patch("inputs", "docs/other.md",
                        lambda entry: entry.update(path="research/evidence.md",
                                                   output="research/evidence.md"))
        self.assertTrue(any("research file is declared" in e for e in self.check_errors()))

    def test_an_old_rules_version_is_refused(self) -> None:
        path = self.root / manifest.INPUTS_FILE
        doc = json.loads(path.read_text(encoding="utf-8"))
        doc["rules"] = "release-manifest-2026-10-29.1"
        path.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
        self.assertTrue(any("rules" in e for e in self.check_errors()))

    def test_a_non_work_tree_root_is_a_refusal_not_a_pass(self) -> None:
        empty = Path(tempfile.mkdtemp(prefix="not-a-repo."))
        errors = io.StringIO()
        with redirect_stderr(errors):
            code = manifest.main(["check", "--root", str(empty),
                                  "--inputs", str(empty / "missing.json"),
                                  "--exclusions", str(empty / "missing2.json")])
        self.assertEqual(1, code)
        self.assertIn("unreadable", errors.getvalue())

    def test_derive_fails_closed_on_a_tracked_file_that_is_gone(self) -> None:
        self.repo.write("docs/vanishing.md", "text\n")
        self.repo.commit()
        (self.root / "docs/vanishing.md").unlink()
        errors = io.StringIO()
        with redirect_stderr(errors):
            code = manifest.main(["derive", "--root", str(self.root),
                                  "--inputs-out", str(self.root / "x.json"),
                                  "--exclusions-out", str(self.root / "y.json")])
        self.assertEqual(1, code)
        self.assertIn("not readable on disk", errors.getvalue())


if __name__ == "__main__":
    unittest.main()
