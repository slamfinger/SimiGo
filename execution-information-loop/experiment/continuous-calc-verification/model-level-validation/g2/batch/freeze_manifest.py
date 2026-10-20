#!/usr/bin/env python3
"""Freeze the single G2 batch manifest and its authorization token.

The token is not a new grant. It binds the existing human authorization
`G2-BATCH-AUTH-20261020-01` to the digest of exactly this manifest, so the
runner can consume it atomically before the first child launch.

Usage: python3 freeze_manifest.py [--dry-run]
"""

import argparse
import datetime
import hashlib
import json
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[5]
G2 = HERE.parent
MODEL_DIR = G2 / "artifact-model-qwen3-coder-30b-a3b-instruct-4bit-6e302ea6"
BINDING = REPO / "docs/01-questions/G2_MODEL_BINDING_20261020.json"
PREREG = REPO / "docs/01-questions/G2_PREREGISTRATION_20261020.md"
AUTH_DOC = REPO / "docs/01-questions/G2_BATCH_AUTHORIZATION_20261020.md"
P0_TERMINAL = G2 / "p0" / "20261020T075257Z" / "terminal.json"
P0_RESULT = G2 / "p0" / "P0_A2_RESULT_20261020.md"
MANIFEST_DIR = G2 / "manifest"
MANIFEST = MANIFEST_DIR / "G2_MANIFEST.json"
MANIFEST_SHA = MANIFEST_DIR / "G2_MANIFEST.json.sha256"
TOKEN = MANIFEST_DIR / "G2_AUTHORIZATION.token"
EVIDENCE = G2 / "evidence"
FIXTURES = HERE / "fixtures"
HOST_BIN = HERE / "host" / ".build" / "release" / "G2Host"

SUPERSEDED_MANIFEST = (
    "81a78e7e940c3e7b3fe78c52fd8ca88695809d8762c7b132561dcae44498ef5c")

AUTHORIZATION_ID = "G2-BATCH-AUTH-20261020-01"
EXPECTED_WEIGHTS = "d1f01c0c98db2d07a437e81372dffc49c04e728342cec8f72cc2929caeeb6abf"
EXPECTED_TOKENIZER = "9bada7c8fddefc7e91cf3bbe9b56305d5234c73e16732518dc4f3825b2d84ac3"
EXPECTED_COMBINED = "bb0b2711451cbabc1efc0aae3e282dde166db6f0e82ba245905b4848bf71ec58"
BUDGET = {
    "model_starts_planned": 9,
    "model_starts_max": 9,
    "retries": 0,
    "negative_control_processes_max": 6,
    "process_calls_max": 15,
}


def sha256_file(path):
    hasher = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            hasher.update(block)
    return hasher.hexdigest()


