#!/usr/bin/env python3
"""Scan tracked research artifacts for private environment data.

The shell audit intentionally uses `git grep -I`, which is appropriate for
source files but does not prove that binary evidence is clean. This audit
opens the tracked document/evidence formats used by this repository and checks
both raw bytes and decoded container streams.

PNG text metadata is parsed by `tools/png_text_chunks.py`, the module the staging
audit calls too, so one container cannot be certified here and refused there. The
privacy literals below are unchanged by that sharing: this file decides what is
searched for, the shared module decides what bytes are reachable.
"""

from __future__ import annotations

import io
import os
import re
import subprocess
import sys
import zipfile
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import png_text_chunks  # noqa: E402


FORBIDDEN = [
    b"/Users/",
    b"mr.simi",
    b"YPXU8M53F9",
    b"slamfinger@163.com",
]

OFFICE_SUFFIXES = {".docx", ".pptx", ".xlsx"}
PDF_SUFFIXES = {".pdf"}
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".heic", ".tiff", ".tif"}
SKIP_FILES = {
    Path("tools/open_source_audit.sh"),
    Path("tools/release_artifact_audit.py"),
}


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        check=True,
        capture_output=True,
    )
    return [
        Path(os.fsdecode(item))
        for item in result.stdout.split(b"\0")
        if item
    ]


def findings(data: bytes) -> list[str]:
    found: list[str] = []
    for pattern in FORBIDDEN:
        start = 0
        while True:
            offset = data.find(pattern, start)
            if offset < 0:
                break
            found.append(f"{pattern.decode('ascii')} @ byte {offset}")
            start = offset + 1
    return found


def scan_ooo(data: bytes) -> bytes:
    chunks = [data]
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for name in archive.namelist():
            member = archive.read(name)
            chunks.append(member)
            chunks.append(member.decode("utf-8", errors="ignore").encode())
    return b"\n".join(chunks)


def scan_pdf(data: bytes) -> bytes:
    chunks = [data]
    for match in re.finditer(rb"stream\r?\n(.*?)\r?\nendstream", data, re.DOTALL):
        compressed = match.group(1)
        try:
            chunks.append(zlib.decompress(compressed))
        except zlib.error:
            chunks.append(compressed)
    return b"\n".join(chunks)


def scan_png(data: bytes) -> bytes:
    """The raw file plus every text comment the shared parser can certify.

    This used to hand the whole `zTXt` payload to zlib, which the `keyword\\0method\\0`
    prefix defeats, so a comment compressed behind it was invisible to the whole-tree
    audit while the staging audit found it. `png_text_chunks.parse()` reads the fields
    positionally and inflates the body. It raises on a container it cannot certify
    rather than returning the views gathered so far: an empty answer has to mean
    "parsed cleanly", never "did not look".
    """
    return b"\n".join([data, *png_text_chunks.parse(data)])


def scan_file(path: Path) -> tuple[str, list[str]]:
    data = path.read_bytes()
    suffix = path.suffix.lower()
    if suffix in OFFICE_SUFFIXES:
        decoded = scan_ooo(data)
        kind = "office container"
    elif suffix in PDF_SUFFIXES:
        decoded = scan_pdf(data)
        kind = "pdf container"
    elif suffix in IMAGE_SUFFIXES:
        decoded = scan_png(data)
        kind = "image container"
    else:
        decoded = data + data.decode("utf-8", errors="ignore").encode()
        kind = "text/binary"
    return kind, findings(decoded)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    checked = 0
    failed = False
    uncertifiable = 0

    for path in tracked_files():
        if path in SKIP_FILES or not path.is_file():
            continue
        try:
            kind, hits = scan_file(path)
        except png_text_chunks.PngStructureError as error:
            # Fail closed, and do not count the file: a container this parser cannot
            # certify has not been scanned, whatever its bytes might have contained.
            uncertifiable += 1
            print(f"FAIL: {path}: uncertifiable png container ({error})", file=sys.stderr)
            failed = True
            continue
        except Exception as error:  # fail closed on unreadable tracked evidence
            print(f"FAIL: {path}: unable to audit ({error})", file=sys.stderr)
            failed = True
            continue
        checked += 1
        if hits:
            failed = True
            print(f"FAIL: {path} [{kind}]: {', '.join(hits)}", file=sys.stderr)

    label = "PASS" if not failed else "FAIL"
    print(f"{label}: privacy scan checked {checked} tracked file(s); "
          f"uncertifiable container(s) = {uncertifiable}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
