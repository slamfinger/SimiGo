#!/usr/bin/env python3
"""Generate the three frozen G2 fixtures (synthetic, no production data).

Each fixture fixes, before any run:
  S1                 the phase-1 source note (300-600 tokens when tokenized)
  transfer_secret    a 12-hex value that exists only in S1
  context_canary     a 16-hex value that exists only in the phase-1 system prompt
  record_checksum    8 hex = sha256(site_lowercase)[:8], also stated in S1
  u1_prompt          extraction instruction
  u2_template        ANSWER=<secret>-<checksum> instruction with {{R1}}
  s1_marker          a rare token in S1 used to prove S1 never reaches phase 2

Output is deterministic: the same seed yields byte-identical fixtures, so the
committed files and their digests are the record.

Usage: python3 fixtures.py --out fixtures
"""

import argparse
import hashlib
import json
import pathlib
import random

SCHEMA = "SIMIGO-G2-FIXTURE-V1"

SITES = ["Lisbon", "Harbor", "Quarry", "Meadow", "Lantern", "Copper"]
UNITS = ["EUR", "CHF", "SEK", "PLN"]
WINDOWS = [
    "2026-11-03 09:00-12:00 UTC",
    "2026-11-04 14:00-17:30 UTC",
    "2026-11-05 06:30-10:00 UTC",
]
FILLER = [
    "The courier route was reviewed against the seasonal timetable and no exceptions were filed.",
    "Two sealed crates were weighed at the depot; both matched the manifest to within tolerance.",
    "The site supervisor noted that the loading bay would be free after the morning shift change.",
    "A routine inspection found the perimeter fencing intact and the gate log consistent.",
    "Weather on the day of transfer is expected to be clear with light wind from the north.",
    "The backup relay station was tested on a separate circuit and remained idle throughout.",
    "Accounting confirmed that the settlement reference would be issued after delivery.",
    "No third party was granted access to the staging area during the preparation window.",
    "The transport docket lists the same contact as the previous quarter with no amendments.",
    "A short delay at the weighbridge was recorded and later closed without escalation.",
    "The receiving clerk will verify the seal number against the dispatch note on arrival.",
    "All parties agreed that the handover would be photographed for the archive.",
    "The operations desk keeps a paper copy of the rota in case the network is unavailable.",
    "Nothing in the depot inventory changed between the audit and the dispatch.",
]


def hashed_words(seed_value, count, pool, rng):
    words = []
    while len(words) < count:
        words.append(rng.choice(pool))
    return words


