#!/usr/bin/env python3
"""Probe the fail-closed policy=off branch on the real signed E world.

The E matrix exercises the production consumer policy ``verify`` and the
legacy producer policy ``required``.  This probe covers the remaining branch:
a database that already contains signed settlements is opened with policy
``off`` (the isolated-library setting).  Such a consumer has no trust anchor,
so it must not silently reuse the signed settlement.  It must report
``SETTLEMENT_SIGNATURE_UNVERIFIABLE`` and recompute instead.

The authoritative world-a database is only read; every mutation happens on a
temporary copy.  The same copy is also opened with ``verify`` as a positive
control: with the run trust anchor, the signed settlement must be reused.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

LAB = Path("/Users/mr.simi/Documents/SimiGo-Lab")
sys.path.insert(0, str(LAB / "execution-information-loop"))
import carrier_loop  # noqa: E402

RUN_ROOT = Path(__file__).resolve().parents[1]
WORLD = RUN_ROOT / "worlds" / "world-a" / "carrier.sqlite"
ANCHOR = RUN_ROOT / "trust" / "settlement-trust-anchor.json"
OUT = RUN_ROOT / "logs" / "off-policy-refusal.json"
ITEM_ID = "TASK-U1"
DEMAND_ID = "task-u1"
EVALUATED_AT = "2026-10-22T04:53:00Z"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def dependency_basis(loop) -> tuple[dict, dict]:
    settlement = loop.current_settlement(ITEM_ID)
    object_ids = dict(settlement["basis"]["dependency_object_ids"])
    values = {}
    for dependency_id in object_ids:
        dependency = loop.current_settlement(dependency_id)
        if dependency is None:
            raise RuntimeError("missing dependency settlement: %s" % dependency_id)
        values[dependency_id] = dependency["result"]["value"]
    return object_ids, values


def reuse_decision(loop, evaluated_at):
    item = loop.current_item(ITEM_ID)
    if item is None:
        raise RuntimeError("missing item: %s" % ITEM_ID)
    object_ids, values = dependency_basis(loop)
    return loop._settlement_reuse_decision(
        loop.current_settlement(ITEM_ID), item, object_ids,
        evaluated_at, values,
    )


def source_reuse_decision(loop, evaluated_at):
    item = loop.current_item("TASK-SOURCE")
    return loop._settlement_reuse_decision(
        loop.current_settlement("TASK-SOURCE"), item, {}, evaluated_at, {},
    )


def main() -> int:
    world_before = sha256_file(WORLD)
    signed_object_id = None
    checks = {}
    evidence = {}

    os.environ.pop("SIMIGO_SETTLEMENT_SIGNING_KEY", None)
    os.environ.pop("SIMIGO_SETTLEMENT_PROVENANCE", None)
    os.environ["SIMIGO_SETTLEMENT_TRUST_ANCHOR"] = str(ANCHOR)

    with tempfile.TemporaryDirectory(prefix="e-off-policy-") as temporary:
        # --- off policy: a signed settlement is unverifiable, not reusable ---
        off_path = Path(temporary) / "off.sqlite"
        shutil.copy2(WORLD, off_path)
        off_loop = carrier_loop.CarrierInformationLoop.open(
            str(off_path), provenance_policy="off"
        )
        try:
            signed = off_loop.current_settlement(ITEM_ID)
            signed_object_id = (signed or {}).get("_object_id")
            off_decision = reuse_decision(off_loop, carrier_loop.parse_utc(EVALUATED_AT))
            off_source_decision = source_reuse_decision(
                off_loop, carrier_loop.parse_utc(EVALUATED_AT)
            )
            calls = []

            def calculator(item_id, source_payload, dependency_values):
                calls.append(item_id)
                return {"off_policy_probe": item_id}

            result = off_loop.execute_demand(
                DEMAND_ID,
                "off-policy-probe",
                calculator,
                evaluated_at_utc=EVALUATED_AT,
            )
            actions = [
                action for action in result.get("actions", [])
                if action.get("item_id") == ITEM_ID
            ]
            action = actions[0] if actions else {}
            replacement = off_loop.current_settlement(ITEM_ID) or {}
            replacement_signature = off_loop.current_settlement_signature(ITEM_ID)
            evidence["off"] = {
                "u1_reuse_decision": list(off_decision),
                "source_reuse_decision": list(off_source_decision),
                "action_reasons": {
                    action.get("item_id"): [action.get("action"), action.get("reason")]
                    for action in result.get("actions", [])
                },
                "demand_action": action.get("action"),
                "demand_reason": action.get("reason"),
                "calculator_calls": list(calls),
                "reused_item_ids": result.get("reused_item_ids"),
                "computed_item_ids": result.get("computed_item_ids"),
                "signed_settlement_object_id": signed_object_id,
                "replacement_settlement_object_id": replacement.get("_object_id"),
                "replacement_has_provenance": "provenance" in replacement,
                "replacement_signature_object_id": (
                    (replacement_signature or {}).get("_object_id")
                ),
                "replacement_signature_declares_object_id": (
                    (replacement_signature or {}).get("settlement_object_id")
                ),
                "policy": off_loop.provenance_policy,
                "trust_anchor_loaded": off_loop.trust_anchor is not None,
                "signer_loaded": off_loop.signer is not None,
            }
            checks["off_policy_refuses_signed_u1_reuse"] = (
                tuple(off_decision) == (False, "SETTLEMENT_SIGNATURE_UNVERIFIABLE")
            )
            checks["off_policy_refuses_signed_source_reuse"] = (
                tuple(off_source_decision) == (False, "SETTLEMENT_SIGNATURE_UNVERIFIABLE")
            )
            checks["off_policy_recomputes_instead_of_reusing"] = (
                action.get("action") == "COMPUTE"
                and not (result.get("reused_item_ids") or [])
                and not any(
                    action.get("action") == "REUSE"
                    for action in result.get("actions", [])
                )
            )
            checks["off_policy_calculator_covers_dependency_closure"] = (
                set(calls) == {"TASK-SOURCE", ITEM_ID}
            )
            checks["off_policy_no_trust_anchor_or_signer"] = (
                off_loop.trust_anchor is None and off_loop.signer is None
            )
            replacement_signature_covers_current = (
                (replacement_signature or {}).get("settlement_object_id")
                == replacement.get("_object_id")
            )
            checks["off_policy_replacement_is_unsigned_and_distinct"] = (
                replacement.get("_object_id") not in (None, signed_object_id)
                and not replacement_signature_covers_current
            )
        finally:
            off_loop.close()

        # --- an off-policy recomputation must not become verifiable later ---
        off_verify_path = Path(temporary) / "off-then-verify.sqlite"
        shutil.copy2(off_path, off_verify_path)
        off_verify_loop = carrier_loop.CarrierInformationLoop.open(
            str(off_verify_path), provenance_policy="verify"
        )
        try:
            off_verify_decision = reuse_decision(
                off_verify_loop, carrier_loop.parse_utc(EVALUATED_AT)
            )
            evidence["off_then_verify"] = {
                "reuse_decision": list(off_verify_decision),
                "policy": off_verify_loop.provenance_policy,
                "trust_anchor_loaded": off_verify_loop.trust_anchor is not None,
            }
            checks["off_recomputation_is_refused_by_verify"] = (
                tuple(off_verify_decision)
                == (False, "SETTLEMENT_SIGNATURE_MISSING")
            )
        finally:
            off_verify_loop.close()

        # --- verify policy: positive control with the run trust anchor ---
        verify_path = Path(temporary) / "verify.sqlite"
        shutil.copy2(WORLD, verify_path)
        verify_loop = carrier_loop.CarrierInformationLoop.open(
            str(verify_path), provenance_policy="verify"
        )
        try:
            verify_decision = reuse_decision(
                verify_loop, carrier_loop.parse_utc(EVALUATED_AT)
            )
            evidence["verify"] = {
                "reuse_decision": list(verify_decision),
                "policy": verify_loop.provenance_policy,
                "trust_anchor_loaded": verify_loop.trust_anchor is not None,
                "signer_loaded": verify_loop.signer is not None,
            }
            checks["verify_policy_reuses_signed_settlement"] = (
                tuple(verify_decision) == (True, None)
            )
            checks["verify_policy_loads_anchor_without_private_key"] = (
                verify_loop.trust_anchor is not None and verify_loop.signer is None
                and "SIMIGO_SETTLEMENT_SIGNING_KEY" not in os.environ
            )
        finally:
            verify_loop.close()

    world_after = sha256_file(WORLD)
    checks["authoritative_world_unchanged"] = world_before == world_after
    evidence["authoritative_world"] = {
        "path": str(WORLD),
        "sha256_before": world_before,
        "sha256_after": world_after,
    }
    report = {
        "schema_id": "SIMIGO-E-ROUND-OFF-POLICY-PROBE-V1",
        "world": str(WORLD),
        "item_id": ITEM_ID,
        "demand_id": DEMAND_ID,
        "checks": checks,
        "evidence": evidence,
        "verdict": "PASS" if all(checks.values()) else "FAIL",
        "not_claimed": [
            "that policy=off is a verification mode",
            "semantic correctness of a signed value",
        ],
    }
    OUT.write_text(json.dumps(report, indent=1, sort_keys=True) + "\n",
                   encoding="utf-8")
    print(json.dumps({
        "verdict": report["verdict"],
        "false_checks": [key for key, value in checks.items() if not value],
        "off": evidence.get("off"),
        "verify": evidence.get("verify"),
        "report": str(OUT),
    }, ensure_ascii=False, indent=1))
    return 0 if report["verdict"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
