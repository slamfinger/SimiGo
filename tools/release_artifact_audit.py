#!/usr/bin/env python3
"""Scan tracked research artifacts for private environment data.

The shell audit intentionally uses `git grep -I`, which is appropriate for
source files but does not prove that binary evidence is clean. This audit
opens the tracked document/evidence formats used by this repository and checks
both raw bytes and decoded container streams.
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
    chunks = [data]
    offset = 8
    while offset + 12 <= len(data):
        length = int.from_bytes(data[offset : offset + 4], "big")
        kind = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        if kind in {b"tEXt", b"iTXt", b"zTXt"}:
            chunks.append(payload)
            try:
                chunks.append(zlib.decompress(payload))
            except zlib.error:
                pass
        offset += 12 + length
        if kind == b"IEND":
            break
    return b"\n".join(chunks)


def scan_file(path: Path) -> tuple[int, list[str]]:
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

    for path in tracked_files():
        if path in SKIP_FILES or not path.is_file():
            continue
        try:
            kind, hits = scan_file(path)
        except Exception as error:  # fail closed on unreadable tracked evidence
            print(f"FAIL: {path}: unable to audit ({error})", file=sys.stderr)
            failed = True
            continue
        checked += 1
        if hits:
            failed = True
            print(f"FAIL: {path} [{kind}]: {', '.join(hits)}", file=sys.stderr)

    print(f"PASS: privacy scan checked {checked} tracked files")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
