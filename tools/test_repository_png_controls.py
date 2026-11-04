#!/usr/bin/env python3
"""Dual-entry controls: one PNG must get the same verdict from both scan engines.

The repository audit (`tools/release_artifact_audit.py`, driven by
`tools/open_source_audit.sh`) and the staging audit (`tools/release_staging_audit.py`)
measure two different objects and their verdicts must never be merged. Before this
suite they could not even be compared: the repository decoder handed a whole `zTXt`
payload to zlib, so a comment compressed behind `keyword\\0method\\0` was invisible
there while the staging audit found it. Both now call `tools/png_text_chunks.py`.

Each control therefore runs the *same bytes through both entries* and requires the
same verdict, at the exit-code level rather than only at the parser level:

* a legal compressed `zTXt` and a legal compressed `iTXt`, each carrying a forbidden
  literal: both entries fail;
* a legal PNG carrying nothing forbidden: both entries pass;
* a corrupt CRC, a truncation, a missing `IEND` and trailing bytes after `IEND`:
  both entries fail, even though the contents are clean, because an uncertifiable
  container has not been scanned.

Hand-built compressed fixtures are the point: the tracked images in this repository
carry uncompressed comments, so a real-file measurement alone would never exercise
the inflated path. The last test checks the real files anyway, for agreement only --
it does not claim the tree is clean, and research hits stay where they are.

Nothing in this file spells a forbidden literal: the fixtures are assembled, so the
suite can live inside the tree it helps to audit.
"""

from __future__ import annotations

import binascii
import io
import os
import subprocess
import sys
import tempfile
import unittest
import zlib
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import png_text_chunks  # noqa: E402
import release_artifact_audit as artifact  # noqa: E402
import release_staging_audit as staging  # noqa: E402

HOME = "/" + "Users/" + "alice"
HOME_BYTES = HOME.encode()
CLEAN_COMMENT = b"/opt/simi/notes"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def png_chunk(kind: bytes, data: bytes, crc: int | None = None) -> bytes:
    checksum = (binascii.crc32(kind + data) & 0xFFFFFFFF) if crc is None else crc
    return len(data).to_bytes(4, "big") + kind + data + checksum.to_bytes(4, "big")


def png_wrap(*chunks: bytes) -> bytes:
    return PNG_SIGNATURE + b"".join(chunks)


def well_formed(body: bytes, *chunks: bytes) -> bytes:
    return png_wrap(*chunks, body, png_chunk(b"IEND", b""))


def ztxt_bytes(comment: bytes) -> bytes:
    """Legal `zTXt`: `keyword\\0method\\0compressed` -- only an inflated view reaches it."""
    return well_formed(png_chunk(
        b"zTXt", b"comment\x00\x00" + zlib.compress(comment)),
        png_chunk(b"IHDR", b"\0" * 13))


def itxt_bytes(comment: bytes) -> bytes:
    """Legal compressed `iTXt`: flag=1, method=0, then language, translated keyword, text."""
    payload = (b"comment\x00" + b"\x01\x00" + b"\x00" + b"\x00" + zlib.compress(comment))
    return well_formed(png_chunk(b"iTXt", payload), png_chunk(b"IHDR", b"\0" * 13))


def ttxt_bytes(comment: bytes) -> bytes:
    return well_formed(png_chunk(b"tEXt", b"comment\x00" + comment),
                       png_chunk(b"IHDR", b"\0" * 13))


def broken_cases() -> dict[str, bytes]:
    """Structurally uncertifiable containers whose *contents* are clean."""
    clean = png_chunk(b"tEXt", b"comment\x00" + CLEAN_COMMENT)
    iend = png_chunk(b"IEND", b"")
    return {
        "bad_crc.png": png_wrap(png_chunk(b"tEXt", b"comment\x00" + CLEAN_COMMENT,
                                          crc=0xDEADBEEF), iend),
        "truncated.png": png_wrap(clean, iend)[: len(PNG_SIGNATURE) + 8 + 12],
        "no_iend.png": png_wrap(clean),
        "trailing.png": png_wrap(clean, iend) + b"\x00\x00after-iend",
        "not_a_png.png": b"\xff\xd8\xff\xe0" + b"a jpeg claiming a png suffix",
        "bad_method.png": png_wrap(
            png_chunk(b"zTXt", b"comment\x00\x09" + zlib.compress(CLEAN_COMMENT)), iend),
        "bad_inflate.png": png_wrap(
            png_chunk(b"zTXt", b"comment\x00\x00not-deflated"), iend),
        "bad_itxt_flag.png": png_wrap(
            png_chunk(b"iTXt", b"comment\x00\x07\x00\x00\x00" + CLEAN_COMMENT), iend),
        "long_keyword.png": png_wrap(png_chunk(b"tEXt", b"k" * 80 + b"\x00" + CLEAN_COMMENT),
                                     iend),
    }


def repository_cli(paths: list[Path]) -> tuple[int, str]:
    """The repository entry's own exit code, over exactly these files."""
    out, err = io.StringIO(), io.StringIO()
    original = artifact.tracked_files
    artifact.tracked_files = lambda: paths
    try:
        with redirect_stdout(out), redirect_stderr(err):
            code = artifact.main()
    finally:
        artifact.tracked_files = original
    return code, out.getvalue() + err.getvalue()


def repository_status(path: Path) -> tuple[str, list[str]]:
    try:
        kind, hits = artifact.scan_file(path)
    except png_text_chunks.PngStructureError as error:
        return "uncertifiable", [str(error)]
    return ("hit" if hits else "clean"), hits


