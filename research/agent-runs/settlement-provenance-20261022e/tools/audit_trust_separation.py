#!/usr/bin/env python3
"""Audit the C4 trust root: signing key and anchor separation from the database.

The claim under test is narrow and checkable:
  * the private key lives in its own file with owner-only permissions;
  * the trust anchor is a separate read-only file with the same key id;
  * the attacker anchor keeps the key id but changes the public key;
  * no SQLite database in the run root contains the private key material;
  * consumer processes are constructed without a signing key.

This audit does not claim resistance when the attacker can read the key file
or rewrite the anchor; that scenario (T3) is explicitly outside C4.
"""
from __future__ import annotations

import base64
import hashlib
import json
import re
import stat
from pathlib import Path

RUN_ROOT = Path(__file__).resolve().parents[1]
TRUST = RUN_ROOT / "trust"
LAB = Path("/Users/mr.simi/Documents/SimiGo-Lab")
RUNNER = (LAB / "simigo2-experimental/scripts/ordinary_task/run_phase_e.py")
LOOP = LAB / "execution-information-loop/carrier_loop.py"
BRIDGE = LAB / "execution-information-loop/production_runtime_bridge.py"
PROVENANCE = LAB / "execution-information-loop/settlement_provenance.py"


def permissions(path: Path) -> str:
    return oct(stat.S_IMODE(path.stat().st_mode))


def main() -> int:
    key = json.loads((TRUST / "settlement-signing-key.json").read_text())
    anchor = json.loads((TRUST / "settlement-trust-anchor.json").read_text())
    attacker = json.loads((TRUST / "attacker-anchor.json").read_text())
    private_raw = base64.b64decode(key["private_key_base64"])
    private_forms = {
        "base64": key["private_key_base64"].encode(),
        "raw": private_raw,
        "hex": private_raw.hex().encode(),
    }
    databases = [
        path for path in RUN_ROOT.rglob("*.sqlite")
        if "previous-attempts" not in path.relative_to(RUN_ROOT).parts
    ]
    leaks = []
    scanned_bytes = 0
    for database in databases:
        content = database.read_bytes()
        scanned_bytes += len(content)
        for name, needle in private_forms.items():
            if needle and needle in content:
                leaks.append({"database": str(database.relative_to(RUN_ROOT)),
                              "form": name})
    runner_text = RUNNER.read_text(encoding="utf-8")
    loop_text = LOOP.read_text(encoding="utf-8")
    bridge_text = BRIDGE.read_text(encoding="utf-8")
    provenance_text = PROVENANCE.read_text(encoding="utf-8")
    sign_callers = {
        path.name: text.count("settlement_provenance.sign_declaration(")
        for path in sorted((LAB / "execution-information-loop").glob("*.py"))
        for text in [path.read_text(encoding="utf-8")]
        if "settlement_provenance.sign_declaration(" in text
    }
    bridge_commands = set(re.findall(r'add_parser\("([^"]+)"', bridge_text))
    build_at = loop_text.find("settlement_provenance.build_declaration(")
    sign_at = loop_text.find("settlement_provenance.sign_declaration(")
    checks = {
        "signing_key_mode_is_0600":
            permissions(TRUST / "settlement-signing-key.json") == "0o600",
        "trust_anchor_mode_is_0444":
            permissions(TRUST / "settlement-trust-anchor.json") == "0o444",
        "signing_key_is_ed25519": key.get("algorithm") == "Ed25519",
        "trust_anchor_is_ed25519": anchor.get("algorithm") == "Ed25519",
        "key_and_anchor_share_key_id":
            key.get("key_id") == anchor.get("key_id"),
        "key_and_anchor_share_public_key":
            key.get("public_key_base64") == anchor.get("public_key_base64"),
        "attacker_anchor_reuses_key_id":
            attacker.get("key_id") == anchor.get("key_id"),
        "attacker_public_key_differs":
            attacker.get("public_key_base64") != anchor.get("public_key_base64"),
        "private_key_material_absent_from_databases": not leaks,
        "databases_scanned": len(databases) > 0,
        "consumer_runs_are_built_without_key":
            runner_text.count("with_key=False") >= 2
            and "policy=\"verify\"" in runner_text,
        "sign_declaration_has_one_caller":
            sign_callers == {LOOP.name: 1}
            and provenance_text.count("def sign_declaration(") == 1,
        "signing_key_loaded_only_via_load_policy":
            provenance_text.count("SigningKey.load(") == 1,
        "bridge_exposes_no_signing_command":
            not ({"sign", "sign-declaration", "settle"} & bridge_commands),
        "settle_signs_only_after_declaration_built":
            0 <= build_at < sign_at,
    }
    report = {
        "schema_id": "SIMIGO-E-ROUND-TRUST-SEPARATION-AUDIT-V1",
        "trust_root": str(TRUST),
        "key_id": key.get("key_id"),
        "key_path": str(TRUST / "settlement-signing-key.json"),
        "key_mode": permissions(TRUST / "settlement-signing-key.json"),
        "anchor_path": str(TRUST / "settlement-trust-anchor.json"),
        "anchor_mode": permissions(TRUST / "settlement-trust-anchor.json"),
        "anchor_sha256": hashlib.sha256(
            (TRUST / "settlement-trust-anchor.json").read_bytes()).hexdigest(),
        "attacker_anchor_sha256": hashlib.sha256(
            (TRUST / "attacker-anchor.json").read_bytes()).hexdigest(),
        "databases_scanned": [
            path.relative_to(RUN_ROOT).as_posix() for path in databases],
        "database_bytes_scanned": scanned_bytes,
        "private_key_forms_checked": sorted(private_forms),
        "sign_declaration_callers": sign_callers,
        "bridge_commands": sorted(bridge_commands),
        "leaks": leaks,
        "checks": checks,
        "verdict": "PASS" if all(checks.values()) else "FAIL",
        "not_claimed": [
            "protection when an attacker can read the key file",
            "protection when an attacker can rewrite the trust anchor",
            "database-instance lineage of a complete signed history",
        ],
    }
    output = RUN_ROOT / "logs" / "trust-separation-audit.json"
    output.write_text(json.dumps(report, indent=1, sort_keys=True) + "\n",
                      encoding="utf-8")
    print(json.dumps({
        "verdict": report["verdict"],
        "false_checks": [k for k, v in checks.items() if not v],
        "databases": len(databases),
        "database_bytes_scanned": scanned_bytes,
        "report": str(output),
    }, ensure_ascii=False, indent=1))
    return 0 if report["verdict"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
