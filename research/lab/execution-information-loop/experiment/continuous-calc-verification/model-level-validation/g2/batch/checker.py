#!/usr/bin/env python3
"""Frozen G2 checker for the U2 answer.

Pre-registered rule (G2_PREREGISTRATION_20261020.md §4):
  U2 must emit `ANSWER=<secret>-<checksum>`, where `checksum` is derived from a
  field of the settled `R1`. The checker parses the line, verifies the format,
  the secret against the *settled* R1, and recomputes the checksum itself. It is
  not an exact-string comparison, and it never looks at the fixture's answer
  key for the pass decision.

`transfer_secret_matches_fixture` is reported separately: it is the G2-C row
"upstream came from the Information Space", not part of the format checker.
"""

import hashlib
import re

SCHEMA_ID = "SIMIGO-G2-CHECKER-V1"

ANSWER_RE = re.compile(r"^ANSWER=([0-9a-f]{12})-([0-9a-f]{8})$")


def checksum_for_site(site):
    return hashlib.sha256(str(site).lower().encode("utf-8")).hexdigest()[:8]


def check_u2(text, r1, fixture):
    stripped = (text or "").strip()
    lines = [line.strip() for line in stripped.splitlines() if line.strip()]
    match = ANSWER_RE.match(lines[-1]) if lines else None
    parsed = bool(match) and len(lines) == 1
    secret = match.group(1) if match else None
    checksum = match.group(2) if match else None

    r1_secret = (r1 or {}).get("secret")
    r1_site = (r1 or {}).get("site")
    r1_checksum = (r1 or {}).get("checksum")
    recomputed = checksum_for_site(r1_site) if r1_site is not None else None

    rows = {
        "format_ok": parsed,
        "secret_present": secret is not None,
        "secret_matches_settled_r1": bool(secret) and secret == r1_secret,
        "checksum_recomputed_from_settled_r1_site": recomputed,
        "checksum_matches_recomputed": bool(checksum) and checksum == recomputed,
        # The settled record's own checksum field: a self-consistent R1 must
        # agree with the recomputation, otherwise R1 is internally inconsistent.
        "settled_r1_checksum_self_consistent": bool(recomputed)
        and r1_checksum == recomputed,
        "transfer_secret_matches_fixture": bool(secret)
        and secret == (fixture or {}).get("transfer_secret"),
        "line_count": len(lines),
        "parsed_secret": secret,
        "parsed_checksum": checksum,
        "r1_secret": r1_secret,
        "r1_site": r1_site,
        "r1_checksum": r1_checksum,
        "recomputed_checksum": recomputed,
        "raw_text": text,
    }
    rows["pass"] = all([
        rows["format_ok"],
        rows["secret_matches_settled_r1"],
        rows["checksum_matches_recomputed"],
    ])
    return {"schema_id": SCHEMA_ID, "rule": "ANSWER=<secret>-<checksum>", **rows}
