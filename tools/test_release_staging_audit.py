#!/usr/bin/env python3
"""Positive and negative controls for `tools/release_staging_audit.py`.

The suite exists to answer one question: is this audit capable of failing? Two
failure modes had to be measured rather than assumed.

* A container hit can be invisible to a byte scan. The .docx and .pdf fixtures carry
  the forbidden literal only inside a deflated member or a compressed stream, and
  each test asserts the raw file bytes do not contain it, so a PASS from a plain byte
  scan proves nothing while the audit must still fail. The PNG fixtures separate the
  three text-metadata chunks: `tEXt` is reachable from the raw bytes, while `zTXt`
  and flag-1 `iTXt` hide the literal behind a compression prefix that only a
  field-parsed, inflated view can reach. Both scan entries now share that parser
  (`tools/png_text_chunks.py`), so each compressed fixture asserts the *repository*
  engine reaches it too -- the differential that used to record the blind spot is
  kept as the witness that the blind spot is closed. A container that cannot be
  certified fails the audit even when its contents are clean.
* A PASS must be about the audited directory only, so the audit is also run against
  the unsanitized source of a real build, where it must fail.

Every sensitive value is assembled from parts or imported, so this file itself
carries none of them and can live inside the tree it audits.
"""

from __future__ import annotations

import binascii
import io
import sys
import tempfile
import unittest
import zipfile
import zlib
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_sanitize as sanitize  # noqa: E402
import release_staging_audit as staging  # noqa: E402
from release_artifact_audit import FORBIDDEN, findings, scan_file, scan_png  # noqa: E402

HOME = "/" + "Users/" + "alice"
HOME_BYTES = HOME.encode()
TEMP = "/" + "private" + "/var/folders/" + "ab/cdef/T/tmp-plan.md"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def office_bytes(private_path: str = HOME + "/doc.md") -> bytes:
    """A .docx whose only copy of the literal lives inside a deflated member."""
    body = ("<w:document><w:note>" + private_path + "</w:note></w:document>"
            + "<!--" + ("pad " * 400) + "-->").encode()
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("[Content_Types].xml", "<Types/>")
        archive.writestr("word/document.xml", body)
    return buffer.getvalue()


def pdf_bytes(private_path: bytes = HOME_BYTES) -> bytes:
    """A .pdf whose only copy of the literal lives inside a compressed stream."""
    payload = zlib.compress(b"BT /F1 12 Tf (" + private_path + b"/x.tex) Tj ET")
    return (b"%PDF-1.4\n1 0 obj\n<< /Length " + str(len(payload)).encode() + b" >>\nstream\n"
            + payload + b"\nendstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n")


def png_chunk(kind: bytes, data: bytes, crc: int | None = None) -> bytes:
    """A well-formed chunk unless `crc` says otherwise.

    The CRC is real because the audit now verifies it: a fixture with a bogus
    checksum would be evidence of a fail-closed container, not of a token leak.
    """
    checksum = (binascii.crc32(kind + data) & 0xFFFFFFFF) if crc is None else crc
    return (len(data).to_bytes(4, "big") + kind + data + checksum.to_bytes(4, "big"))


def png_wrap(*chunks: bytes) -> bytes:
    return PNG_SIGNATURE + b"".join(chunks)


def png_bytes(private_path: bytes = HOME_BYTES) -> bytes:
    """A .png whose only copy of the literal is an uncompressed tEXt comment."""
    return png_wrap(png_chunk(b"tEXt", b"comment\x00" + private_path + b"/shot.png"),
                    png_chunk(b"IDAT", zlib.compress(b"\x00" * 16)),
                    png_chunk(b"IEND", b""))


def png_ztxt_bytes(private_path: bytes = HOME_BYTES) -> bytes:
    """A .png whose literal survives only after `keyword\\0method\\0` is stripped.

    This is the shape a whole-payload zlib call loses: the keyword prefix makes the
    decompress fail, so nothing is appended and nothing is hit. Both engines now
    parse the fields, which is what the assertions below measure.
    """
    return png_wrap(
        png_chunk(b"zTXt", b"comment\x00\x00" + zlib.compress(private_path + b"/shot.png")),
        png_chunk(b"IDAT", zlib.compress(b"\x00" * 16)),
        png_chunk(b"IEND", b""))