def git(*args):
    result = subprocess.run(["git", "-C", str(REPO)] + list(args),
                            capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit("git %s failed: %s" % (" ".join(args), result.stderr.strip()))
    return result.stdout.strip()


def rel(path):
    return str(pathlib.Path(path).resolve().relative_to(REPO))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    binding = json.loads(BINDING.read_text(encoding="utf-8"))
    model = binding["model"]
    if not HOST_BIN.is_file():
        sys.exit("host product missing; build it before freezing")
    if not P0_TERMINAL.is_file():
        sys.exit("P0 terminal record missing")
    p0_terminal = json.loads(P0_TERMINAL.read_text(encoding="utf-8"))
    if p0_terminal.get("terminal_state") != "PASS":
        sys.exit("P0 is not PASS; a batch manifest may not be issued")

    fixture_index = json.loads((FIXTURES / "fixtures.json").read_text(encoding="utf-8"))
    fixtures = []
    for row in fixture_index["fixtures"]:
        body = json.loads((FIXTURES / row["path"]).read_text(encoding="utf-8"))
        if body["context_canary"] in body["s1_text"] \
                or body["context_canary"] in body["u1_prompt"]:
            sys.exit("canary placement violation in %s" % row["path"])
        if body["transfer_secret"] not in body["s1_text"]:
            sys.exit("transfer secret absent from S1 in %s" % row["path"])
        token_counts = row.get("token_counts") or {}
        if not 300 <= token_counts.get("s1", 0) <= 600:
            sys.exit("S1 token count outside the frozen 300-600 range in %s"
                     % row["path"])
        fixtures.append({
            "fixture_id": body["fixture_id"],
            "file": row["path"],
            "sha256": row["sha256"],
            "s1_sha256": body["s1_sha256"],
            "s1_word_count": body["s1_words"],
            "s1_token_count": token_counts.get("s1"),
            "u1_prompt_token_count": token_counts.get("u1_prompt"),
            "transfer_secret_sha256": row["transfer_secret_sha256"],
            "context_canary_sha256": row["context_canary_sha256"],
            "record_checksum": body["record_checksum"],
            "decoy_present": body["decoy_present"],
        })

    manifest = {
        "schema_id": "SIMIGO-G2-BATCH-MANIFEST-V1",
        "manifest_id": "G2-BATCH-20261020-01",
        "created_at_utc": datetime.datetime.now(datetime.timezone.utc)
        .strftime("%Y-%m-%dT%H:%M:%SZ"),
        "authorization": {
            "id": AUTHORIZATION_ID,
            "record": rel(AUTH_DOC),
            "sha256": sha256_file(AUTH_DOC),
            "status": "AUTHORIZED — ONE BATCH ONLY",
        },
        "preregistration": {
            "record": rel(PREREG),
            "sha256": sha256_file(PREREG),
            "status": "FROZEN",
        },
        "p0": {
            "terminal": rel(P0_TERMINAL),
            "terminal_state": p0_terminal["terminal_state"],
            "result_record": rel(P0_RESULT),
            "run_id": "20261020T075257Z",
            "gate": "P0 gate only; opens no evidence gate for G2-A/B/C",
        },
        "model_binding": {
            "record": rel(BINDING),
            "sha256": sha256_file(BINDING),
            "repo_id": model["repo_id"],
            "revision": model["revision"],
            "file_count": model["file_count"],
            "total_bytes": model["total_bytes"],
            "aggregate_sha256": model["aggregate_sha256"],
            "model_dir": rel(MODEL_DIR),
            "model_dir_form": "dereferenced A2 copy (17 regular files, 0 symlinks)",
            "expected_engine_identity": {
                "weights_digest": EXPECTED_WEIGHTS,
                "tokenizer_digest": EXPECTED_TOKENIZER,
                "combined_digest": EXPECTED_COMBINED,
                "source": "P0-A2 run 20261020T075257Z",
            },
        },
        "backend": {
            "package_swift": {"path": rel(HERE / "host" / "Package.swift"),
                              "sha256": sha256_file(HERE / "host" / "Package.swift")},
            "package_resolved": {"path": rel(HERE / "host" / "Package.resolved"),
                                 "sha256": sha256_file(HERE / "host" / "Package.resolved")},
            "build_product": {"path": rel(HOST_BIN),
                              "sha256": sha256_file(HOST_BIN)},
            "swift_version": subprocess.run(["swift", "--version"], capture_output=True,
                                              text=True).stdout.splitlines()[:1],
        },
        "source_revision_at_freeze": git("rev-parse", "HEAD"),
        "freeze_history": [{
            "superseded_manifest_sha256": SUPERSEDED_MANIFEST,
            "status": "superseded before execution; never committed, never consumed",
            "reason": (
                "the first draft used flat build/runner keys while the runner's "
                "preflight reads executables/backend objects; preflight refuses "
                "before the token is consumed and before any child launch, so no "
                "model start was ever charged against it"),
        }],
        "tracked_tree_clean_at_freeze":
            git("status", "--porcelain", "--untracked-files=no") == "",
        "freeze_note": (
            "the batch payload and this manifest are committed together right after the "
            "freeze; the runner itself refuses to start unless `git status --porcelain` "
            "is empty at launch time"),
        "executables": {
            "runner": {"path": rel(HERE / "run_batch.py"),
                       "sha256": sha256_file(HERE / "run_batch.py"),
                       "version": 1},
            "gate": {"path": rel(HERE / "carrier_gate.py"),
                     "sha256": sha256_file(HERE / "carrier_gate.py")},
            "checker": {"path": rel(HERE / "checker.py"),
                        "sha256": sha256_file(HERE / "checker.py")},
            "fixtures_generator": {"path": rel(HERE / "fixtures.py"),
                                   "sha256": sha256_file(HERE / "fixtures.py")},
        },
        "fixtures": fixtures,
        "matrix": {
            "fixtures": 3,
            "arms": ["A: continuous baseline", "B phase 1: settle, no export",
                     "B phase 2: cold restore and U2"],
            "negative_controls": ["C-missing: SETTLEMENT_MISSING",
                                  "C-tampered: OBJECT_DIGEST_MISMATCH"],
            "model_starts_per_fixture": 3,
            "generation": {"decoding": "greedy (temperature = 0)",
                           "max_tokens_u1": 256, "max_tokens_u2": 128,
                           "prefill": "canonical-remainder-v1 (.remainder, step 256)"},
        },
        "budget": BUDGET,
        "evidence_root": rel(EVIDENCE),
        "terminal_states": ["PASS", "FAIL", "INCONCLUSIVE"],
        "stop_rules": [
            "no retry, no model substitution, no fixture substitution, no matrix expansion",
            "a canary in R1 voids the fixture and stops the batch",
            "a canary on any phase-2 surface fails G2-A",
            "a negative control that continues fails G2-B",
            "any run after this one needs a new manifest and a new authorization",
        ],
        "not_established_by_this_manifest": [
            "peak memory was never measured",
            "the symlink reader defect (A3) is untouched",
            "tokenizer digest reproducibility across directories is reported, not proven",
            "G2-A, G2-B and G2-C are undecided until the run's own evidence exists",
        ],
    }
    if args.dry_run:
        print(json.dumps(manifest, indent=2, sort_keys=True))
        return

    for path in (MANIFEST, MANIFEST_SHA, TOKEN):
        if path.exists():
            sys.exit("refusing to overwrite existing %s" % path)
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8")
    manifest_sha = sha256_file(MANIFEST)
    MANIFEST_SHA.write_text("%s  G2_MANIFEST.json\n" % manifest_sha, encoding="utf-8")
    TOKEN.write_text(json.dumps({
        "schema_id": "SIMIGO-G2-BATCH-AUTHORIZATION-TOKEN-V1",
        "authorization_id": AUTHORIZATION_ID,
        "authorization_record": rel(AUTH_DOC),
        "authorization_sha256": sha256_file(AUTH_DOC),
        "manifest_sha256": manifest_sha,
        "issued_at_utc": datetime.datetime.now(datetime.timezone.utc)
        .strftime("%Y-%m-%dT%H:%M:%SZ"),
        "issued_by": "freeze step; derived from the existing authorization, not a new grant",
        "consumption": "atomic rename before the first child launch; no second run",
    }, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"manifest": str(MANIFEST), "sha256": manifest_sha,
                      "token": str(TOKEN)}, indent=2))


if __name__ == "__main__":
    main()