class DualEntryPngControls(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory(prefix="repo-png-controls.")
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.tree = self.tmp / "tree"
        self.tree.mkdir()

    def write(self, name: str, data: bytes) -> Path:
        path = self.tree / name
        path.write_bytes(data)
        return path

    def staging_cli(self) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = staging.main(["--dir", str(self.tree)])
        return code, out.getvalue() + err.getvalue()

    def assert_both_fail(self, name: str, data: bytes, expect: str) -> None:
        path = self.write(name, data)
        repo_code, repo_text = repository_cli([path])
        stage_code, stage_text = self.staging_cli()
        self.assertEqual(1, repo_code, f"repository entry passed on {name}")
        self.assertEqual(1, stage_code, f"staging entry passed on {name}")
        self.assertIn(expect, repo_text)
        self.assertIn(expect, stage_text)
        status, _ = repository_status(path)
        self.assertNotEqual("clean", status)

    # ---- the two compressed shapes that used to split the entries -----------

    def test_compressed_ztxt_forbidden_literal_fails_both_entries(self) -> None:
        data = ztxt_bytes(HOME_BYTES + b"/shot.png")
        self.assertEqual(artifact.findings(data), [], "reachable only once inflated")
        self.assert_both_fail("hidden.png", data, "hidden.png")

    def test_compressed_itxt_forbidden_literal_fails_both_entries(self) -> None:
        data = itxt_bytes(HOME_BYTES + b"/shot.png")
        self.assertEqual(artifact.findings(data), [], "reachable only once inflated")
        self.assert_both_fail("meta.png", data, "meta.png")

    def test_both_entries_count_the_inflated_hit_the_same_way(self) -> None:
        path = self.write("same.png", ztxt_bytes(HOME_BYTES + b"/x"))
        kind, repo_hits = artifact.scan_file(path)
        report = staging.audit(self.tree)
        self.assertEqual("image container", kind)
        self.assertEqual(len(repo_hits), 1)
        self.assertIn("same.png [image container] x1", report["artifact_hits"])

    # ---- a clean legal PNG must not become a failure because the parser got stricter ---

    def test_clean_png_passes_both_entries(self) -> None:
        for name, data in (("clean_ztxt.png", ztxt_bytes(CLEAN_COMMENT)),
                           ("clean_itxt.png", itxt_bytes(CLEAN_COMMENT)),
                           ("clean_text.png", ttxt_bytes(CLEAN_COMMENT))):
            with self.subTest(name=name):
                path = self.write(name, data)
                repo_code, repo_text = repository_cli([path])
                stage_code, stage_text = self.staging_cli()
                self.assertEqual(0, repo_code, repo_text)
                self.assertEqual(0, stage_code, stage_text)
                self.assertEqual("clean", repository_status(path)[0])
                report = staging.audit(self.tree)
                self.assertEqual([], report["container_errors"])
                self.assertEqual([], report["artifact_hits"])

    # ---- uncertifiable containers: fail closed in both, whatever the contents ---

    def test_uncertifiable_containers_fail_both_entries(self) -> None:
        for name, data in broken_cases().items():
            with self.subTest(name=name):
                path = self.write(name, data)
                repo_code, repo_text = repository_cli([path])
                stage_code, stage_text = self.staging_cli()
                self.assertEqual(1, repo_code, f"repository entry passed on {name}")
                self.assertIn("uncertifiable png container", repo_text)
                self.assertEqual(1, stage_code, f"staging entry passed on {name}")
                self.assertIn("uncertifiable", stage_text)
                self.assertEqual("uncertifiable", repository_status(path)[0])
                report = staging.audit(self.tree)
                self.assertEqual(0, report["container_checked"]["image"])
                self.assertEqual(0, report["checked"],
                                 "an uncertifiable file is not a scanned file")
                self.assertNotIn(CLEAN_COMMENT.decode(), repo_text + stage_text,
                                 "the transcript names the file, never the value")

    # ---- one implementation, one rule set ----------------------------------

    def test_both_entries_call_the_same_parser(self) -> None:
        self.assertIs(png_text_chunks.parse, staging.png_text_views)
        self.assertIs(png_text_chunks.views_and_errors, staging.png_views)
        self.assertIs(png_text_chunks, artifact.png_text_chunks)
        self.assertIs(png_text_chunks.PngStructureError, staging.PngStructureError)

    def test_sharing_the_parser_did_not_change_what_is_searched_for(self) -> None:
        # The privacy scope is the same object in both entries: this round moved how
        # bytes become reachable, not which literals count as a leak.
        self.assertIs(staging.FORBIDDEN, artifact.FORBIDDEN)
        self.assertEqual(4, len(artifact.FORBIDDEN))
        self.assertEqual({Path("tools/open_source_audit.sh"),
                          Path("tools/release_artifact_audit.py")},
                         set(artifact.SKIP_FILES))

    def test_tracked_images_get_the_same_verdict_from_both_entries(self) -> None:
        """Agreement over the real files -- not a claim that the tree is clean."""
        root = Path(__file__).resolve().parents[1]
        listed = subprocess.run(["git", "-C", str(root), "ls-files", "-z"],
                                capture_output=True).stdout.split(b"\0")
        images = [root / os.fsdecode(item) for item in listed
                  if item and os.fsdecode(item).lower().endswith(".png")
                  and (root / os.fsdecode(item)).is_file()]
        for path in images:
            with self.subTest(path=str(path.relative_to(root).as_posix())):
                self.tree.mkdir(exist_ok=True)
                target = self.write(path.name, path.read_bytes())
                status, _ = repository_status(target)
                report = staging.audit(self.tree)
                blocked = bool(report["artifact_hits"] or report["container_errors"]
                               or report["unreadable"])
                self.assertEqual(status == "uncertifiable",
                                 bool(report["container_errors"]))
                self.assertEqual(status == "hit", blocked and not report["container_errors"])


if __name__ == "__main__":
    unittest.main()
