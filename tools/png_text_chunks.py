#!/usr/bin/env python3
"""Strict PNG text-metadata parsing, shared by both privacy scan entries.

One implementation exists because two were measured to disagree. The repository
audit appended a `zTXt` payload and handed the *whole* payload to zlib, which the
`keyword\\0method\\0` prefix defeats, so a comment compressed behind it was invisible
to the whole-tree audit while the staging audit found it. Both entries now call
`parse()` here: a container that cannot be certified fails the same way in both, and
a future fix cannot land in one scanner and not the other.

Fail closed. `parse()` either returns every decodable text view of a *certified*
container or raises `PngStructureError`; it never returns the views gathered so far,
because a caller that sees an empty list must be able to read that as "parsed and
clean" rather than "not looked at".

Nothing in this module matches privacy patterns. The literals and their scope stay
in `release_artifact_audit.FORBIDDEN`, unchanged: this file turns a container into
bytes worth searching, and decides whether the container may be trusted at all.
"""

from __future__ import annotations

import binascii
import zlib

RULES = "png-text-chunks-2026-11-01.1"

SIGNATURE = b"\x89PNG\r\n\x1a\n"
TEXT_CHUNKS = {b"tEXt", b"zTXt", b"iTXt"}
DEFLATE = 0x00
MAX_KEYWORD = 79
CHUNK_TYPE_BYTES = bytes(range(65, 91)) + bytes(range(97, 123))


class PngStructureError(Exception):
    """A PNG container that could not be certified."""


def _keyword_tail(payload: bytes, offset: int) -> bytes:
    """Return the bytes after the keyword's NUL terminator."""
    separator = payload.find(b"\x00")
    if separator < 0:
        raise PngStructureError(f"text chunk at offset {offset} has no keyword terminator")
    if not 1 <= separator <= MAX_KEYWORD:
        raise PngStructureError(
            f"text chunk at offset {offset} keyword length {separator} is out of range")
    return payload[separator + 1:]


def _inflate(data: bytes, offset: int, label: str) -> bytes:
    try:
        return zlib.decompress(data)
    except zlib.error as error:
        raise PngStructureError(
            f"{label} chunk at offset {offset} could not be inflated "
            f"({type(error).__name__})") from error


def _text_chunk(kind: bytes, payload: bytes, offset: int) -> bytes:
    """Decode one text-metadata chunk into the bytes a reader would actually see.

    Field order is taken from the format, not from a fixed offset: `tEXt` is
    `keyword\\0text`, `zTXt` is `keyword\\0method\\0compressed`, and `iTXt` is
    `keyword\\0flag\\0method\\0language\\0translated\\0text`. The flag and method
    bytes can themselves be 0x00, which is why they are read positionally instead
    of by splitting on NUL.
    """
    tail = _keyword_tail(payload, offset)
    if kind == b"tEXt":
        return tail
    if len(tail) < 2:
        raise PngStructureError(f"{kind.decode()} chunk at offset {offset} is truncated")
    if kind == b"zTXt":
        if tail[0] != DEFLATE:
            raise PngStructureError(
                f"zTXt chunk at offset {offset} uses unsupported compression method {tail[0]}")
        return _inflate(tail[1:], offset, "zTXt")
    flag, method = tail[0], tail[1]
    if flag not in (0, 1):
        raise PngStructureError(
            f"iTXt chunk at offset {offset} has invalid compression flag {flag}")
    if flag == 1 and method != DEFLATE:
        raise PngStructureError(
            f"iTXt chunk at offset {offset} uses unsupported compression method {method}")
    fields = tail[2:].split(b"\x00", 2)
    if len(fields) < 3:
        raise PngStructureError(
            f"iTXt chunk at offset {offset} is missing its text terminator")
    return _inflate(fields[2], offset, "iTXt") if flag else fields[2]


def parse(data: bytes) -> list[bytes]:
    """Every decodable text view of a certified PNG, in chunk order.

    The container is certified before any view is returned: signature, chunk length
    and bounds, a type made of four alphabetic bytes, a matching per-chunk CRC, an
    `IEND` before the end of the file and no bytes after it. A trailing fragment is
    not scanned as if it belonged to the image -- it is a container that cannot be
    certified -- and bytes past the declared end of a chunk are not invented.
    """
    if not data.startswith(SIGNATURE):
        raise PngStructureError("an image-suffixed file that is not a PNG container")
    views: list[bytes] = []
    offset = len(SIGNATURE)
    seen_iend = False
    while offset + 12 <= len(data):
        length = int.from_bytes(data[offset:offset + 4], "big")
        kind = data[offset + 4:offset + 8]
        if any(byte not in CHUNK_TYPE_BYTES for byte in kind):
            raise PngStructureError(
                f"chunk at offset {offset} has a type outside the four alphabetic bytes")
        payload_end = offset + 8 + length
        if payload_end + 4 > len(data):
            raise PngStructureError(
                f"chunk at offset {offset} declares {length} bytes that run past the file")
        payload = data[offset + 8:payload_end]
        stored_crc = int.from_bytes(data[payload_end:payload_end + 4], "big")
        if binascii.crc32(kind + payload) & 0xFFFFFFFF != stored_crc:
            raise PngStructureError(f"chunk at offset {offset} fails its CRC check")
        if kind in TEXT_CHUNKS:
            views.append(_text_chunk(kind, payload, offset))
        offset = payload_end + 4
        if kind == b"IEND":
            if offset != len(data):
                raise PngStructureError(
                    f"{len(data) - offset} trailing byte(s) after the IEND chunk")
            seen_iend = True
            break
    if not seen_iend:
        raise PngStructureError("no IEND chunk before the end of the file")
    return views


def views_and_errors(data: bytes) -> tuple[list[bytes], list[str]]:
    """(views, errors) for one image file: an uncertifiable container is an error.

    Anything that can be scanned is still scanned raw by the caller; this only ever
    adds decoded text views and the structural verdict, never removes one.
    """
    try:
        return parse(data), []
    except PngStructureError as error:
        return [], [str(error)]