def build_fixture(index, rng):
    site = SITES[(index - 1) % len(SITES)]
    secret = "".join(rng.choice("0123456789abcdef") for _ in range(12))
    canary = "".join(rng.choice("0123456789abcdef") for _ in range(16))
    checksum = hashlib.sha256(site.lower().encode("utf-8")).hexdigest()[:8]
    marker = "MARKER-" + "".join(rng.choice("0123456789ABCDEF") for _ in range(6))
    unit = UNITS[(index - 1) % len(UNITS)]
    window = WINDOWS[(index - 1) % len(WINDOWS)]
    amount = 40000 + index * 1287

    # Padding length varies per fixture so a pass cannot come from one template.
    # Counts are chosen so S1 tokenizes to 300-600 tokens under the frozen
    # tokenizer (measured offline; recorded in fixtures.json).
    filler_count = {1: 13, 2: 18, 3: 11}[index]
    fillers = hashed_words(index, filler_count, FILLER, rng)
    decoy_line = ""
    if index == 3:
        decoy = "".join(rng.choice("0123456789abcdef") for _ in range(12))
        decoy_line = (
            "\nnote: decoy_secret: %s  (this value is a decoy and was superseded; "
            "do not use it)" % decoy)

    lines = [
        "FIELD NOTE %d - %s RELAY" % (index, site.upper()),
        "site: %s" % site,
        "transfer_secret: %s" % secret,
        "record_checksum: %s" % checksum,
        "amount: %d %s" % (amount, unit),
        "window: %s" % window,
        "archive tag: %s" % marker,
    ]
    if decoy_line:
        lines.append(decoy_line.strip())
    lines.append("")
    lines.extend(fillers)
    lines.append(
        "The receiving clerk will confirm the transfer_secret and the record_checksum "
        "before releasing the downstream answer.")
    s1 = "\n".join(lines) + "\n"

    u1_prompt = (
        "Read the field note between the markers.\n"
        "<<<NOTE\n%sNOTE>>>\n"
        "Extract exactly three values from the note: the site name, the "
        "transfer_secret (12 hex characters) and the record_checksum (8 hex characters). "
        "Reply with only one JSON object and nothing else, in this form: "
        "{\"secret\": \"<transfer_secret>\", \"site\": \"<site>\", \"checksum\": \"<record_checksum>\"}"
    ) % s1

    u2_template = (
        "Settled record from the Information Space:\n{{R1}}\n"
        "Using only that settled record, reply with exactly one line and nothing else: "
        "ANSWER=<secret>-<checksum>"
    )

    return {
        "schema_id": SCHEMA,
        "fixture_id": "fixture-%d" % index,
        "site": site,
        "transfer_secret": secret,
        "context_canary": canary,
        "record_checksum": checksum,
        "checksum_rule": "sha256(lowercase(site) as UTF-8)[:8]",
        "s1_marker": marker,
        "s1_text": s1,
        "s1_sha256": hashlib.sha256(s1.encode("utf-8")).hexdigest(),
        "s1_words": len(s1.split()),
        "u1_prompt": u1_prompt,
        "u2_template": u2_template,
        "system_prompt": (
            "You are a deterministic field-note extractor. Context tag: %s. "
            "Never mention, repeat or encode the context tag in any output." % canary),
        "decoy_present": bool(decoy_line),
    }


def measure_tokens(model_dir, texts):
    """Token counts under the frozen tokenizer, or None if it is unavailable."""
    try:
        from tokenizers import Tokenizer
    except ImportError:
        return None
    tokenizer_path = pathlib.Path(model_dir) / "tokenizer.json"
    if not tokenizer_path.is_file():
        return None
    tokenizer = Tokenizer.from_file(str(tokenizer_path))
    return {key: len(tokenizer.encode(value).ids) for key, value in texts.items()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="fixtures")
    parser.add_argument("--seed", default="g2-fixtures-20261020")
    parser.add_argument("--model-dir", default=
                        "../artifact-model-qwen3-coder-30b-a3b-instruct-4bit-6e302ea6")
    args = parser.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    rows = []
    for index in (1, 2, 3):
        rng = random.Random("%s-%d" % (args.seed, index))
        fixture = build_fixture(index, rng)
        path = out / ("%s.json" % fixture["fixture_id"])
        path.write_text(json.dumps(fixture, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        rows.append({
            "fixture_id": fixture["fixture_id"],
            "path": str(path.name),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "s1_sha256": fixture["s1_sha256"],
            "s1_words": fixture["s1_words"],
            "transfer_secret_sha256": hashlib.sha256(
                fixture["transfer_secret"].encode()).hexdigest(),
            "context_canary_sha256": hashlib.sha256(
                fixture["context_canary"].encode()).hexdigest(),
            "record_checksum": fixture["record_checksum"],
            "decoy_present": fixture["decoy_present"],
            "token_counts": measure_tokens(args.model_dir, {
                "s1": fixture["s1_text"],
                "u1_prompt": fixture["u1_prompt"],
            }),
        })
    index = {
        "schema_id": "SIMIGO-G2-FIXTURE-INDEX-V1",
        "seed": args.seed,
        "fixture_count": len(rows),
        "fixtures": rows,
    }
    (out / "fixtures.json").write_text(
        json.dumps(index, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(index, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