def png_compressed_itxt_bytes(private_path: bytes = HOME_BYTES) -> bytes:
    """The same leak behind iTXt, where flag=1 deflates everything past the fields.

    The flag and method bytes are 0x01 and 0x00, so a parser that splits this chunk
    on NUL reads the flag as a separator and loses the field alignment.
    """
    payload = (b"comment\x00" + b"\x01\x00" + b"\x00" + b"\x00"
               + zlib.compress(private_path + b"/shot.png"))
    return png_wrap(png_chunk(b"iTXt", payload),
                    png_chunk(b"IDAT", zlib.compress(b"\x00" * 16)),
                    png_chunk(b"IEND", b""))



def write_tree(root: Path) -> None:
    (root / "docs").mkdir(parents=True)
    (root / "README.md").write_text("# SimiGo\n\nProduct documentation.\n", encoding="utf-8")
    (root / "docs" / "clean.md").write_text("Nothing sensitive here.\n", encoding="utf-8")


class StagingAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)

    def tree(self, name: str = "staging") -> Path:
        root = self.tmp / name
        root.mkdir(parents=True, exist_ok=True)
        write_tree(root)
        return root

    # ---- the happy path is the weakest claim in this file -------------------

    def test_clean_directory_passes(self) -> None:
        root = self.tree()
        report = staging.audit(root)
        self.assertEqual(report["artifact_hits"], [])
        self.assertEqual(report["sanitize_hits"], [])
        self.assertEqual(report["checked"], 2)

    # ---- ordinary text: both engines must fire ------------------------------

    def test_planted_home_path_fails_both_engines(self) -> None:
        root = self.tree()
        (root / "leak.md").write_text("see " + HOME + "/notes\n", encoding="utf-8")
        report = staging.audit(root)
        self.assertIn("leak.md [text/binary] x2", report["artifact_hits"])
        self.assertEqual(len(report["sanitize_hits"]), 1)
        self.assertTrue(report["sanitize_hits"][0].startswith("leak.md: "))
        self.assertIn("forbidden_0", report["sanitize_hits"][0])
        self.assertIn("home_paths x1", report["sanitize_hits"][0])

    def test_planted_temp_path_fails_only_the_sanitize_engine(self) -> None:
        # The repository audit has no temporary-path literal, so this is the one
        # case where the two engines differ by design. Reporting it separately is
        # what keeps the stricter verdict from being mistaken for the older rule.
        root = self.tree()
        (root / "tmp.md").write_text("plan at " + TEMP + "\n", encoding="utf-8")
        report = staging.audit(root)
        self.assertEqual(report["artifact_hits"], [])
        self.assertIn("tmp.md: temp_paths x1", report["sanitize_hits"])

    # ---- containers: a byte scan cannot see these, and must not be trusted ----

    def test_office_container_hit_survives_raw_byte_scan(self) -> None:
        data = office_bytes()
        self.assertEqual(findings(data), [], "fixture must not be detectable raw")
        root = self.tree()
        (root / "report.docx").write_bytes(data)
        self.assertEqual(scan_file(root / "report.docx")[0], "office container")
        report = staging.audit(root)
        # x2: the imported byte audit scans the decoded member twice (raw and the
        # utf-8 round trip), so one occurrence inside the archive is reported twice.
        self.assertIn("report.docx [office container] x2", report["artifact_hits"])
        self.assertEqual(report["container_checked"]["office"], 1)

    def test_pdf_stream_hit_survives_raw_byte_scan(self) -> None:
        data = pdf_bytes()
        self.assertEqual(findings(data), [], "fixture must not be detectable raw")
        root = self.tree()
        (root / "scan.pdf").write_bytes(data)
        report = staging.audit(root)
        self.assertIn("scan.pdf [pdf container] x1", report["artifact_hits"])

    def test_png_text_chunk_hit_is_caught(self) -> None:
        data = png_bytes()
        self.assertEqual(len(findings(data)), 1, "tEXt leaks into the raw bytes")
        root = self.tree()
        (root / "shot.png").write_bytes(data)
        report = staging.audit(root)
        # x2: the whole-file raw scan and the shared parser's field-parsed view both
        # see it. Counts are per scanned view, so one literal visible in several views
        # is counted several times; the verdict only cares that the list is non-empty.
        self.assertIn("shot.png [image container] x2", report["artifact_hits"])
        self.assertEqual(report["container_errors"], [])

    def test_png_compressed_text_chunk_is_decoded(self) -> None:
        # The shape that used to be invisible to the whole-tree audit. The literal
        # appears nowhere in the file bytes, so a plain byte scan cannot reach it;
        # the field-parsing decoder both entries share must, and both verdicts fail.
        data = png_ztxt_bytes()
        self.assertEqual(findings(data), [], "fixture must not be detectable raw")
        self.assertEqual(len(findings(scan_png(data))), 1, "the repository entry reaches it")
        views = staging.png_text_views(data)
        self.assertEqual(len(views), 1, "one comment, parsed and inflated")
        self.assertEqual(len(findings(views[0])), 1)
        root = self.tree()
        (root / "hidden.png").write_bytes(data)
        report = staging.audit(root)
        self.assertIn("hidden.png [image container] x1", report["artifact_hits"])
        self.assertEqual(report["container_errors"], [])
        self.assertEqual(report["container_checked"]["image"], 1)

    def test_png_compressed_itxt_is_decoded(self) -> None:
        data = png_compressed_itxt_bytes()
        self.assertEqual(findings(data), [], "fixture must not be detectable raw")
        self.assertEqual(len(findings(scan_png(data))), 1, "the repository entry reaches it")
        root = self.tree()
        (root / "meta.png").write_bytes(data)
        self.assertIn("meta.png [image container] x1",
                      staging.audit(root)["artifact_hits"])

    def test_clean_png_with_compressed_comment_is_not_a_hit(self) -> None:
        # Decoding more must not mean inventing hits: the same compressed-comment
        # shape, carrying nothing sensitive, is parsed and reported clean.
        root = self.tree()
        (root / "clean.png").write_bytes(png_ztxt_bytes(b"/opt/simi"))
        (root / "clean_meta.png").write_bytes(png_compressed_itxt_bytes(b"/opt/simi"))
        report = staging.audit(root)
        self.assertEqual(report["artifact_hits"], [])
        self.assertEqual(report["sanitize_hits"], [])
        self.assertEqual(report["container_errors"], [])
        self.assertEqual(report["container_checked"]["image"], 2)

    def test_png_raw_bytes_are_still_scanned(self) -> None:
        # The field parser must not become the only path to the bytes. Here the
        # literal sits in a chunk that carries no text by definition, so the raw
        # view of the whole file is the only thing that can find it.
        data = png_wrap(png_chunk(b"IHDR", b"\x00" * 13),
                        png_chunk(b"eXIf", HOME_BYTES + b"/camera.jpg"),
                        png_chunk(b"IDAT", zlib.compress(b"\x00" * 16)),
                        png_chunk(b"IEND", b""))
        self.assertEqual(len(findings(data)), 1)
        root = self.tree()
        (root / "photo.png").write_bytes(data)
        report = staging.audit(root)
        self.assertIn("photo.png [image container] x1", report["artifact_hits"])
        self.assertEqual(report["container_errors"], [])

    def test_uncertifiable_png_containers_fail_closed(self) -> None:
        # Every case here is content-clean: the only thing wrong is that the
        # container could not be certified. Reporting those as a scan that passed
        # is the failure mode this test exists to prevent.
        cases = {
            "bad_crc.png": png_wrap(
                png_chunk(b"tEXt", b"comment\x00clean", crc=0xDEADBEEF),
                png_chunk(b"IEND", b"")),
            "truncated.png": png_wrap(png_chunk(b"tEXt", b"comment\x00clean"))[:-4]
            + b"\x00\x00\x00",
            "no_iend.png": png_wrap(png_chunk(b"tEXt", b"comment\x00clean")),
            "trailing.png": png_wrap(png_chunk(b"tEXt", b"comment\x00clean"),
                                      png_chunk(b"IEND", b"")) + b"\x00\x00after-iend",
            "not_png.png": b"\xff\xd8\xff\xe0" + b"claims a .png suffix, is not one",
            "bad_method.png": png_wrap(
                png_chunk(b"zTXt", b"comment\x00\x01" + zlib.compress(b"clean")),
                png_chunk(b"IEND", b"")),
            "bad_inflate.png": png_wrap(
                png_chunk(b"zTXt", b"comment\x00\x00not-deflated-data"),
                png_chunk(b"IEND", b"")),
            "bad_itxt_flag.png": png_wrap(
                png_chunk(b"iTXt", b"comment\x00\x07\x00\x00\x00clean"),
                png_chunk(b"IEND", b"")),
        }
        for name, data in cases.items():
            with self.subTest(name=name):
                root = self.tree("staging-" + name)
                (root / name).write_bytes(data)
                report = staging.audit(root)
                self.assertTrue(report["container_errors"],
                                f"{name} must not be reported as scanned")
                self.assertEqual(report["container_checked"]["image"], 0)
                self.assertEqual(report["checked"], 2,
                                 "an uncertifiable file is not a checked file")
                out, err = io.StringIO(), io.StringIO()
                with redirect_stdout(out), redirect_stderr(err):
                    self.assertEqual(staging.main(["--dir", str(root)]), 1)
                self.assertIn("uncertifiable", err.getvalue())
                self.assertNotIn(HOME, out.getvalue() + err.getvalue())

    def test_clean_containers_are_not_hits(self) -> None:
        root = self.tree()
        (root / "report.docx").write_bytes(office_bytes("/opt/simi/doc.md"))
        (root / "scan.pdf").write_bytes(pdf_bytes(b"/opt/simi"))
        (root / "shot.png").write_bytes(png_bytes(b"/opt/simi"))
        report = staging.audit(root)
        self.assertEqual(report["artifact_hits"], [])
        self.assertEqual(report["sanitize_hits"], [])
        self.assertEqual(report["container_checked"]["office"], 1)
        self.assertEqual(report["container_checked"]["pdf"], 1)
        self.assertEqual(report["container_checked"]["image"], 1)

    # ---- fail-closed structural cases --------------------------------------

    def test_symlink_fails_closed(self) -> None:
        root = self.tree()
        (root / "link.md").symlink_to(root / "README.md")
        with self.assertRaises(staging.StagingAuditError) as caught:
            staging.audit(root)
        self.assertIn("symlink", str(caught.exception))

    def test_missing_and_empty_directories_fail_closed(self) -> None:
        for path in (self.tmp / "absent", self.tmp / "empty"):
            if path.name == "empty":
                path.mkdir()
            with self.assertRaises(staging.StagingAuditError):
                staging.audit(path)

    def test_unreadable_file_is_not_a_clean_file(self) -> None:
        root = self.tree()
        (root / "broken.docx").write_bytes(b"not a zip at all, but claims .docx")
        report = staging.audit(root)
        self.assertTrue(report["unreadable"], "a container that cannot be unpacked must fail")
        self.assertFalse((root / "broken.docx").is_symlink())

    # ---- the self-exclusion set is the repository audit's, never a new one ---

    def test_rule_carrier_exclusion_is_reported_by_name(self) -> None:
        root = self.tree()
        (root / "tools").mkdir()
        (root / "tools" / "release_artifact_audit.py").write_text(
            'FORBIDDEN = [b"' + HOME + '"]\n', encoding="utf-8")
        report = staging.audit(root)
        self.assertEqual(report["carriers_excluded"], ["tools/release_artifact_audit.py"])
        self.assertEqual(report["artifact_hits"], [])
        self.assertEqual(report["checked"], 2, "the carrier is not counted as an audited file")

    def test_the_log_never_echoes_the_value(self) -> None:
        root = self.tree()
        (root / "leak.md").write_text("see " + HOME + "/notes\n", encoding="utf-8")
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = staging.main(["--dir", str(root)])
        self.assertEqual(code, 1)
        transcript = out.getvalue() + err.getvalue()
        self.assertNotIn(HOME, transcript)
        self.assertNotIn(FORBIDDEN[1].decode(), transcript)
        self.assertIn("leak.md", transcript or err.getvalue())

    def test_cli_verdicts_are_labelled_as_staging_only(self) -> None:
        root = self.tree()
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            self.assertEqual(staging.main(["--dir", str(root)]), 0)
        printed = out.getvalue()
        self.assertIn("RESULT staging audit = PASS", printed)
        self.assertIn("neither verdict implies the other", printed)

    # ---- the chain, end to end --------------------------------------------

    def test_build_gate_then_audit(self) -> None:
        repo = self.tmp / "repo"
        (repo / "research").mkdir(parents=True)
        (repo / "research" / "evidence.md").write_text(
            "home: " + HOME + "/notes\nuser: " + FORBIDDEN[1].decode() + "\n", encoding="utf-8")
        (repo / "inputs.json").write_text(
            '{"manifest_version": 1, "sources": [{"path": "research/evidence.md",'
            ' "output": "evidence.md"}]}', encoding="utf-8")
        out, manifest = self.tmp / "deliverable", self.tmp / "provenance.json"
        record = sanitize.build(repo / "inputs.json", out, manifest, repo)
        self.assertEqual(record["sources"][0]["rules_applied"],
                         ["home_paths", "forbidden_1"])
        self.assertEqual(sanitize.gate(out, manifest), [])

        # The deliverable is clean; the directory it came from is not. Auditing only
        # the first would pass while the second is what is public.
        self.assertEqual(staging.audit(out)["artifact_hits"], [])
        self.assertTrue(staging.audit((repo / "research"))["artifact_hits"])
        findings_in_source = findings((repo / "research" / "evidence.md").read_bytes())
        self.assertEqual(len(findings_in_source), 2)


if __name__ == "__main__":
    unittest.main()
